#!/usr/bin/env bash
# ==========================================================
#              KINGCLOUD WINDOWS CLOUD PC
#                  WIN10.SH MANAGER
# ==========================================================
#
# Docker Image:
# sankhlaking97/win10-ultra-lite
#
# Features:
#  • Multi Windows Cloud PCs
#  • Background installation
#  • Custom Windows PC name
#  • Username / Password
#  • RAM / CPU / Disk
#  • Custom Web/VNC/RDP ports
#  • Automatic free-port detection
#  • Start All / Stop All / Restart All
#  • Suspend / Resume
#  • Delete Server
#  • Installation Logs
#  • Docker Logs
#  • Persistent volumes
#  • KVM detection
# ==========================================================

set -u

# ==========================================================
# COLORS
# ==========================================================

R='\033[1;31m'
G='\033[1;32m'
Y='\033[1;33m'
B='\033[1;34m'
C='\033[1;36m'
P='\033[1;35m'
W='\033[1;37m'
D='\033[0;90m'
N='\033[0m'

# ==========================================================
# CONFIGURATION
# ==========================================================

APP_NAME="KINGCLOUD"
IMAGE="sankhlaking97/win10-ultra-lite"

BASE_DIR="/opt/kingcloud-cloudpc"
INFO_DIR="$BASE_DIR/info"
LOG_DIR="$BASE_DIR/logs"
LOCK_DIR="$BASE_DIR/locks"

mkdir -p "$INFO_DIR"
mkdir -p "$LOG_DIR"
mkdir -p "$LOCK_DIR"

# ==========================================================
# ROOT CHECK
# ==========================================================

if [ "$(id -u)" != "0" ]; then
    echo -e "${R}Please run this script as root.${N}"
    echo
    echo "Example:"
    echo "  sudo bash win10.sh"
    exit 1
fi

# ==========================================================
# BASIC FUNCTIONS
# ==========================================================

clear_screen() {
    clear
}

line() {
    echo -e "${D}────────────────────────────────────────────────────────────${N}"
}

sleep_short() {
    sleep 1
}

sanitize_name() {
    echo "$1" \
        | tr '[:upper:]' '[:lower:]' \
        | sed 's/[^a-z0-9_-]/-/g' \
        | sed 's/--*/-/g' \
        | sed 's/^-//;s/-$//'
}

# ==========================================================
# DOCKER CHECK
# ==========================================================

check_docker() {

    if ! command -v docker >/dev/null 2>&1; then

        echo
        echo -e "${Y}Docker is not installed.${N}"
        echo

        read -rp "Install Docker automatically? [Y/n]: " ans
        ans="${ans:-Y}"

        if [[ "$ans" =~ ^[Yy]$ ]]; then

            echo
            echo -e "${C}Installing Docker...${N}"

            if command -v apt-get >/dev/null 2>&1; then

                apt-get update -y
                apt-get install -y docker.io

            elif command -v dnf >/dev/null 2>&1; then

                dnf install -y docker

            elif command -v yum >/dev/null 2>&1; then

                yum install -y docker

            else

                echo -e "${R}Unsupported Linux distribution.${N}"
                return 1

            fi

            systemctl enable docker >/dev/null 2>&1 || true
            systemctl start docker >/dev/null 2>&1 || true

        else
            return 1
        fi
    fi

    if ! docker info >/dev/null 2>&1; then

        systemctl start docker >/dev/null 2>&1 || true

        sleep 2

        if ! docker info >/dev/null 2>&1; then
            echo
            echo -e "${R}Docker daemon is not available.${N}"
            echo
            return 1
        fi
    fi

    return 0
}

# ==========================================================
# KVM CHECK
# ==========================================================

check_kvm() {

    if [ -e /dev/kvm ]; then
        return 0
    fi

    echo
    echo -e "${R}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
    echo -e "${R}KVM NOT FOUND${N}"
    echo -e "${R}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
    echo
    echo -e "${Y}/dev/kvm is not available on this VPS.${N}"
    echo
    echo "This Windows Cloud PC command requires KVM:"
    echo
    echo "  /dev/kvm"
    echo
    echo -e "${D}If your VPS provider does not expose KVM,"
    echo -e "the Windows container may not start.${N}"
    echo

    read -rp "Continue anyway? [y/N]: " ans

    if [[ ! "$ans" =~ ^[Yy]$ ]]; then
        return 1
    fi

    return 0
}

# ==========================================================
# PORT CHECK
# ==========================================================

is_port_free() {

    local port="$1"

    # Check host sockets
    if command -v ss >/dev/null 2>&1; then

        if ss -lnt 2>/dev/null |
            awk '{print $4}' |
            grep -qE "[:.]${port}$"; then
            return 1
        fi
    fi

    # Check Docker published ports
    if docker ps --format '{{.Ports}}' 2>/dev/null |
        grep -qE "[:.]${port}->"; then
        return 1
    fi

    return 0
}

find_free_port() {

    local start="$1"
    local port="$start"

    while [ "$port" -le 65500 ]; do

        if is_port_free "$port"; then
            echo "$port"
            return 0
        fi

        port=$((port + 1))

    done

    return 1
}

# ==========================================================
# VALIDATE PORT
# ==========================================================

valid_port() {

    local port="$1"

    [[ "$port" =~ ^[0-9]+$ ]] &&
    [ "$port" -ge 1 ] &&
    [ "$port" -le 65535 ]
}

# ==========================================================
# VALIDATE NUMBER
# ==========================================================

valid_number() {

    [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -gt 0 ]
}

# ==========================================================
# SERVER STATUS
# ==========================================================

server_status() {

    local cname="$1"

    # Installation currently running
    if [ -f "$LOCK_DIR/$cname.installing" ]; then

        local pid
        pid=$(cat "$LOCK_DIR/$cname.installing" 2>/dev/null || true)

        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            echo "INSTALLING"
            return
        fi

        rm -f "$LOCK_DIR/$cname.installing"
    fi

    if ! docker container inspect "$cname" >/dev/null 2>&1; then
        echo "MISSING"
        return
    fi

    local state
    state=$(docker inspect -f '{{.State.Status}}' "$cname" 2>/dev/null || echo "unknown")

    case "$state" in

        running)
            echo "RUNNING"
            ;;

        exited)
            echo "STOPPED"
            ;;

        paused)
            echo "SUSPENDED"
            ;;

        restarting)
            echo "RESTARTING"
            ;;

        created)
            echo "CREATED"
            ;;

        dead)
            echo "DEAD"
            ;;

        *)
            echo "$state"
            ;;

    esac
}

# ==========================================================
# SAVE SERVER INFORMATION
# ==========================================================

save_info() {

    local cname="$1"
    local display="$2"
    local username="$3"
    local ram="$4"
    local cpu="$5"
    local disk="$6"
    local web="$7"
    local vnc="$8"
    local rdp="$9"

    cat > "$INFO_DIR/$cname.conf" <<EOF
SERVER_NAME=$(printf '%q' "$display")
CONTAINER_NAME=$(printf '%q' "$cname")
USERNAME=$(printf '%q' "$username")
RAM=$(printf '%q' "$ram")
CPU=$(printf '%q' "$cpu")
DISK=$(printf '%q' "$disk")
WEB_PORT=$(printf '%q' "$web")
VNC_PORT=$(printf '%q' "$vnc")
RDP_PORT=$(printf '%q' "$rdp")
IMAGE=$(printf '%q' "$IMAGE")
CREATED=$(printf '%q' "$(date '+%Y-%m-%d %H:%M:%S')")
EOF
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

        unset CONTAINER_NAME

        # shellcheck disable=SC1090
        source "$file"

        total=$((total + 1))

        status=$(server_status "$CONTAINER_NAME")

        case "$status" in
            RUNNING)
                running=$((running + 1))
                ;;
            SUSPENDED)
                suspended=$((suspended + 1))
                ;;
        esac

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
# INSTALL WINDOWS CLOUD PC
# ==========================================================

install_cloud_pc() {

    check_docker || {
        sleep 1
        return
    }

    clear_screen

    echo -e "${P}╔══════════════════════════════════════════════════════════╗${N}"
    echo -e "${P}║             KINGCLOUD WINDOWS CLOUD PC                  ║${N}"
    echo -e "${P}╚══════════════════════════════════════════════════════════╝${N}"

    echo

    # ------------------------------------------------------
    # SERVER NAME
    # ------------------------------------------------------

    read -rp "Windows PC Name [KingCloud-PC]: " display_name
    display_name="${display_name:-KingCloud-PC}"

    cname=$(sanitize_name "$display_name")

    if [ -z "$cname" ]; then
        cname="kingcloud-pc"
    fi

    # Prefix to keep containers organized
    cname="kingcloud-$cname"

    # ------------------------------------------------------
    # DUPLICATE CHECK
    # ------------------------------------------------------

    if docker container inspect "$cname" >/dev/null 2>&1 ||
       [ -f "$LOCK_DIR/$cname.installing" ]; then

        echo
        echo -e "${R}✗ Server '$display_name' already exists or is installing.${N}"
        sleep 2
        return
    fi

    echo
    line
    echo -e "${C}Windows User Configuration${N}"
    line

    # ------------------------------------------------------
    # USERNAME
    # ------------------------------------------------------

    read -rp "Windows Username [king]: " win_user
    win_user="${win_user:-king}"

    # Remove spaces
    win_user="${win_user// /}"

    if [ -z "$win_user" ]; then
        win_user="king"
    fi

    # ------------------------------------------------------
    # PASSWORD
    # ------------------------------------------------------

    read -rsp "Windows Password [admin123]: " win_pass
    echo

    win_pass="${win_pass:-admin123}"

    # ------------------------------------------------------
    # RESOURCES
    # ------------------------------------------------------

    echo
    line
    echo -e "${C}Resource Configuration${N}"
    line

    read -rp "RAM in MB [2048]: " ram
    ram="${ram:-2048}"

    if ! valid_number "$ram"; then
        echo -e "${R}✗ Invalid RAM.${N}"
        sleep 2
        return
    fi

    read -rp "CPU cores [1]: " cpu
    cpu="${cpu:-1}"

    if ! valid_number "$cpu"; then
        echo -e "${R}✗ Invalid CPU.${N}"
        sleep 2
        return
    fi

    read -rp "Disk size [50G]: " disk
    disk="${disk:-50G}"

    if [ -z "$disk" ]; then
        disk="50G"
    fi

    # ------------------------------------------------------
    # WEB PORT
    # ------------------------------------------------------

    echo
    line
    echo -e "${C}Network Configuration${N}"
    line

    read -rp "Web/VNC Port [6080]: " web_port
    web_port="${web_port:-6080}"

    if ! valid_port "$web_port"; then
        echo -e "${R}✗ Invalid port.${N}"
        sleep 2
        return
    fi

    if ! is_port_free "$web_port"; then

        echo
        echo -e "${Y}⚠ Port $web_port is already in use.${N}"
        echo -e "${C}Searching for next free port...${N}"

        new_port=$(find_free_port "$web_port")

        if [ -z "$new_port" ]; then
            echo -e "${R}✗ No free port found.${N}"
            sleep 2
            return
        fi

        web_port="$new_port"

        echo -e "${G}✓ Selected port: $web_port${N}"
    fi

    # ------------------------------------------------------
    # VNC PORT
    # ------------------------------------------------------

    vnc_port=$(find_free_port 5900)

    if [ -z "$vnc_port" ]; then
        echo -e "${R}✗ Could not find VNC port.${N}"
        sleep 2
        return
    fi

    # ------------------------------------------------------
    # RDP PORT
    # ------------------------------------------------------

    rdp_port=$(find_free_port 3389)

    if [ -z "$rdp_port" ]; then
        echo -e "${R}✗ Could not find RDP port.${N}"
        sleep 2
        return
    fi

    # ------------------------------------------------------
    # KVM
    # ------------------------------------------------------

    echo
    if [ -e /dev/kvm ]; then
        echo -e "${G}✓ KVM detected: /dev/kvm${N}"
    else
        echo -e "${Y}⚠ KVM not detected.${N}"
    fi

    # ------------------------------------------------------
    # CONFIG PREVIEW
    # ------------------------------------------------------

    echo
    line

    echo -e "${W}CLOUD PC CONFIGURATION${N}"
    echo

    echo -e "  PC Name    : ${C}$display_name${N}"
    echo -e "  Container  : ${C}$cname${N}"
    echo -e "  Username   : ${C}$win_user${N}"
    echo -e "  RAM        : ${C}${ram}MB${N}"
    echo -e "  CPU        : ${C}$cpu Core(s)${N}"
    echo -e "  Disk       : ${C}$disk${N}"
    echo -e "  Web Port   : ${C}$web_port${N}"
    echo -e "  VNC Port   : ${C}$vnc_port${N}"
    echo -e "  RDP Port   : ${C}$rdp_port${N}"
    echo -e "  Image      : ${C}$IMAGE${N}"

    echo
    line

    read -rp "Install this Cloud PC? [Y/n]: " confirm
    confirm="${confirm:-Y}"

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${Y}Cancelled.${N}"
        sleep 1
        return
    fi

    # ------------------------------------------------------
    # SAVE INFO
    # ------------------------------------------------------

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

    # ------------------------------------------------------
    # LOG
    # ------------------------------------------------------

    logfile="$LOG_DIR/$cname.log"

    # ------------------------------------------------------
    # INSTALLATION BACKGROUND
    # ------------------------------------------------------

    (
        echo "=========================================================="
        echo "KINGCLOUD WINDOWS CLOUD PC"
        echo "=========================================================="
        echo
        echo "Server       : $display_name"
        echo "Container    : $cname"
        echo "Username     : $win_user"
        echo "RAM          : ${ram}MB"
        echo "CPU          : $cpu"
        echo "Disk         : $disk"
        echo "Web Port     : $web_port"
        echo "VNC Port     : $vnc_port"
        echo "RDP Port     : $rdp_port"
        echo "Image        : $IMAGE"
        echo
        echo "Started      : $(date)"
        echo "=========================================================="
        echo

        echo "[1/3] Pulling Docker image..."
        if ! docker pull "$IMAGE"; then

            echo
            echo "ERROR: Docker image pull failed."
            echo "Time: $(date)"

            rm -f "$LOCK_DIR/$cname.installing"

            exit 1
        fi

        echo
        echo "[2/3] Creating persistent volumes..."

        docker volume create "${cname}_data" >/dev/null 2>&1 || true
        docker volume create "${cname}_iso" >/dev/null 2>&1 || true

        echo
        echo "[3/3] Starting Windows Cloud PC..."

        if docker run -d \
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
            "$IMAGE"; then

            echo
            echo "=========================================================="
            echo "KINGCLOUD CLOUD PC STARTED"
            echo "=========================================================="
            echo
            echo "Server : $display_name"
            echo "Web    : http://YOUR-VPS-IP:$web_port"
            echo "VNC    : $vnc_port"
            echo "RDP    : $rdp_port"
            echo
            echo "Started: $(date)"
            echo "=========================================================="

        else

            echo
            echo "=========================================================="
            echo "ERROR: CLOUD PC FAILED TO START"
            echo "=========================================================="
            echo
            echo "Check Docker logs."
            echo

        fi

        rm -f "$LOCK_DIR/$cname.installing"

    ) > "$logfile" 2>&1 &

    install_pid=$!

    # Save installation PID
    echo "$install_pid" > "$LOCK_DIR/$cname.installing"

    # ------------------------------------------------------
    # SHORT SUCCESS MESSAGE
    # ------------------------------------------------------

    echo
    echo -e "${G}✓ $display_name installation started in background.${N}"
    echo -e "${D}Installation PID: $install_pid${N}"
    echo

    sleep 1

    # NO PAUSE HERE
    # Automatically returns to main menu.
}

# ==========================================================
# LIST SERVERS
# ==========================================================

list_servers() {

    clear_screen

    echo -e "${P}╔══════════════════════════════════════════════════════════╗${N}"
    echo -e "${P}║                 KINGCLOUD CLOUD PCS                     ║${N}"
    echo -e "${P}╚══════════════════════════════════════════════════════════╝${N}"

    echo

    printf "%-22s %-13s %-8s %-6s %-8s %-8s\n" \
        "SERVER" "STATUS" "RAM" "CPU" "WEB" "RDP"

    line

    found=0

    for file in "$INFO_DIR"/*.conf; do

        [ -e "$file" ] || continue

        unset SERVER_NAME CONTAINER_NAME USERNAME RAM CPU DISK WEB_PORT VNC_PORT RDP_PORT

        # shellcheck disable=SC1090
        source "$file"

        found=1

        status=$(server_status "$CONTAINER_NAME")

        case "$status" in

            RUNNING)
                status_text="${G}RUNNING${N}"
                ;;

            INSTALLING)
                status_text="${C}INSTALLING${N}"
                ;;

            STOPPED)
                status_text="${R}STOPPED${N}"
                ;;

            SUSPENDED)
                status_text="${Y}SUSPENDED${N}"
                ;;

            RESTARTING)
                status_text="${Y}RESTARTING${N}"
                ;;

            *)
                status_text="${D}$status${N}"
                ;;

        esac

        printf "%-22s %-22b %-8s %-6s %-8s %-8s\n" \
            "$SERVER_NAME" \
            "$status_text" \
            "${RAM}M" \
            "$CPU" \
            "$WEB_PORT" \
            "$RDP_PORT"

    done

    if [ "$found" -eq 0 ]; then
        echo -e "${D}No Cloud PCs found.${N}"
    fi

    echo
    line

    sleep 3
}

# ==========================================================
# START ALL
# ==========================================================

start_all() {

    check_docker || {
        sleep 2
        return
    }

    clear_screen

    echo -e "${G}╔══════════════════════════════════════════════════════════╗${N}"
    echo -e "${G}║                   START ALL CLOUD PCS                  ║${N}"
    echo -e "${G}╚══════════════════════════════════════════════════════════╝${N}"

    echo

    found=0

    for file in "$INFO_DIR"/*.conf; do

        [ -e "$file" ] || continue

        unset SERVER_NAME CONTAINER_NAME

        # shellcheck disable=SC1090
        source "$file"

        found=1

        status=$(server_status "$CONTAINER_NAME")

        echo -e "${W}$SERVER_NAME${N}"

        case "$status" in

            RUNNING)

                echo -e "  ${G}✓ Already running${N}"
                ;;

            INSTALLING)

                echo -e "  ${C}⏳ Installation still running${N}"
                ;;

            STOPPED|CREATED)

                echo -e "  ${C}▶ Starting...${N}"

                if docker start "$CONTAINER_NAME" >/dev/null 2>&1; then
                    echo -e "  ${G}✓ Started successfully${N}"
                else
                    echo -e "  ${R}✗ Start failed${N}"
                fi
                ;;

            SUSPENDED)

                echo -e "  ${Y}⏸ Server is suspended${N}"
                ;;

            RESTARTING)

                echo -e "  ${Y}↻ Already restarting${N}"
                ;;

            MISSING)

                echo -e "  ${R}✗ Container not found${N}"
                ;;

            *)

                echo -e "  ${Y}Status: $status${N}"
                ;;

        esac

        echo

    done

    if [ "$found" -eq 0 ]; then
        echo -e "${D}No Cloud PCs found.${N}"
    fi

    echo -e "${G}✓ Start operation completed.${N}"

    sleep 2
}

# ==========================================================
# STOP ALL
# ==========================================================

stop_all() {

    check_docker || {
        sleep 2
        return
    }

    clear_screen

    echo -e "${R}╔══════════════════════════════════════════════════════════╗${N}"
    echo -e "${R}║                    STOP ALL CLOUD PCS                   ║${N}"
    echo -e "${R}╚══════════════════════════════════════════════════════════╝${N}"

    echo

    found=0

    for file in "$INFO_DIR"/*.conf; do

        [ -e "$file" ] || continue

        unset SERVER_NAME CONTAINER_NAME

        # shellcheck disable=SC1090
        source "$file"

        found=1

        status=$(server_status "$CONTAINER_NAME")

        echo -e "${W}$SERVER_NAME${N}"

        case "$status" in

            RUNNING)

                echo -e "  ${Y}■ Stopping...${N}"

                if docker stop "$CONTAINER_NAME" >/dev/null 2>&1; then
                    echo -e "  ${G}✓ Stopped${N}"
                else
                    echo -e "  ${R}✗ Stop failed${N}"
                fi
                ;;

            INSTALLING)

                echo -e "  ${C}⏳ Installation running${N}"
                ;;

            STOPPED)

                echo -e "  ${D}Already stopped${N}"
                ;;

            SUSPENDED)

                echo -e "  ${Y}Already suspended${N}"
                ;;

            *)

                echo -e "  ${D}Status: $status${N}"
                ;;

        esac

        echo

    done

    if [ "$found" -eq 0 ]; then
        echo -e "${D}No Cloud PCs found.${N}"
    fi

    echo -e "${G}✓ Stop operation completed.${N}"

    sleep 2
}

# ==========================================================
# RESTART ALL
# ==========================================================

restart_all() {

    check_docker || {
        sleep 2
        return
    }

    clear_screen

    echo -e "${C}╔══════════════════════════════════════════════════════════╗${N}"
    echo -e "${C}║                  RESTART ALL CLOUD PCS                  ║${N}"
    echo -e "${C}╚══════════════════════════════════════════════════════════╝${N}"

    echo

    found=0

    for file in "$INFO_DIR"/*.conf; do

        [ -e "$file" ] || continue

        unset SERVER_NAME CONTAINER_NAME

        # shellcheck disable=SC1090
        source "$file"

        found=1

        status=$(server_status "$CONTAINER_NAME")

        echo -e "${W}$SERVER_NAME${N}"

        case "$status" in

            RUNNING|STOPPED|CREATED)

                echo -e "  ${C}↻ Restarting...${N}"

                if docker restart "$CONTAINER_NAME" >/dev/null 2>&1; then
                    echo -e "  ${G}✓ Restarted${N}"
                else
                    echo -e "  ${R}✗ Restart failed${N}"
                fi
                ;;

            INSTALLING)

                echo -e "  ${Y}⏳ Installation still running${N}"
                ;;

            SUSPENDED)

                echo -e "  ${Y}⏸ Server is suspended${N}"
                ;;

            *)

                echo -e "  ${D}Status: $status${N}"
                ;;

        esac

        echo

    done

    if [ "$found" -eq 0 ]; then
        echo -e "${D}No Cloud PCs found.${N}"
    fi

    echo -e "${G}✓ Restart operation completed.${N}"

    sleep 2
}

# ==========================================================
# SERVER SELECTION
# ==========================================================

select_server() {

    local action="$1"

    clear_screen

    echo -e "${P}KINGCLOUD • SELECT CLOUD PC${N}"
    line

    local servers=()
    local names=()
    local i=1

    for file in "$INFO_DIR"/*.conf; do

        [ -e "$file" ] || continue

        unset SERVER_NAME CONTAINER_NAME

        # shellcheck disable=SC1090
        source "$file"

        servers+=("$CONTAINER_NAME")
        names+=("$SERVER_NAME")

        status=$(server_status "$CONTAINER_NAME")

        echo -e "${W}[$i]${N} $SERVER_NAME ${D}[$status]${N}"

        i=$((i + 1))

    done

    if [ "${#servers[@]}" -eq 0 ]; then
        echo
        echo -e "${D}No Cloud PCs found.${N}"
        sleep 2
        return
    fi

    echo

    read -rp "Select server: " choice

    if ! [[ "$choice" =~ ^[0-9]+$ ]] ||
       [ "$choice" -lt 1 ] ||
       [ "$choice" -gt "${#servers[@]}" ]; then

        echo -e "${R}Invalid selection.${N}"
        sleep 2
        return
    fi

    cname="${servers[$((choice - 1))]}"

    case "$action" in

        delete)
            delete_server "$cname"
            ;;

        logs)
            show_logs "$cname"
            ;;

        suspend)
            suspend_server "$cname"
            ;;

        resume)
            resume_server "$cname"
            ;;

    esac
}

# ==========================================================
# DELETE SERVER
# ==========================================================

delete_server() {

    local cname="$1"

    unset SERVER_NAME

    if [ -f "$INFO_DIR/$cname.conf" ]; then
        # shellcheck disable=SC1090
        source "$INFO_DIR/$cname.conf"
    fi

    echo
    echo -e "${R}WARNING${N}"
    echo
    echo -e "Server: ${W}${SERVER_NAME:-$cname}${N}"
    echo
    echo "This will remove:"
    echo "  • Docker container"
    echo "  • Persistent data volume"
    echo "  • ISO volume"
    echo
    echo -e "${R}Server data may be permanently deleted.${N}"
    echo

    read -rp "Type DELETE to confirm: " confirm

    if [ "$confirm" != "DELETE" ]; then
        echo -e "${Y}Cancelled.${N}"
        sleep 1
        return
    fi

    # Kill background installation if active
    if [ -f "$LOCK_DIR/$cname.installing" ]; then

        pid=$(cat "$LOCK_DIR/$cname.installing" 2>/dev/null || true)

        if [ -n "$pid" ]; then
            kill "$pid" 2>/dev/null || true
        fi

        rm -f "$LOCK_DIR/$cname.installing"
    fi

    # Remove container
    docker rm -f "$cname" >/dev/null 2>&1 || true

    # Remove volumes
    docker volume rm "${cname}_data" >/dev/null 2>&1 || true
    docker volume rm "${cname}_iso" >/dev/null 2>&1 || true

    # Remove config
    rm -f "$INFO_DIR/$cname.conf"

    # Keep log for safety
    echo
    echo -e "${G}✓ Server deleted.${N}"

    sleep 2
}

# ==========================================================
# SUSPEND SERVER
# ==========================================================

suspend_server() {

    local cname="$1"

    unset SERVER_NAME

    if [ -f "$INFO_DIR/$cname.conf" ]; then
        # shellcheck disable=SC1090
        source "$INFO_DIR/$cname.conf"
    fi

    echo

    if ! docker container inspect "$cname" >/dev/null 2>&1; then

        echo -e "${R}✗ Container not found.${N}"
        sleep 2
        return
    fi

    status=$(server_status "$cname")

    if [ "$status" != "RUNNING" ]; then

        echo -e "${Y}Server is not running.${N}"
        sleep 2
        return
    fi

    if docker pause "$cname" >/dev/null 2>&1; then
        echo -e "${Y}⏸ $SERVER_NAME suspended.${N}"
    else
        echo -e "${R}✗ Failed to suspend server.${N}"
    fi

    sleep 2
}

# ==========================================================
# RESUME SERVER
# ==========================================================

resume_server() {

    local cname="$1"

    unset SERVER_NAME

    if [ -f "$INFO_DIR/$cname.conf" ]; then
        # shellcheck disable=SC1090
        source "$INFO_DIR/$cname.conf"
    fi

    echo

    if ! docker container inspect "$cname" >/dev/null 2>&1; then

        echo -e "${R}✗ Container not found.${N}"
        sleep 2
        return
    fi

    status=$(server_status "$cname")

    if [ "$status" = "SUSPENDED" ]; then

        if docker unpause "$cname" >/dev/null 2>&1; then
            echo -e "${G}▶ $SERVER_NAME resumed.${N}"
        else
            echo -e "${R}✗ Failed to resume server.${N}"
        fi

    elif [ "$status" = "STOPPED" ]; then

        if docker start "$cname" >/dev/null 2>&1; then
            echo -e "${G}▶ $SERVER_NAME started.${N}"
        else
            echo -e "${R}✗ Failed to start server.${N}"
        fi

    elif [ "$status" = "RUNNING" ]; then

        echo -e "${G}✓ Server is already running.${N}"

    else

        echo -e "${Y}Server status: $status${N}"

    fi

    sleep 2
}

# ==========================================================
# SHOW LOGS
# ==========================================================

show_logs() {

    local cname="$1"

    unset SERVER_NAME

    if [ -f "$INFO_DIR/$cname.conf" ]; then
        # shellcheck disable=SC1090
        source "$INFO_DIR/$cname.conf"
    fi

    clear_screen

    echo -e "${P}KINGCLOUD • SERVER LOGS${N}"
    line

    echo -e "${W}Server:${N} ${SERVER_NAME:-$cname}"
    echo -e "${D}Container: $cname${N}"

    echo
    echo -e "${C}Installation Log${N}"
    line

    logfile="$LOG_DIR/$cname.log"

    if [ -f "$logfile" ]; then
        tail -n 50 "$logfile"
    else
        echo -e "${D}No installation log available.${N}"
    fi

    echo
    echo -e "${C}Docker Log${N}"
    line

    if docker container inspect "$cname" >/dev/null 2>&1; then
        docker logs --tail 40 "$cname" 2>&1 || true
    else
        echo -e "${D}Container not created yet.${N}"
    fi

    echo
    line

    sleep 4
}

# ==========================================================
# ABOUT
# ==========================================================

about() {

    clear_screen

    echo -e "${P}"
    cat <<'EOF'
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║                KINGCLOUD CLOUD PC                       ║
║                                                          ║
╠══════════════════════════════════════════════════════════╣
║                                                          ║
║  Windows Cloud PC Docker Manager                        ║
║                                                          ║
║  ✓ Multi Cloud PC                                       ║
║  ✓ Background Installation                              ║
║  ✓ Custom PC Name                                       ║
║  ✓ Windows Username / Password                           ║
║  ✓ RAM Configuration                                     ║
║  ✓ CPU Configuration                                     ║
║  ✓ Disk Configuration                                    ║
║  ✓ Custom Web Port                                       ║
║  ✓ Automatic Port Detection                              ║
║  ✓ VNC Port                                              ║
║  ✓ RDP Port                                              ║
║  ✓ Persistent Docker Volumes                             ║
║  ✓ Start All                                             ║
║  ✓ Stop All                                              ║
║  ✓ Restart All                                           ║
║  ✓ Suspend / Resume                                      ║
║  ✓ Delete Server                                         ║
║  ✓ Installation Logs                                    ║
║  ✓ Docker Logs                                           ║
║  ✓ KVM Detection                                         ║
║                                                          ║
║                  K I N G C L O U D                       ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
EOF
    echo -e "${N}"

    echo
    echo -e "${D}Docker Image:${N}"
    echo -e "${C}$IMAGE${N}"

    echo
    line

    sleep 4
}

# ==========================================================
# SYSTEM CLEANUP
# ==========================================================

cleanup_old_locks() {

    for lock in "$LOCK_DIR"/*.installing; do

        [ -e "$lock" ] || continue

        pid=$(cat "$lock" 2>/dev/null || true)

        if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
            rm -f "$lock"
        fi

    done
}

# ==========================================================
# MAIN MENU
# ==========================================================

while true; do

    cleanup_old_locks

    show_banner

    echo
    echo -e "${G}[1]${N} 🚀 Install Windows Cloud PC"
    echo -e "${C}[2]${N} 📋 List Cloud PCs"
    echo -e "${B}[3]${N} 🔄 Restart All"
    echo -e "${R}[4]${N} ⏹  Stop All"
    echo -e "${G}[5]${N} ▶  Start All"
    echo -e "${R}[6]${N} 🗑  Delete Server"
    echo -e "${C}[7]${N} 📜 Server Logs"
    echo -e "${Y}[8]${N} ⏸  Suspend Server"
    echo -e "${G}[9]${N} ▶  Resume Server"
    echo -e "${P}[10]${N} ℹ  About & Features"

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
