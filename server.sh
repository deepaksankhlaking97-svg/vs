#!/usr/bin/env bash
set -Eeuo pipefail

# --- Configuration ---
PANEL_DIR="/opt/kingcloud-panel"
PANEL_PORT=399
PANEL_SERVICE="kingcloud-panel"
SERVER_BASE_DIR="/opt/minecraft"
RCON_CONF="/etc/kingcloud-rcon.conf"

# --- TUI Engine: Colors & Styles ---
C_RESET="\e[0m"
C_BOLD="\e[1m"
C_DIM="\e[2m"
C_RED="\e[31m"
C_GREEN="\e[32m"
C_YELLOW="\e[33m"
C_BLUE="\e[34m"
C_MAGENTA="\e[35m"
C_CYAN="\e[36m"
C_WHITE="\e[37m"
C_BRIGHT_RED="\e[91m"
C_BRIGHT_GREEN="\e[92m"
C_BRIGHT_YELLOW="\e[93m"
C_BRIGHT_BLUE="\e[94m"
C_BRIGHT_MAGENTA="\e[95m"
C_BRIGHT_CYAN="\e[96m"
C_BRIGHT_WHITE="\e[97m"

hide_cursor() { echo -ne "\e[?25l"; }
show_cursor() { echo -ne "\e[?25h"; }
trap 'show_cursor; echo -ne "${C_RESET}"; exit' INT TERM EXIT
clear_screen() { echo -ne "\e[2J\e[H"; }

# --- Animation Functions ---
run_with_spinner() {
    local cmd="$1"
    local msg="$2"
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local delay=0.08
    echo -ne "${C_BRIGHT_CYAN}  ${msg} ${C_RESET}"
    eval "$cmd" > /dev/null 2>&1 &
    local pid=$!
    while kill -0 $pid 2>/dev/null; do
        local temp=${spinstr#?}
        printf "\r${C_BRIGHT_CYAN}  [%s] %s ${C_RESET}" "$spinstr" "$msg"
        spinstr=$temp${spinstr%"$temp"}
        sleep $delay
    done
    wait $pid
    local status=$?
    if [ $status -eq 0 ]; then
        printf "\r${C_BRIGHT_GREEN}  [✓] %s ${C_RESET}\n" "$msg"
    else
        printf "\r${C_BRIGHT_RED}  [✗] %s ${C_RESET}\n" "$msg"
    fi
    return $status
}

progress_bar() {
    local duration=$1
    local width=40
    local interval=$(awk "BEGIN {print $duration / $width}")
    for (( i=0; i<=width; i++ )); do
        local pct=$(( i * 100 / width ))
        local bar=$(printf "%${i}s" | tr ' ' '█')
        local empty=$(printf "%$((width-i))s" | tr ' ' '░')
        local color=$C_BRIGHT_CYAN
        if (( pct > 30 )); then color=$C_BRIGHT_GREEN; fi
        if (( pct > 70 )); then color=$C_BRIGHT_YELLOW; fi
        if (( pct == 100 )); then color=$C_BRIGHT_MAGENTA; fi
        printf "\r  ${color}[%s%s] %3d%%${C_RESET}" "$bar" "$empty" "$pct"
        sleep "$interval"
    done
    echo
}

print_step() {
    echo -e "${C_BRIGHT_YELLOW}  ──[ ${C_BRIGHT_WHITE}${1}/${2}${C_BRIGHT_YELLOW} ] ${C_BOLD}${C_WHITE}${3}${C_RESET}"
}
print_success() { echo -e "  ${C_BRIGHT_GREEN}✓ ${1}${C_RESET}"; }
print_error() { echo -e "  ${C_BRIGHT_RED}✗ ${1}${C_RESET}"; }
print_info() { echo -e "  ${C_BRIGHT_CYAN}ℹ ${1}${C_RESET}"; }
print_warning() { echo -e "  ${C_BRIGHT_YELLOW}⚠ ${1}${C_RESET}"; }

# --- Core Functions ---

install_panel() {
    clear_screen
    echo -e "${C_BRIGHT_GREEN}  Starting Panel Installation & Fix...${C_RESET}"
    sleep 1

    print_step 1 5 "Setting up Panel Directory"
    mkdir -p "$PANEL_DIR"
    print_success "Directory ready: $PANEL_DIR"
    progress_bar 0.5

    print_step 2 5 "Installing RCON Bridge"
    cat > "$PANEL_DIR/rcon_bridge.py" <<'PY'
#!/usr/bin/env python3
import socket, struct, os
CONF="/etc/kingcloud-rcon.conf"
def load_config():
    c={}
    if not os.path.exists(CONF): return c
    with open(CONF) as f:
        for line in f:
            line=line.strip()
            if "=" in line:
                k,v=line.split("=",1)
                c[k]=v
    return c
def make_packet(request_id, packet_type, payload):
    body=struct.pack("<ii",request_id,packet_type)
    body+=payload.encode("utf-8")+b"\x00\x00"
    return struct.pack("<i",len(body))+body
def receive(sock):
    raw=sock.recv(4)
    if len(raw)!=4: raise ConnectionError("RCON closed")
    size=struct.unpack("<i",raw)[0]
    data=b""
    while len(data)<size:
        chunk=sock.recv(size-len(data))
        if not chunk: raise ConnectionError("RCON closed")
        data+=chunk
    request_id,packet_type=struct.unpack("<ii",data[:8])
    payload=data[8:-2].decode("utf-8","replace")
    return request_id,packet_type,payload
def execute(command):
    c=load_config()
    host=c.get("RCON_HOST","127.0.0.1")
    port=int(c.get("RCON_PORT","25575"))
    password=c.get("RCON_PASSWORD","")
    sock=socket.create_connection((host,port),timeout=8)
    try:
        sock.sendall(make_packet(100,3,password))
        request_id,packet_type,payload=receive(sock)
        if request_id == -1: raise PermissionError("Auth failed")
        sock.sendall(make_packet(101,2,command))
        output=[]
        sock.settimeout(1)
        while True:
            try:
                _,_,payload=receive(sock)
                if payload: output.append(payload)
            except socket.timeout: break
        return "".join(output).strip()
    finally:
        sock.close()
PY
    chmod 644 "$PANEL_DIR/rcon_bridge.py"
    print_success "RCON Bridge installed"
    progress_bar 0.8

    print_step 3 5 "Creating Web Panel Application"
    cat > "$PANEL_DIR/app.py" <<PY
#!/usr/bin/env python3
import http.server
import socketserver
import json
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rcon_bridge

PORT = $PANEL_PORT

class PanelHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/' or self.path == '/index.html':
            self.send_response(200)
            self.send_header('Content-type', 'text/html')
            self.end_headers()
            html = """
            <!DOCTYPE html>
            <html><head><title>KingCloud Panel</title>
            <style>
                body { font-family: sans-serif; background: #1e1e2e; color: #cdd6f4; padding: 20px; }
                h1 { color: #89b4fa; }
                input, button { padding: 10px; font-size: 16px; border-radius: 5px; border: none; }
                input { width: 300px; background: #313244; color: #cdd6f4; }
                button { background: #89b4fa; color: #1e1e2e; cursor: pointer; font-weight: bold; }
                pre { background: #313244; padding: 15px; border-radius: 5px; min-height: 100px; }
            </style>
            </head><body>
            <h1>KingCloud Minecraft Panel</h1>
            <form id="cmdForm">
                <input type="text" id="cmd" placeholder="Enter command...">
                <button type="submit">Execute</button>
            </form>
            <pre id="output">Waiting for command...</pre>
            <script>
                document.getElementById('cmdForm').onsubmit = async (e) => {
                    e.preventDefault();
                    const cmd = document.getElementById('cmd').value;
                    const res = await fetch('/api/command?cmd=' + encodeURIComponent(cmd));
                    const data = await res.json();
                    document.getElementById('output').textContent = data.result || data.error;
                };
            </script>
            </body></html>
            """
            self.wfile.write(html.encode())
        elif self.path.startswith('/api/command'):
            from urllib.parse import urlparse, parse_qs
            parsed = urlparse(self.path)
            params = parse_qs(parsed.query)
            cmd = params.get('cmd', [''])[0]
            try:
                result = rcon_bridge.execute(cmd)
                self.send_response(200)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({"result": result}).encode())
            except Exception as e:
                self.send_response(500)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({"error": str(e)}).encode())
        else:
            self.send_response(404)
            self.end_headers()
    def log_message(self, format, *args): pass

with socketserver.TCPServer(("", PORT), PanelHandler) as httpd:
    print(f"Panel running on port {PORT}")
    httpd.serve_forever()
PY
    chmod +x "$PANEL_DIR/app.py"
    print_success "Web Panel created (Port: $PANEL_PORT)"
    progress_bar 1.0

    print_step 4 5 "Configuring Systemd Service"
    cat > /etc/systemd/system/$PANEL_SERVICE.service <<EOF
[Unit]
Description=KingCloud Minecraft Panel
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$PANEL_DIR
ExecStart=/usr/bin/python3 $PANEL_DIR/app.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    run_with_spinner "systemctl daemon-reload" "Reloading systemd"
    print_success "Service configured"
    progress_bar 0.5

    print_step 5 5 "Starting Panel"
    run_with_spinner "systemctl enable --now $PANEL_SERVICE" "Starting $PANEL_SERVICE"
    
    echo
    echo -e "${C_BRIGHT_GREEN}  ═══════════════════════════════════════════════════════${C_RESET}"
    print_success "Panel installed and running!"
    print_info "Access panel at: ${C_BRIGHT_WHITE}http://<your-ip>:$PANEL_PORT${C_RESET}"
    echo -e "${C_BRIGHT_GREEN}  ═══════════════════════════════════════════════════════${C_RESET}"
    echo
    read -p "  Press Enter to return to menu..."
}

create_server() {
    clear_screen
    echo -e "${C_BRIGHT_GREEN}  Starting Server Creation Wizard...${C_RESET}"
    sleep 1

    print_step 1 4 "Scanning Available Ports"
    local available_ports=()
    for (( p=25565; p<=25575; p++ )); do
        if ! ss -tuln | grep -q ":$p "; then
            available_ports+=($p)
        fi
    done

    if [ ${#available_ports[@]} -eq 0 ]; then
        print_error "No available ports found in range 25565-25575."
        echo
        read -p "  Press Enter to return to menu..."
        return
    fi

    print_success "Found ${#available_ports[@]} available ports"
    progress_bar 0.8

    print_step 2 4 "Select Server Port"
    echo -e "  ${C_BRIGHT_WHITE}Available Ports:${C_RESET}"
    for i in "${!available_ports[@]}"; do
        echo -e "  ${C_BRIGHT_CYAN}[$((i+1))]${C_RESET} ${C_WHITE}Port ${available_ports[$i]}${C_RESET}"
    done
    echo -e "  ${C_BRIGHT_CYAN}[0]${C_RESET} ${C_WHITE}Cancel${C_RESET}"
    echo
    echo -ne "  ${C_BRIGHT_YELLOW}Select port [1-${#available_ports[@]}]: ${C_RESET}"
    read -r choice

    if [[ "$choice" == "0" ]]; then
        print_warning "Cancelled."
        echo
        read -p "  Press Enter to return to menu..."
        return
    fi

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#available_ports[@]} ]; then
        print_error "Invalid selection."
        echo
        read -p "  Press Enter to return to menu..."
        return
    fi

    local SELECTED_PORT=${available_ports[$((choice-1))]}
    local SERVER_DIR="$SERVER_BASE_DIR/server_$SELECTED_PORT"
    local SERVER_NAME="minecraft-$SELECTED_PORT"
    
    print_success "Selected Port: $SELECTED_PORT"
    progress_bar 0.5

    print_step 3 4 "Setting up Server Directory"
    mkdir -p "$SERVER_DIR"
    
    # Generate RCON password
    local RCON_PASS="$(python3 -c 'import secrets, string; print("".join(secrets.choice(string.ascii_letters + string.digits) for _ in range(40)))')"
    local RCON_PORT=$((SELECTED_PORT + 1000)) # e.g., 25565 -> 26565

    cat > "$SERVER_DIR/server.properties" <<EOF
# KingCloud Auto-Generated
server-port=$SELECTED_PORT
enable-rcon=true
rcon.port=$RCON_PORT
rcon.password=$RCON_PASS
motd=KingCloud Server on Port $SELECTED_PORT
EOF
    chmod 600 "$SERVER_DIR/server.properties"
    print_success "server.properties created"
    progress_bar 0.8

    print_step 4 4 "Creating Systemd Service"
    # Note: Assuming server.jar exists or user will place it. 
    # For a real setup, you'd download the jar here.
    if [ ! -f "$SERVER_DIR/server.jar" ]; then
        print_warning "server.jar not found. Please place it in $SERVER_DIR"
    fi

    cat > /etc/systemd/system/$SERVER_NAME.service <<EOF
[Unit]
Description=Minecraft Server (Port $SELECTED_PORT)
After=network.target

[Service]
User=root
WorkingDirectory=$SERVER_DIR
ExecStart=/usr/bin/java -Xmx2G -Xms1G -jar server.jar nogui
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    run_with_spinner "systemctl daemon-reload" "Reloading systemd"
    run_with_spinner "systemctl enable $SERVER_NAME" "Enabling service"
    
    echo
    echo -e "${C_BRIGHT_GREEN}  ═══════════════════════════════════════════════════════${C_RESET}"
    print_success "Server created successfully!"
    print_info "Directory: ${C_BRIGHT_WHITE}$SERVER_DIR${C_RESET}"
    print_info "Game Port: ${C_BRIGHT_WHITE}$SELECTED_PORT${C_RESET}"
    print_info "RCON Port: ${C_BRIGHT_WHITE}$RCON_PORT${C_RESET}"
    print_info "Service:   ${C_BRIGHT_WHITE}$SERVER_NAME${C_RESET}"
    echo
    print_warning "Remember to place server.jar in the directory and start it:"
    echo -e "    ${C_BRIGHT_CYAN}systemctl start $SERVER_NAME${C_RESET}"
    echo -e "${C_BRIGHT_GREEN}  ═══════════════════════════════════════════════════════${C_RESET}"
    echo
    read -p "  Press Enter to return to menu..."
}

restart_panel() {
    clear_screen
    echo -e "${C_BRIGHT_GREEN}  Restarting Panel...${C_RESET}"
    sleep 1
    
    if systemctl list-unit-files 2>/dev/null | grep -q "^$PANEL_SERVICE.service"; then
        run_with_spinner "systemctl restart $PANEL_SERVICE" "Restarting $PANEL_SERVICE"
        sleep 1
        if systemctl is-active --quiet $PANEL_SERVICE; then
            print_success "Panel restarted successfully!"
        else
            print_error "Panel failed to restart."
            systemctl status $PANEL_SERVICE --no-pager -l || true
        fi
    else
        print_error "Panel service not found. Run option 1 to install."
    fi
    echo
    read -p "  Press Enter to return to menu..."
}

change_panel_port() {
    clear_screen
    echo -e "${C_BRIGHT_GREEN}  Change Panel Port${C_RESET}"
    echo
    print_info "Current port: ${C_BRIGHT_WHITE}$PANEL_PORT${C_RESET}"
    echo -ne "  ${C_BRIGHT_YELLOW}Enter new port (default 399): ${C_RESET}"
    read -r NEW_PORT
    
    NEW_PORT=${NEW_PORT:-399}
    
    if ! [[ "$NEW_PORT" =~ ^[0-9]+$ ]] || [ "$NEW_PORT" -lt 1 ] || [ "$NEW_PORT" -gt 65535 ]; then
        print_error "Invalid port number."
        echo
        read -p "  Press Enter to return to menu..."
        return
    fi

    if ss -tuln | grep -q ":$NEW_PORT "; then
        print_error "Port $NEW_PORT is already in use."
        echo
        read -p "  Press Enter to return to menu..."
        return
    fi

    print_step 1 2 "Updating Configuration"
    if [ -f "$PANEL_DIR/app.py" ]; then
        sed -i "s/^PORT = .*/PORT = $NEW_PORT/" "$PANEL_DIR/app.py"
        print_success "Updated app.py to port $NEW_PORT"
    else
        print_error "app.py not found. Is the panel installed?"
        echo
        read -p "  Press Enter to return to menu..."
        return
    fi
    progress_bar 0.5

    print_step 2 2 "Restarting Panel"
    run_with_spinner "systemctl restart $PANEL_SERVICE" "Restarting $PANEL_SERVICE"
    
    echo
    echo -e "${C_BRIGHT_GREEN}  ═══════════════════════════════════════════════════════${C_RESET}"
    print_success "Panel port changed to ${C_BRIGHT_WHITE}$NEW_PORT${C_RESET}"
    print_info "Access panel at: ${C_BRIGHT_WHITE}http://<your-ip>:$NEW_PORT${C_RESET}"
    echo -e "${C_BRIGHT_GREEN}  ═══════════════════════════════════════════════════════${C_RESET}"
    echo
    read -p "  Press Enter to return to menu..."
}

show_menu() {
    clear_screen
    echo -e "${C_BRIGHT_MAGENTA}"
    cat << "EOF"
  _  __     _ _   _  __ _ _      _     _ 
 | |/ /   _| | | | |/ /(_) | ___| |__ | |
 | ' / | | | | | | ' / | | |/ _ \ '_ \| |
 | . \ |_| | | | | . \ | | |  __/ |_) | |
 |_|\_\__,_|_|_| |_|\_\|_|_|\___|_.__/|_|
EOF
    echo -e "${C_RESET}"
    echo -e "${C_BRIGHT_CYAN}  ═══════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_BOLD}${C_WHITE}       KINGCLOUD MINECRAFT MANAGEMENT SUITE       ${C_RESET}"
    echo -e "${C_BRIGHT_CYAN}  ═══════════════════════════════════════════════════════${C_RESET}"
    echo
    echo -e "  ${C_BRIGHT_WHITE}Please select an option:${C_RESET}"
    echo
    echo -e "  ${C_BRIGHT_CYAN}[1]${C_RESET} ${C_WHITE}Install & Fix Panel + RCON${C_RESET}      ${C_DIM}(Full Setup)${C_RESET}"
    echo -e "  ${C_BRIGHT_CYAN}[2]${C_RESET} ${C_WHITE}Create New Server${C_RESET}               ${C_DIM}(Port Selection)${C_RESET}"
    echo -e "  ${C_BRIGHT_CYAN}[3]${C_RESET} ${C_WHITE}Restart Panel${C_RESET}"
    echo -e "  ${C_BRIGHT_CYAN}[4]${C_RESET} ${C_WHITE}Change Panel Port${C_RESET}               ${C_DIM}(Current: $PANEL_PORT)${C_RESET}"
    echo -e "  ${C_BRIGHT_CYAN}[5]${C_RESET} ${C_WHITE}Exit${C_RESET}"
    echo
    echo -ne "  ${C_BRIGHT_YELLOW}Enter choice [1-5]: ${C_RESET}"
    read -r choice
    
    case $choice in
        1) install_panel ;;
        2) create_server ;;
        3) restart_panel ;;
        4) change_panel_port ;;
        5) clear_screen; exit 0 ;;
        *) 
            print_error "Invalid choice."
            sleep 1
            ;;
    esac
}

# --- Main Execution ---
main() {
    if [ "$(id -u)" != "0" ]; then
        clear_screen
        print_error "This script must be run as root."
        exit 1
    fi

    hide_cursor
    while true; do
        show_menu
    done
}

main "$@"
