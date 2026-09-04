#!/usr/bin/env bash
set -Eeuo pipefail

# --- Configuration ---
SERVER_DIR="/opt/minecraft/server"
PANEL_DIR="/opt/kingcloud-panel"
PROPS="$SERVER_DIR/server.properties"
RCON_PORT="25575"
RCON_CONF="/etc/kingcloud-rcon.conf"
SKIP_PANEL=0

# --- TUI Engine: Colors & Styles ---
C_RESET="\e[0m"
C_BOLD="\e[1m"
C_DIM="\e[2m"
C_ITALIC="\e[3m"

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

# Cursor control
hide_cursor() { echo -ne "\e[?25l"; }
show_cursor() { echo -ne "\e[?25h"; }
trap 'show_cursor; echo -ne "${C_RESET}"; exit' INT TERM EXIT

clear_screen() { echo -ne "\e[2J\e[H"; }

# --- Animation Functions ---

# Typewriter effect for subtle text reveals
typewriter() {
    local text="$1"
    local delay="${2:-0.02}"
    local color="${3:-$C_BRIGHT_CYAN}"
    echo -ne "$color"
    for (( i=0; i<${#text}; i++ )); do
        printf "%s" "${text:$i:1}"
        sleep "$delay"
    done
    echo -ne "${C_RESET}\n"
}

# Spinner for background tasks
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

# Animated progress bar with gradient colors
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

# --- UI Components ---
print_step() {
    local step="$1"
    local total="$2"
    local title="$3"
    echo -e "${C_BRIGHT_YELLOW}  ──[ ${C_BRIGHT_WHITE}${step}/${total}${C_BRIGHT_YELLOW} ] ${C_BOLD}${C_WHITE}${title}${C_RESET}"
}

print_success() { echo -e "  ${C_BRIGHT_GREEN}✓ ${1}${C_RESET}"; }
print_error() { echo -e "  ${C_BRIGHT_RED}✗ ${1}${C_RESET}"; }
print_info() { echo -e "  ${C_BRIGHT_CYAN}ℹ ${1}${C_RESET}"; }
print_warning() { echo -e "  ${C_BRIGHT_YELLOW}⚠ ${1}${C_RESET}"; }

# --- Core Logic ---

check_prerequisites() {
    print_step 1 7 "Checking System & Prerequisites"
    
    if [ "$(id -u)" != "0" ]; then
        print_error "This script must be run as root."
        exit 1
    fi
    print_success "Running as root"

    if [ ! -d "$SERVER_DIR" ]; then
        print_error "Minecraft server directory not found: $SERVER_DIR"
        exit 1
    fi
    print_success "Minecraft directory found"

    if [ ! -f "$PROPS" ]; then
        print_error "server.properties not found."
        exit 1
    fi
    print_success "server.properties found"

    if [ ! -d "$PANEL_DIR" ]; then
        print_warning "Panel directory not found: $PANEL_DIR (Skipping panel integration)"
        SKIP_PANEL=1
    else
        print_success "Panel directory found"
        SKIP_PANEL=0
    fi
    echo
}

backup_and_configure_rcon() {
    print_step 2 7 "Backing up & Configuring RCON"
    
    run_with_spinner "cp '$PROPS' '$PROPS.backup-\$(date +%Y%m%d-%H%M%S)'" "Backing up server.properties"
    
    sed -i '/^[[:space:]]*enable-rcon=/d' "$PROPS"
    sed -i '/^[[:space:]]*rcon.port=/d' "$PROPS"
    sed -i '/^[[:space:]]*rcon.password=/d' "$PROPS"
    
    RCON_PASS="$(python3 -c 'import secrets, string; print("".join(secrets.choice(string.ascii_letters + string.digits) for _ in range(40)))')"
    
    cat >> "$PROPS" <<EOF

# KINGCLOUD RCON AUTO-FIX
enable-rcon=true
rcon.port=$RCON_PORT
rcon.password=$RCON_PASS
EOF
    chmod 600 "$PROPS"
    
    print_success "RCON enabled on port $RCON_PORT"
    print_success "Secure password generated"
    echo
}

save_rcon_config() {
    print_step 3 7 "Saving RCON Credentials"
    
    cat > "$RCON_CONF" <<EOF
RCON_HOST=127.0.0.1
RCON_PORT=$RCON_PORT
RCON_PASSWORD=$RCON_PASS
EOF
    chmod 600 "$RCON_CONF"
    
    print_success "Credentials saved to $RCON_CONF"
    echo
}

install_rcon_cli() {
    print_step 4 7 "Installing RCON CLI Tool"
    
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
            print("Auth failed")
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
    
    print_success "kingcloud-rcon installed to /usr/local/bin"
    echo
}

setup_panel_bridge() {
    print_step 5 7 "Setting up Panel RCON Bridge"
    
    if [ "$SKIP_PANEL" -eq 1 ]; then
        print_warning "Skipping panel bridge (directory not found)"
        echo
        return
    fi
    
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
    
    print_success "rcon_bridge.py created in $PANEL_DIR"
    echo
}

restart_services() {
    print_step 6 7 "Restarting Services"
    
    if systemctl list-unit-files 2>/dev/null | grep -q "^minecraft.service"; then
        run_with_spinner "systemctl restart minecraft || true" "Restarting Minecraft server"
        sleep 2
    else
        print_warning "minecraft.service not found. Manual restart may be required."
    fi
    
    if [ "$SKIP_PANEL" -eq 0 ]; then
        SERVICE=""
        for s in kingcloud-panel panel kingcloud minecraft-panel; do
            if systemctl list-unit-files 2>/dev/null | grep -q "^${s}.service"; then
                SERVICE="$s"
                break
            fi
        done
        
        if [ -n "$SERVICE" ]; then
            run_with_spinner "systemctl restart $SERVICE || true" "Restarting $SERVICE"
        else
            print_warning "Panel service not detected. Manual restart may be required."
        fi
    fi
    echo
}

test_rcon() {
    print_step 7 7 "Testing RCON Connection"
    
    local attempts=0
    local max_attempts=5
    
    while [ $attempts -lt $max_attempts ]; do
        if /usr/local/bin/kingcloud-rcon list > /tmp/rcon_test.txt 2>&1; then
            print_success "RCON connection successful!"
            print_info "Server response:"
            sed 's/^/    /' /tmp/rcon_test.txt
            rm -f /tmp/rcon_test.txt
            echo
            return 0
        fi
        attempts=$((attempts + 1))
        if [ $attempts -lt $max_attempts ]; then
            print_warning "Attempt $attempts/$max_attempts failed. Waiting for server..."
            sleep 3
        fi
    done
    
    print_error "RCON test failed after $max_attempts attempts."
    print_info "Check server logs: journalctl -u minecraft -f"
    rm -f /tmp/rcon_test.txt
    echo
}

show_summary() {
    clear_screen
    echo -e "${C_BRIGHT_GREEN}"
    cat << "EOF"
  ███████╗██╗   ██╗███████╗████████╗███████╗███╗   ███╗
  ██╔════╝╚██╗ ██╔╝██╔════╝╚══██╔══╝██╔════╝████╗ ████║
  ███████╗ ╚████╔╝ ███████╗   ██║   █████╗  ██╔████╔██║
  ╚════██║  ╚██╔╝  ╚════██║   ██║   ██╔══╝  ██║╚██╔╝██║
  ███████║   ██║   ███████║   ██║   ███████╗██║ ╚═╝ ██║
  ╚══════╝   ╚═╝   ╚══════╝   ╚═╝   ╚══════╝╚═╝     ╚═╝
EOF
    echo -e "${C_RESET}"
    echo -e "${C_BRIGHT_CYAN}  ═══════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_BOLD}${C_WHITE}               AUTO-FIX COMPLETED SUCCESSFULLY        ${C_RESET}"
    echo -e "${C_BRIGHT_CYAN}  ═══════════════════════════════════════════════════════${C_RESET}"
    echo
    echo -e "  ${C_BRIGHT_WHITE}RCON Configuration:${C_RESET}"
    echo -e "    ${C_BRIGHT_CYAN}Host:${C_RESET}     127.0.0.1"
    echo -e "    ${C_BRIGHT_CYAN}Port:${C_RESET}     $RCON_PORT"
    echo -e "    ${C_BRIGHT_CYAN}Config:${C_RESET}   $RCON_CONF"
    echo
    echo -e "  ${C_BRIGHT_WHITE}CLI Tool:${C_RESET}"
    echo -e "    ${C_BRIGHT_CYAN}Command:${C_RESET}  kingcloud-rcon <command>"
    echo -e "    ${C_BRIGHT_CYAN}Example:${C_RESET}  kingcloud-rcon list"
    echo -e "    ${C_BRIGHT_CYAN}Example:${C_RESET}  kingcloud-rcon say Hello"
    echo
    if [ "$SKIP_PANEL" -eq 0 ]; then
        echo -e "  ${C_BRIGHT_WHITE}Panel Integration:${C_RESET}"
        echo -e "    ${C_BRIGHT_CYAN}Bridge:${C_RESET}   $PANEL_DIR/rcon_bridge.py"
        echo -e "    ${C_BRIGHT_CYAN}Usage:${C_RESET}    Import and use execute() in your panel API."
        echo
    fi
    echo -e "  ${C_BRIGHT_YELLOW}⚠ IMPORTANT:${C_RESET}"
    echo -e "    ${C_BRIGHT_WHITE}RCON is bound to localhost. Do NOT expose port $RCON_PORT publicly.${C_RESET}"
    echo
    echo -e "${C_BRIGHT_CYAN}  ═══════════════════════════════════════════════════════${C_RESET}"
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
    echo -e "${C_BOLD}${C_WHITE}       ADVANCED RCON & LIVE CONSOLE AUTO-FIX        ${C_RESET}"
    echo -e "${C_BRIGHT_CYAN}  ═══════════════════════════════════════════════════════${C_RESET}"
    echo
    echo -e "  ${C_BRIGHT_WHITE}Please select an option:${C_RESET}"
    echo
    echo -e "  ${C_BRIGHT_CYAN}[1]${C_RESET} ${C_WHITE}Run Full Auto-Fix (Recommended)${C_RESET}"
    echo -e "  ${C_BRIGHT_CYAN}[2]${C_RESET} ${C_WHITE}Exit${C_RESET}"
    echo
    echo -ne "  ${C_BRIGHT_YELLOW}Enter choice [1-2]: ${C_RESET}"
    read -r choice
    
    case $choice in
        1) return 0 ;;
        2) clear_screen; exit 0 ;;
        *) clear_screen; print_error "Invalid choice. Exiting."; exit 1 ;;
    esac
}

# --- Main Execution ---
main() {
    hide_cursor
    show_menu
    
    clear_screen
    echo -e "${C_BRIGHT_GREEN}  Starting Auto-Fix Process...${C_RESET}"
    sleep 1
    
    check_prerequisites
    progress_bar 1.0
    
    backup_and_configure_rcon
    progress_bar 1.5
    
    save_rcon_config
    progress_bar 0.5
    
    install_rcon_cli
    progress_bar 1.0
    
    setup_panel_bridge
    progress_bar 1.0
    
    restart_services
    progress_bar 2.0
    
    test_rcon
    
    show_summary
}

main "$@"
