#!/usr/bin/env bash

# ==========================================================
#              KINGCLOUD CLOUD PC MANAGER
#       Windows Cloud PC / Docker Management Panel
# ==========================================================

set -u

# ---------------- COLORS ----------------
R='\033[1;31m'
G='\033[1;32m'
Y='\033[1;33m'
B='\033[1;34m'
C='\033[1;36m'
P='\033[1;35m'
W='\033[1;37m'
D='\033[0;90m'
N='\033[0m'

SCRIPT_NAME="KINGCLOUD CLOUD PC"
IMAGE="sankhlaking97/win10-ultra-lite"

BASE_DIR="/opt/kingcloud-cloudpc"
DATA_DIR="$BASE_DIR/data"
LOG_DIR="$BASE_DIR/logs"
INFO_DIR="$BASE_DIR/info"

mkdir -p "$DATA_DIR" "$LOG_DIR" "$INFO_DIR"

# ==========================================================
# BASIC FUNCTIONS
# ==========================================================

pause_screen() {
    echo
    read -rp "Press ENTER to continue..."
}

clear_screen() {
    clear
}

line() {
    printf "${D}────────────────────────────────────────────────────────────${N}\n"
}

spinner() {
    local pid=$1
    local msg="$2"
    local spin='|/-\'
    local i=0

    while kill -0 "$pid" 2>/dev/null; do
        printf "\r${C}${msg} ${spin:i++%4:1}${N}"
        sleep 0.15
    done

    printf "\r%-70s\r" ""
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# ==========================================================
# DOCKER CHECK
# ==========================================================

check_docker() {

    if ! command_exists docker; then

        echo
        echo -e "${Y}Docker is not installed.${N}"
        echo

        read -rp "Install Docker automatically? [Y/n]: " answer
        answer="${answer:-Y}"

        if [[ "$answer" =~ ^[Yy]$ ]]; then

            echo
            echo -e "${C}Installing Docker...${N}"

            (
                if command_exists apt-get; then
                    apt-get update -y >/dev/null 2>&1
                    apt-get install -y docker.io >/dev/null 2>&1
                    systemctl enable --now docker >/dev/null 2>&1 || true

                elif command_exists dnf; then
                    dnf install -y docker >/dev/null 2>&1
                    systemctl enable --now docker >/dev/null 2>&1 || true

                elif command_exists yum; then
                    yum install -y docker >/dev/null 2>&1
                    systemctl enable --now docker >/dev/null 2>&1 || true

                else
                    echo "Unsupported Linux distribution."
                    exit 1
                fi
            ) &

            pid=$!
            spinner "$pid" "Installing Docker"
            wait "$pid"

            if ! command_exists docker; then
                echo -e "${R}Docker installation failed.${N}"
                return 1
            fi

            echo -e "${G}Docker installed successfully.${N}"

        else
            echo -e "${R}Docker is required.${N}"
            return 1
        fi
    fi

    if ! docker info >/dev/null 2>&1; then

        echo -e "${Y}Docker daemon is not running.${N}"

        systemctl start docker >/dev/null 2>&1 || true

        if ! docker info >/dev/null 2>&1; then
            echo -e "${R}Cannot access Docker daemon.${N}"
            echo "Try:"
            echo "  systemctl start docker"
            return 1
        fi
    fi

    return 0
}

# ==========================================================
# FREE PORT
# ==========================================================

is_port_free() {

    local port="$1"

    if command_exists ss; then
        ! ss -lnt 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${port}$"
    else
        ! docker ps --format '{{.Ports}}' | grep -q ":${port}->"
    fi
}

find_free_port() {

    local start="$1"
    local port="$start"

    while true; do

        if is_port_free "$port"; then
            echo "$port"
            return
        fi

        port=$((port + 1))

        if [ "$port" -gt 65500 ]; then
            echo ""
            return 1
        fi
    done
}

# ==========================================================
# NAME VALIDATION
# ==========================================================

sanitize_name() {

    echo "$1" |
        tr '[:upper:]' '[:lower:]' |
        sed 's/[^a-z0-9_-]/-/g' |
        sed 's/--*/-/g' |
        sed 's/^-//;s/-$//'
}

# ==========================================================
# SAVE SERVER INFO
# ==========================================================

save_info() {

    local cname="$1"
    local display="$2"
    local username="$3"
    local ram="$4"
    local cpu="$5"
    local disk="$6"
    local web_port="$7"
    local vnc_port="$8"
    local rdp_port="$9"

    cat > "$INFO_DIR/$cname.conf" <<EOF
SERVER_NAME=$display
CONTAINER_NAME=$cname
USERNAME=$username
RAM=$ram
CPU=$cpu
DISK=$disk
WEB_PORT=$web_port
VNC_PORT=$vnc_port
RDP_PORT=$rdp_port
IMAGE=$IMAGE
CREATED=$(date '+%Y-%m-%d %H:%M:%S')
EOF
}

# ==========================================================
# SERVER STATUS
# ==========================================================

server_status() {

    local cname="$1"

    if ! docker ps -a --format '{{.Names}}' |
        grep -qx "$cname"; then
        echo "MISSING"
        return
    fi

    local status
    status=$(docker inspect -f '{{.State.Status}}' "$cname" 2>/dev/null || echo "unknown")

    case "$status" in
        running)
            echo "RUNNING"
            ;;
        exited)
            echo "STOPPED"
            ;;
        paused)
            echo "SUSPENDED"
            ;;
        created)
            echo "CREATED"
            ;;
        *)
            echo "$status"
            ;;
    esac
}

# ==========================================================
# COUNTERS
# ==========================================================

get_counts() {

    local total=0
    local running=0
    local suspended=0

    for file in "$INFO_DIR"/*.conf; do

        [ -e "$file" ] || continue

        total=$((total + 1))

        cname=$(basename "$file" .conf)

        status=$(server_status "$cname")

        [[ "$status" == "RUNNING" ]] && running=$((running + 1))
        [[ "$status" == "SUSPENDED" ]] && suspended=$((suspended + 1))

    done

    echo "$running $total $suspended"
}

# ==========================================================
# BANNER
# ==========================================================

show_banner() {

    clear_screen

    echo -e "${P}"
    cat <<'EOF'
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║             ██╗  ██╗ ██████╗                            ║
║             ██║ ██╔╝██╔════╝                            ║
║             █████╔╝ ██║  ███╗                           ║
║             ██╔═██╗ ██║   ██║                           ║
║             ██║  ██╗╚██████╔╝                           ║
║             ╚═╝  ╚═╝ ╚═════╝                            ║
║                                                          ║
║              CODE-SERVER CONTROL CENTER                 ║
║                                                          ║
║                    K I N G C L O U D                     ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
EOF
    echo -e "${N}"

    echo
    echo -e "${D}Docker • Multi Server • Windows Cloud PC Management${N}"
    echo

    read running total suspended <<< "$(get_counts)"

    echo -e "${G}● Running   : ${W}$running${N}"
    echo -e "${P}● Total     : ${W}$total${N}"
    echo -e "${Y}● Suspended : ${W}$suspended${N}"

    echo
    line
}

# ==========================================================
# PULL IMAGE
# ==========================================================

pull_image_background() {

    local cname="$1"

    local logfile="$LOG_DIR/$cname-install.log"

    (
        echo "==================================================" >> "$logfile"
        echo "KINGCLOUD INSTALLATION" >> "$logfile"
        echo "Server: $cname" >> "$logfile"
        echo "Started: $(date)" >> "$logfile"
        echo "==================================================" >> "$logfile"

        echo "[1/2] Pulling Docker image..." >> "$logfile"

        docker pull "$IMAGE" >> "$logfile" 2>&1

        echo "[2/2] Starting Windows Cloud PC..." >> "$logfile"

        docker start "$cname" >> "$logfile" 2>&1

        echo "Installation/Startup process finished." >> "$logfile"
        echo "Finished: $(date)" >> "$logfile"

    ) &

    echo $!
}

# ==========================================================
# INSTALL CLOUD PC
# ==========================================================

install_cloud_pc() {

    check_docker || {
        pause_screen
        return
    }

    clear_screen

    echo -e "${P}╔════════════════════════════════════════════════════╗${N}"
    echo -e "${P}║           KINGCLOUD WINDOWS CLOUD PC              ║${N}"
    echo -e "${P}╚════════════════════════════════════════════════════╝${N}"
    echo

    read -rp "Windows PC Name [KingCloud-PC]: " display_name
    display_name="${display_name:-KingCloud-PC}"

    cname=$(sanitize_name "$display_name")

    [ -z "$cname" ] && cname="kingcloud-pc"

    # Avoid duplicate names
    if docker ps -a --format '{{.Names}}' | grep -qx "$cname"; then
        echo
        echo -e "${R}A server named '$cname' already exists.${N}"
        pause_screen
        return
    fi

    echo
    echo -e "${C}Windows User Configuration${N}"
    line

    read -rp "Windows Username [king]: " win_user
    win_user="${win_user:-king}"

    read -rsp "Windows Password [admin123]: " win_pass
    echo
    win_pass="${win_pass:-admin123}"

    echo
    echo -e "${C}Resource Configuration${N}"
    line

    read -rp "RAM in MB [2048]: " ram
    ram="${ram:-2048}"

    read -rp "CPU cores [1]: " cpu
    cpu="${cpu:-1}"

    read -rp "Disk size [50G]: " disk
    disk="${disk:-50G}"

    echo
    echo -e "${C}Network Configuration${N}"
    line

    read -rp "Web/VNC Port [6080]: " web_port
    web_port="${web_port:-6080}"

    if ! [[ "$web_port" =~ ^[0-9]+$ ]] ||
       [ "$web_port" -lt 1 ] ||
       [ "$web_port" -gt 65535 ]; then

        echo -e "${R}Invalid port.${N}"
        pause_screen
        return
    fi

    if ! is_port_free "$web_port"; then

        echo -e "${Y}Port $web_port is already in use.${N}"

        read -rp "Find next free port automatically? [Y/n]: " fp
        fp="${fp:-Y}"

        if [[ "$fp" =~ ^[Yy]$ ]]; then
            web_port=$(find_free_port "$web_port")
        else
            pause_screen
            return
        fi
    fi

    # Automatically find free ports for VNC and RDP
    vnc_port=$(find_free_port 5900)

    # Make sure RDP doesn't accidentally use same port
    rdp_port=$(find_free_port 3389)

    echo
    echo -e "${G}Configuration:${N}"
    echo -e "  Name       : ${W}$display_name${N}"
    echo -e "  Container  : ${W}$cname${N}"
    echo -e "  User       : ${W}$win_user${N}"
    echo -e "  RAM        : ${W}${ram}MB${N}"
    echo -e "  CPU        : ${W}${cpu}${N}"
    echo -e "  Disk       : ${W}$disk${N}"
    echo -e "  Web Port   : ${W}$web_port${N}"
    echo -e "  VNC Port   : ${W}$vnc_port${N}"
    echo -e "  RDP Port   : ${W}$rdp_port${N}"
    echo

    read -rp "Create this Cloud PC? [Y/n]: " confirm
    confirm="${confirm:-Y}"

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${Y}Cancelled.${N}"
        pause_screen
        return
    fi

    echo
    echo -e "${C}[$display_name] Installation started in background...${N}"

    # Create persistent volumes
    docker volume create "${cname}_data" >/dev/null
    docker volume create "${cname}_iso" >/dev/null

    logfile="$LOG_DIR/$cname-install.log"

    echo "==================================================" > "$logfile"
    echo "KINGCLOUD CLOUD PC INSTALLATION" >> "$logfile"
    echo "SERVER: $display_name" >> "$logfile"
    echo "CONTAINER: $cname" >> "$logfile"
    echo "STARTED: $(date)" >> "$logfile"
    echo "==================================================" >> "$logfile"

    # ------------------------------------------------------
    # Pull image in background
    # ------------------------------------------------------

    (
        echo "[KINGCLOUD] Pulling image: $IMAGE"
        docker pull "$IMAGE"

        echo "[KINGCLOUD] Creating Cloud PC..."

        docker run -d \
            --name "$cname" \
            --restart unless-stopped \
            --device /dev/kvm:/dev/kvm \
            --cap-add NET_ADMIN \
            -p "${web_port}:6080" \
            -p "${vnc_port}:5900" \
            -p "${rdp_port}:3389" \
            -e VNC_PASSWORD="$win_pass" \
            -e WINDOWS_USERNAME="$win_user" \
            -e WINDOWS_PASSWORD="$win_pass" \
            -e RAM="$ram" \
            -e CPU="$cpu" \
            -e DISK="$disk" \
            -v "${cname}_data:/data" \
            -v "${cname}_iso:/iso" \
            "$IMAGE"

        echo
        echo "[KINGCLOUD] Cloud PC started."
        echo "Web/VNC : $web_port"
        echo "VNC     : $vnc_port"
        echo "RDP     : $rdp_port"

    ) > "$logfile" 2>&1 &

    pid=$!

    save_info \
        "$cname" \
        "$display_name" \
        "$win_user" \
        "$ram" \
        "$cpu" \
        "$disk" \
        "$web_port" \
        "$vnc_port" \
        "$rdp_port"

    echo
    echo -e "${G}✓ Installation running in background.${N}"
    echo -e "${D}Process PID : $pid${N}"
    echo -e "${D}Server Name : $display_name${N}"
    echo -e "${D}Log File    : $logfile${N}"
    echo
    echo -e "${Y}Use [2] List Servers or [7] View Logs.${N}"

    pause_screen
}

# ==========================================================
# LIST SERVERS
# ==========================================================

list_servers() {

    clear_screen

    echo -e "${P}KINGCLOUD • CLOUD PC LIST${N}"
    line

    printf "%-20s %-12s %-10s %-8s %-8s %-8s\n" \
        "SERVER" "STATUS" "RAM" "CPU" "WEB" "RDP"

    line

    found=0

    for file in "$INFO_DIR"/*.conf; do

        [ -e "$file" ] || continue

        unset SERVER_NAME CONTAINER_NAME RAM CPU WEB_PORT RDP_PORT

        source "$file"

        status=$(server_status "$CONTAINER_NAME")

        case "$status" in
            RUNNING)
                sc="${G}RUNNING${N}"
                ;;
            STOPPED)
                sc="${R}STOPPED${N}"
                ;;
            SUSPENDED)
                sc="${Y}SUSPEND${N}"
                ;;
            *)
                sc="${D}$status${N}"
                ;;
        esac

        printf "%-20s %-20b %-10s %-8s %-8s %-8s\n" \
            "$SERVER_NAME" \
            "$sc" \
            "${RAM}M" \
            "$CPU" \
            "$WEB_PORT" \
            "$RDP_PORT"

        found=1
    done

    if [ "$found" -eq 0 ]; then
        echo -e "${D}No Cloud PC servers found.${N}"
    fi

    echo
    line
    pause_screen
}

# ==========================================================
# START ALL
# ==========================================================

start_all() {

    check_docker || return

    echo
    echo -e "${G}Starting all Cloud PCs...${N}"

    for file in "$INFO_DIR"/*.conf; do

        [ -e "$file" ] || continue

        unset CONTAINER_NAME SERVER_NAME
        source "$file"

        if docker ps -a --format '{{.Names}}' |
            grep -qx "$CONTAINER_NAME"; then

            echo -e "${C}▶ $SERVER_NAME${N}"
            docker start "$CONTAINER_NAME" >/dev/null 2>&1 || true

        fi
    done

    echo -e "${G}✓ Done.${N}"
    pause_screen
}

# ==========================================================
# STOP ALL
# ==========================================================

stop_all() {

    check_docker || return

    echo
    echo -e "${R}Stopping all Cloud PCs...${N}"

    for file in "$INFO_DIR"/*.conf; do

        [ -e "$file" ] || continue

        unset CONTAINER_NAME SERVER_NAME
        source "$file"

        if docker ps --format '{{.Names}}' |
            grep -qx "$CONTAINER_NAME"; then

            echo -e "${Y}■ $SERVER_NAME${N}"
            docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true

        fi
    done

    echo -e "${G}✓ Done.${N}"
    pause_screen
}

# ==========================================================
# RESTART ALL
# ==========================================================

restart_all() {

    check_docker || return

    echo
    echo -e "${C}Restarting all Cloud PCs...${N}"

    for file in "$INFO_DIR"/*.conf; do

        [ -e "$file" ] || continue

        unset CONTAINER_NAME SERVER_NAME
        source "$file"

        if docker ps -a --format '{{.Names}}' |
            grep -qx "$CONTAINER_NAME"; then

            echo -e "${C}↻ $SERVER_NAME${N}"
            docker restart "$CONTAINER_NAME" >/dev/null 2>&1 || true

        fi
    done

    echo -e "${G}✓ Done.${N}"
    pause_screen
}

# ==========================================================
# SELECT SERVER
# ==========================================================

select_server() {

    local action="$1"

    echo
    echo -e "${C}Available Cloud PCs:${N}"
    echo

    local servers=()
    local i=1

    for file in "$INFO_DIR"/*.conf; do

        [ -e "$file" ] || continue

        unset SERVER_NAME CONTAINER_NAME
        source "$file"

        servers+=("$CONTAINER_NAME")

        echo -e "${W}[$i]${N} $SERVER_NAME ${D}($CONTAINER_NAME)${N}"

        i=$((i + 1))
    done

    if [ "${#servers[@]}" -eq 0 ]; then
        echo -e "${D}No servers available.${N}"
        pause_screen
        return
    fi

    echo
    read -rp "Select server: " choice

    if ! [[ "$choice" =~ ^[0-9]+$ ]] ||
       [ "$choice" -lt 1 ] ||
       [ "$choice" -gt "${#servers[@]}" ]; then

        echo -e "${R}Invalid selection.${N}"
        pause_screen
        return
    fi

    cname="${servers[$((choice - 1))]}"

    case "$action" in

        delete)
            delete_server "$cname"
            ;;

        suspend)
            suspend_server "$cname"
            ;;

        resume)
            resume_server "$cname"
            ;;

        logs)
            show_logs "$cname"
            ;;

    esac
}

# ==========================================================
# DELETE SERVER
# ==========================================================

delete_server() {

    local cname="$1"

    unset SERVER_NAME
    [ -f "$INFO_DIR/$cname.conf" ] && source "$INFO_DIR/$cname.conf"

    echo
    echo -e "${R}WARNING: This will delete the Docker container.${N}"
    echo -e "Server: ${W}${SERVER_NAME:-$cname}${N}"
    echo

    read -rp "Type DELETE to confirm: " confirm

    if [ "$confirm" != "DELETE" ]; then
        echo -e "${Y}Cancelled.${N}"
        pause_screen
        return
    fi

    docker rm -f "$cname" >/dev/null 2>&1 || true

    # Remove volumes
    docker volume rm "${cname}_data" >/dev/null 2>&1 || true
    docker volume rm "${cname}_iso" >/dev/null 2>&1 || true

    rm -f "$INFO_DIR/$cname.conf"

    echo -e "${G}✓ Server deleted.${N}"

    pause_screen
}

# ==========================================================
# SUSPEND
# ==========================================================

suspend_server() {

    local cname="$1"

    unset SERVER_NAME
    [ -f "$INFO_DIR/$cname.conf" ] && source "$INFO_DIR/$cname.conf"

    if docker inspect "$cname" >/dev/null 2>&1; then

        docker pause "$cname" >/dev/null 2>&1 || true

        echo -e "${Y}⏸ $SERVER_NAME suspended.${N}"

    else
        echo -e "${R}Server not found.${N}"
    fi

    pause_screen
}

# ==========================================================
# RESUME
# ==========================================================

resume_server() {

    local cname="$1"

    unset SERVER_NAME
    [ -f "$INFO_DIR/$cname.conf" ] && source "$INFO_DIR/$cname.conf"

    if docker inspect "$cname" >/dev/null 2>&1; then

        docker unpause "$cname" >/dev/null 2>&1 || true

        echo -e "${G}▶ $SERVER_NAME resumed.${N}"

    else
        echo -e "${R}Server not found.${N}"
    fi

    pause_screen
}

# ==========================================================
# LOGS
# ==========================================================

show_logs() {

    local cname="$1"

    unset SERVER_NAME
    [ -f "$INFO_DIR/$cname.conf" ] && source "$INFO_DIR/$cname.conf"

    clear

    echo -e "${P}KINGCLOUD • INSTALLATION LOG${N}"
    line

    echo -e "${C}SERVER: ${W}${SERVER_NAME:-$cname}${N}"
    echo -e "${D}CONTAINER: $cname${N}"
    echo

    logfile="$LOG_DIR/$cname-install.log"

    if [ -f "$logfile" ]; then
        tail -n 40 "$logfile"
    else
        echo "No installation log found."
    fi

    echo
    line

    echo
    echo -e "${C}Docker logs:${N}"
    docker logs --tail 30 "$cname" 2>&1 || true

    echo
    pause_screen
}

# ==========================================================
# ABOUT
# ==========================================================

about() {

    clear

    echo -e "${P}"
    cat <<'EOF'
╔══════════════════════════════════════════════════════════╗
║                   KINGCLOUD CLOUD PC                     ║
╠══════════════════════════════════════════════════════════╣
║                                                          ║
║  • Docker based Windows Cloud PC                         ║
║  • Multi Cloud PC support                                ║
║  • Background installation                               ║
║  • Persistent data volumes                               ║
║  • RAM / CPU / Disk configuration                         ║
║  • Custom Web/VNC/RDP ports                              ║
║  • Start / Stop / Restart                                ║
║  • Suspend / Resume                                      ║
║  • Live Docker logs                                      ║
║  • Automatic free-port detection                         ║
║                                                          ║
║                  K I N G C L O U D                       ║
╚══════════════════════════════════════════════════════════╝
EOF
    echo -e "${N}"

    pause_screen
}

# ==========================================================
# MAIN MENU
# ==========================================================

while true; do

    show_banner

    echo
    echo -e "${G}[1]${N} 🖥️  Install Windows Cloud PC"
    echo -e "${C}[2]${N} 📋 List Cloud PCs"
    echo -e "${B}[3]${N} 🔄 Restart All"
    echo -e "${R}[4]${N} ⏹️  Stop All"
    echo -e "${G}[5]${N} ▶️  Start All"
    echo -e "${Y}[6]${N} 🗑️  Delete Server"
    echo -e "${Y}[7]${N} 📜 View Installation / Docker Logs"
    echo -e "${Y}[8]${N} ⏸️  Suspend Server"
    echo -e "${G}[9]${N} ▶️  Resume Server"
    echo -e "${C}[10]${N} ℹ️  About & Features"

    echo
    line

    echo -e "${D}[0]${N} 🚪 Exit"
    echo

    read -rp $'\033[1;38;5;51mSelect option:\033[0m ' option

    case "$option" in

        1)
            install_cloud_pc
            ;;

        2)
            list_servers
            ;;

        3)
            restart_all
            ;;

        4)
            stop_all
            ;;

        5)
            start_all
            ;;

        6)
            select_server "delete"
            ;;

        7)
            select_server "logs"
            ;;

        8)
            select_server "suspend"
            ;;

        9)
            select_server "resume"
            ;;

        10)
            about
            ;;

        0)
            clear
            echo -e "${G}KINGCLOUD Cloud PC Manager stopped.${N}"
            exit 0
            ;;

        *)
            echo -e "${R}Invalid option.${N}"
            sleep 1
            ;;

    esac

done
