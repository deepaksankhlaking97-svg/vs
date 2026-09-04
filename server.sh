#!/usr/bin/env bash
set -Eeuo pipefail

# --- Configuration ---
PANEL_DIR="/opt/kingcloud-panel"
PANEL_SERVICE="kingcloud-panel"
PANEL_PORT=399
SERVER_DIR="/opt/minecraft/server"
PROPS="$SERVER_DIR/server.properties"
RCON_PORT="25575"
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

install_panel_and_rcon() {
    clear_screen
    echo -e "${C_BRIGHT_GREEN}  Starting KingCloud Panel & RCON Installation...${C_RESET}"
    sleep 1

    if [ ! -d "$SERVER_DIR" ] || [ ! -f "$PROPS" ]; then
        print_error "Minecraft server directory or server.properties not found."
        print_info "Expected: $SERVER_DIR"
        read -p "  Press Enter to return to menu..."
        return
    fi

    print_step 1 6 "Configuring Minecraft RCON"
    run_with_spinner "cp '$PROPS' '$PROPS.backup-\$(date +%Y%m%d-%H%M%S)'" "Backing up server.properties"
    
    sed -i '/^[[:space:]]*enable-rcon=/d' "$PROPS"
    sed -i '/^[[:space:]]*rcon.port=/d' "$PROPS"
    sed -i '/^[[:space:]]*rcon.password=/d' "$PROPS"
    
    RCON_PASS="$(python3 -c 'import secrets, string; print("".join(secrets.choice(string.ascii_letters + string.digits) for _ in range(40)))')"
    
    cat >> "$PROPS" <<EOF

# KINGCLOUD RCON
enable-rcon=true
rcon.port=$RCON_PORT
rcon.password=$RCON_PASS
EOF
    chmod 600 "$PROPS"
    print_success "RCON enabled on port $RCON_PORT"
    progress_bar 1.0

    print_step 2 6 "Saving RCON Credentials"
    cat > "$RCON_CONF" <<EOF
RCON_HOST=127.0.0.1
RCON_PORT=$RCON_PORT
RCON_PASSWORD=$RCON_PASS
EOF
    chmod 600 "$RCON_CONF"
    print_success "Credentials saved to $RCON_CONF"
    progress_bar 0.5

    print_step 3 6 "Installing RCON CLI Tools"
    cat > /usr/local/bin/kingcloud-rcon <<'PY'
#!/usr/bin/env python3
import socket, struct, sys, os
CONF="/etc/kingcloud-rcon.conf"
def config():
    c={}
    with open(CONF) as f:
        for line in f:
            line=line.strip()
            if "=" in line:
                k,v=line.split("=",1)
                c[k]=v
    return c
def packet(req, typ, text):
    body=struct.pack("<ii",req,typ)
    body+=text.encode()+b"\x00\x00"
    return struct.pack("<i",len(body))+body
def recv(sock):
    raw=sock.recv(4)
    if len(raw)!=4: raise ConnectionError("RCON closed")
    size=struct.unpack("<i",raw)[0]
    data=b""
    while len(data)<size:
        part=sock.recv(size-len(data))
        if not part: raise ConnectionError("RCON closed")
        data+=part
    req,typ=struct.unpack("<ii",data[:8])
    text=data[8:-2].decode("utf-8","replace")
    return req,typ,text
def main():
    if len(sys.argv)<2:
        print("Usage: kingcloud-rcon <command>")
        sys.exit(1)
    c=config()
    host=c.get("RCON_HOST","127.0.0.1")
    port=int(c.get("RCON_PORT","25575"))
    password=c.get("RCON_PASSWORD","")
    command=" ".join(sys.argv[1:])
    s=socket.create_connection((host,port),timeout=8)
    try:
        s.sendall(packet(1,3,password))
        req,typ,text=recv(s)
        if req == -1:
            print("✖ Auth failed")
            sys.exit(2)
        s.sendall(packet(2,2,command))
        result=[]
        s.settimeout(1)
        while True:
            try:
                req,typ,text=recv(s)
                if text: result.append(text)
            except socket.timeout: break
        print("".join(result).rstrip())
    finally:
        s.close()
if __name__=="__main__": main()
PY
    chmod +x /usr/local/bin/kingcloud-rcon
    ln -sf /usr/local/bin/kingcloud-rcon /usr/local/bin/mc-rcon
    print_success "kingcloud-rcon and mc-rcon installed"
    progress_bar 1.0

    print_step 4 6 "Setting up Web Panel"
    mkdir -p "$PANEL_DIR"
    
    cat > "$PANEL_DIR/rcon_bridge.py" <<'PY'
#!/usr/bin/env python3
import socket, struct
CONF="/etc/kingcloud-rcon.conf"
def load_config():
    c={}
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
    payload=data[8:-2].decode("utf-8", errors="replace")
    return request_id,packet_type,payload
def execute(command):
    c=load_config()
    host=c.get("RCON_HOST","127.0.0.1")
    port=int(c.get("RCON_PORT","25575"))
    password=c.get("RCON_PASSWORD","")
    sock=socket.create_connection((host,port),timeout=8)
    try:
        sock.sendall(make_packet(100, 3, password))
        request_id,packet_type,payload=receive(sock)
        if request_id == -1: raise PermissionError("Auth failed")
        sock.sendall(make_packet(101, 2, command))
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

    cat > "$PANEL_DIR/app.py" <<PY
#!/usr/bin/env python3
import http.server, socketserver, json, sys, os, urllib.parse
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rcon_bridge

PORT = $PANEL_PORT
RCON_PORT = $RCON_PORT

class PanelHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/' or self.path == '/index.html':
            self.send_response(200)
            self.send_header('Content-type', 'text/html')
            self.end_headers()
            html = """<!DOCTYPE html>
<html>
<head>
    <title>KingCloud Panel</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: #0f172a; color: #e2e8f0; margin: 0; padding: 20px; display: flex; flex-direction: column; align-items: center; }
        .container { max-width: 800px; width: 100%; background: #1e293b; padding: 30px; border-radius: 12px; box-shadow: 0 10px 25px rgba(0,0,0,0.5); }
        h1 { color: #38bdf8; text-align: center; margin-top: 0; }
        .input-group { display: flex; gap: 10px; margin-bottom: 20px; }
        input { flex: 1; padding: 12px; font-size: 16px; border-radius: 6px; border: 1px solid #334155; background: #0f172a; color: #f8fafc; outline: none; }
        input:focus { border-color: #38bdf8; }
        button { padding: 12px 24px; font-size: 16px; border-radius: 6px; border: none; background: #38bdf8; color: #0f172a; cursor: pointer; font-weight: bold; transition: background 0.2s; }
        button:hover { background: #0ea5e9; }
        pre { background: #0f172a; padding: 20px; border-radius: 8px; min-height: 200px; max-height: 400px; overflow-y: auto; border: 1px solid #334155; white-space: pre-wrap; word-wrap: break-word; color: #a3e635; font-family: 'Consolas', 'Monaco', monospace; }
        .status { text-align: center; color: #94a3b8; font-size: 14px; margin-top: 15px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>⚡ KingCloud Live Console</h1>
        <div class="input-group">
            <input type="text" id="cmd" placeholder="Enter Minecraft command (e.g., list, say Hello)" autofocus>
            <button onclick="sendCmd()">Execute</button>
        </div>
        <pre id="output">Waiting for command...</pre>
        <div class="status">Connected to RCON on port """ + str(RCON_PORT) + """</div>
    </div>
    <script>
        const cmdInput = document.getElementById('cmd');
        const output = document.getElementById('output');
        cmdInput.addEventListener('keypress', function(e) { if (e.key === 'Enter') sendCmd(); });
        async function sendCmd() {
            const cmd = cmdInput.value.trim();
            if (!cmd) return;
            output.textContent = 'Executing...';
            output.style.color = '#fbbf24';
            try {
                const res = await fetch('/api/command?cmd=' + encodeURIComponent(cmd));
                const data = await res.json();
                if (data.error) {
                    output.textContent = 'Error: ' + data.error;
                    output.style.color = '#f87171';
                } else {
                    output.textContent = data.result || 'Command executed successfully (no output).';
                    output.style.color = '#a3e635';
                }
            } catch (e) {
                output.textContent = 'Network Error: ' + e.message;
                output.style.color = '#f87171';
            }
            cmdInput.value = '';
            cmdInput.focus();
        }
    </script>
</body>
</html>"""
            self.wfile.write(html.encode())
        elif self.path.startswith('/api/command'):
            parsed = urllib.parse.urlparse(self.path)
            params = urllib.parse.parse_qs(parsed.query)
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

if __name__ == '__main__':
    with socketserver.TCPServer(("", PORT), PanelHandler) as httpd:
        print(f"Panel running on port {PORT}")
        httpd.serve_forever()
PY

    chmod 644 "$PANEL_DIR/rcon_bridge.py"
    chmod +x "$PANEL_DIR/app.py"
    print_success "Panel files created in $PANEL_DIR"
    progress_bar 1.0

    print_step 5 6 "Configuring Systemd Service"
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
    run_with_spinner "systemctl enable $PANEL_SERVICE" "Enabling service"
    print_success "Service configured"
    progress_bar 0.5

    print_step 6 6 "Starting Services & Testing"
    if systemctl list-unit-files 2>/dev/null | grep -q "^minecraft.service"; then
        run_with_spinner "systemctl restart minecraft" "Restarting Minecraft"
    else
        print_warning "minecraft.service not found. Skipping Minecraft restart."
    fi
    
    run_with_spinner "systemctl restart $PANEL_SERVICE" "Starting Panel"
    
    sleep 3
    local attempts=0
    while [ $attempts -lt 3 ]; do
        if /usr/local/bin/kingcloud-rcon list > /tmp/rcon_test.txt 2>&1; then
            print_success "RCON connection successful!"
            break
        fi
        attempts=$((attempts + 1))
        sleep 2
    done
    rm -f /tmp/rcon_test.txt

    echo
    echo -e "${C_BRIGHT_GREEN}  ═══════════════════════════════════════════════════════${C_RESET}"
    print_success "Installation Complete!"
    print_info "Panel URL: ${C_BRIGHT_WHITE}http://<your-ip>:$PANEL_PORT${C_RESET}"
    print_info "CLI Tool:  ${C_BRIGHT_WHITE}kingcloud-rcon <command>${C_RESET}"
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
        read -p "  Press Enter to return to menu..."
        return
    fi

    if ss -tuln | grep -q ":$NEW_PORT "; then
        print_error "Port $NEW_PORT is already in use."
        read -p "  Press Enter to return to menu..."
        return
    fi

    print_step 1 2 "Updating Configuration"
    if [ -f "$PANEL_DIR/app.py" ]; then
        sed -i "s/^PORT = .*/PORT = $NEW_PORT/" "$PANEL_DIR/app.py"
        print_success "Updated app.py to port $NEW_PORT"
    else
        print_error "app.py not found. Is the panel installed?"
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

uninstall_panel() {
    clear_screen
    echo -e "${C_BRIGHT_RED}  Uninstalling KingCloud Panel...${C_RESET}"
    sleep 1
    
    print_step 1 4 "Stopping Services"
    run_with_spinner "systemctl stop $PANEL_SERVICE 2>/dev/null || true" "Stopping $PANEL_SERVICE"
    run_with_spinner "systemctl disable $PANEL_SERVICE 2>/dev/null || true" "Disabling $PANEL_SERVICE"
    
    print_step 2 4 "Removing Panel Files"
    run_with_spinner "rm -rf $PANEL_DIR" "Removing $PANEL_DIR"
    run_with_spinner "rm -f /etc/systemd/system/$PANEL_SERVICE.service" "Removing systemd service"
    run_with_spinner "systemctl daemon-reload" "Reloading systemd"
    
    print_step 3 4 "Removing RCON Configuration"
    run_with_spinner "rm -f $RCON_CONF" "Removing $RCON_CONF"
    run_with_spinner "rm -f /usr/local/bin/kingcloud-rcon" "Removing kingcloud-rcon CLI"
    run_with_spinner "rm -f /usr/local/bin/mc-rcon" "Removing mc-rcon CLI"
    
    print_step 4 4 "Disabling RCON in Minecraft"
    if [ -f "$PROPS" ]; then
        sed -i 's/^enable-rcon=true/enable-rcon=false/' "$PROPS"
        print_success "RCON disabled in server.properties"
    fi
    
    echo
    echo -e "${C_BRIGHT_GREEN}  ═══════════════════════════════════════════════════════${C_RESET}"
    print_success "Panel and RCON uninstalled successfully!"
    echo -e "${C_BRIGHT_GREEN}  ═══════════════════════════════════════════════════════${C_RESET}"
    echo
    read -p "  Press Enter to return to menu..."
}

show_menu() {
    clear_screen
    echo -e "${C_BRIGHT_CYAN}"
    cat << "EOF"
  _  __     _ _   _  __ _ _      _     _       ____ _                _           
 | |/ /   _| | | | |/ /(_) | ___| |__ | |     / ___| |__   ___  __ _| | __ _ _ __ 
 | ' / | | | | | | ' / | | |/ _ \ '_ \| |    | |   | '_ \ / _ \/ _` | |/ _` | '__|
 | . \ |_| | | | | . \ | | |  __/ |_) | | ___| |___| | | |  __/ (_| | | (_| | |   
 |_|\_\__,_|_|_| |_|\_\|_|_|\___|_.__/|_|(_)  \____|_| |_|\___|\__,_|_|\__,_|_|   
EOF
    echo -e "${C_RESET}"
    echo -e "${C_BRIGHT_CYAN}  ═══════════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_BOLD}${C_WHITE}               KINGCLOUD MINECRAFT MANAGEMENT SUITE               ${C_RESET}"
    echo -e "${C_BRIGHT_CYAN}  ═══════════════════════════════════════════════════════════════════${C_RESET}"
    echo
    echo -e "  ${C_BRIGHT_WHITE}Please select an option:${C_RESET}"
    echo
    echo -e "  ${C_BRIGHT_CYAN}[1]${C_RESET} ${C_WHITE}Install / Fix Panel & RCON${C_RESET}      ${C_DIM}(Full Setup & Auto-Fix)${C_RESET}"
    echo -e "  ${C_BRIGHT_CYAN}[2]${C_RESET} ${C_WHITE}Restart Panel${C_RESET}                   ${C_DIM}(Restart Web Service)${C_RESET}"
    echo -e "  ${C_BRIGHT_CYAN}[3]${C_RESET} ${C_WHITE}Change Panel Port${C_RESET}               ${C_DIM}(Current: $PANEL_PORT)${C_RESET}"
    echo -e "  ${C_BRIGHT_CYAN}[4]${C_RESET} ${C_WHITE}Uninstall Panel${C_RESET}                 ${C_DIM}(Remove All Components)${C_RESET}"
    echo -e "  ${C_BRIGHT_CYAN}[5]${C_RESET} ${C_WHITE}Exit${C_RESET}"
    echo
    echo -ne "  ${C_BRIGHT_YELLOW}Enter choice [1-5]: ${C_RESET}"
    read -r choice
    
    case $choice in
        1) install_panel_and_rcon ;;
        2) restart_panel ;;
        3) change_panel_port ;;
        4) uninstall_panel ;;
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
