#!/usr/bin/env bash
# ==========================================================
#              KINGCLOUD WINDOWS CLOUD PC
#                     WIN10.SH
# ==========================================================

# Do not use set -e here.
# Some VPS/container environments do not have systemd.
set -u
set -o pipefail

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

APP="KINGCLOUD"
IMAGE="sankhlaking97/win10-ultra-lite"

BASE_DIR="/opt/kingcloud-cloudpc"
INFO_DIR="$BASE_DIR/info"
LOG_DIR="$BASE_DIR/logs"
LOCK_DIR="$BASE_DIR/locks"

# ==========================================================
# ROOT AUTO-FIX
# ==========================================================

if [ "$(id -u)" -ne 0 ]; then

    echo
    echo -e "${Y}KINGCLOUD needs administrator/root permission.${N}"
    echo

    if command -v sudo >/dev/null 2>&1; then
        echo -e "${C}Requesting sudo permission...${N}"
        exec sudo -E bash "$0" "$@"
    else
        echo -e "${R}sudo is not installed.${N}"
        echo
        echo "Run:"
        echo "  su -"
        echo "  bash $0"
        exit 1
    fi

fi

# ==========================================================
# DIRECTORIES
# ==========================================================

mkdir -p "$INFO_DIR" "$LOG_DIR" "$LOCK_DIR"

chmod 700 "$BASE_DIR" 2>/dev/null || true

# ==========================================================
# FUNCTIONS
# ==========================================================

clear_screen() {
    clear 2>/dev/null || true
}

line() {
    echo -e "${D}────────────────────────────────────────────────────────────${N}"
}

pause_short() {
    sleep 1
}

sanitize_name() {

    local name="$1"

    name=$(echo "$name" \
        | tr '[:upper:]' '[:lower:]' \
        | sed 's/[^a-z0-9_-]/-/g' \
        | sed 's/--*/-/g' \
        | sed 's/^-//;s/-$//')

    echo "$name"
}

# ==========================================================
# DOCKER INSTALL / CHECK
# ==========================================================

install_docker() {

    echo
    echo -e "${C}Installing Docker...${N}"
    echo

    if command -v apt-get >/dev/null 2>&1; then

        export DEBIAN_FRONTEND=noninteractive

        apt-get update -y || true

        apt-get install -y docker.io || {
            echo -e "${R}Docker installation failed.${N}"
            return 1
        }

    elif command -v dnf >/dev/null 2>&1; then

        dnf install -y docker || {
            echo -e "${R}Docker installation failed.${N}"
            return 1
        }

    elif command -v yum >/dev/null 2>&1; then

        yum install -y docker || {
            echo -e "${R}Docker installation failed.${N}"
            return 1
        }

    elif command -v apk >/dev/null 2>&1; then

        apk add docker || {
            echo -e "${R}Docker installation failed.${N}"
            return 1
        }

    else

        echo -e "${R}Could not detect supported package manager.${N}"
        return 1

    fi

    # systemd may not exist, so NEVER depend on it
    if command -v systemctl >/dev/null 2>&1; then
        systemctl enable docker >/dev/null 2>&1 || true
        systemctl start docker >/dev/null 2>&1 || true
    fi

    # Try service command if available
    if command -v service >/dev/null 2>&1; then
        service docker start >/dev/null 2>&1 || true
    fi

    return 0
}

check_docker() {

    # ------------------------------------------------------
    # Docker binary
    # ------------------------------------------------------

    if ! command -v docker >/dev/null 2>&1; then

        echo -e "${Y}Docker not found.${N}"

        install_docker || return 1

    fi

    # ------------------------------------------------------
    # Docker daemon
    # ------------------------------------------------------

    if docker info >/dev/null 2>&1; then
        return 0
    fi

    echo
    echo -e "${Y}Docker daemon is not responding.${N}"

    # Try systemd
    if command -v systemctl >/dev/null 2>&1; then
        systemctl start docker >/dev/null 2>&1 || true
    fi

    # Try service
    if command -v service >/dev/null 2>&1; then
        service docker start >/dev/null 2>&1 || true
    fi

    sleep 2

    if docker info >/dev/null 2>&1; then
        echo -e "${G}✓ Docker is ready.${N}"
        return 0
    fi

    echo
    echo -e "${R}✗ Docker daemon is not available.${N}"
    echo
    echo -e "${Y}Run this to check:${N}"
    echo "  docker info"
    echo

    return 1
}

# ==========================================================
# KVM CHECK
# ==========================================================

check_kvm() {

    if [ -e /dev/kvm ]; then
        return 0
    fi

    echo
    echo -e "${Y}⚠ /dev/kvm was not detected.${N}"
    echo
    echo -e "${D}The selected Windows Docker image requires KVM for"
    echo -e "hardware virtualization.${N}"
    echo

    read -rp "Continue anyway? [y/N]: " answer

    if [[ "$answer" =~ ^[Yy]$ ]]; then
        return 0
    fi

    return 1
}

# ==========================================================
# PORT FUNCTIONS
# ==========================================================

is_port_free() {

    local port="$1"

    # Host check
    if command -v ss >/dev/null 2>&1; then

        if ss -lnt 2>/dev/null |
            awk '{print $4}' |
            grep -qE "[:.]${port}$"; then

            return 1
        fi

    fi

    # Docker published port check
    if docker ps --format '{{.Ports}}' 2>/dev/null |
        grep -qE "[:.]${port}->"; then

        return 1
    fi

    return 0
}

find_free_port() {

    local port="$1"

    while [ "$port" -le 65500 ]; do

        if is_port_free "$port"; then
            echo "$port"
            return 0
        fi

        port=$((port + 1))

    done

    return 1
}

valid_port() {

    [[ "$1" =~ ^[0-9]+$ ]] &&
    [ "$1" -ge 1 ] &&
    [ "$1" -le 65535 ]
}

valid_number() {

    [[ "$1" =~ ^[0-9]+$ ]] &&
    [ "$1" -gt 0 ]
}

# ==========================================================
# SERVER STATUS
# ==========================================================

server_status() {

    local cname="$1"

    # Installation background process
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

    state=$(docker inspect \
        -f '{{.State.Status}}' \
        "$cname" 2>/dev/null || echo "unknown")

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
# SAVE INFO
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

        [ "$status" = "RUNNING" ] &&
            running=$((running + 1))

        [ "$status" = "SUSPENDED" ] &&
            suspended=$((suspended + 1))

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
# INSTALL CLOUD PC
# ==========================================================

install_cloud_pc() {

    if ! check_docker; then
        sleep 2
        return
    fi

    clear_screen

    echo -e "${P}╔══════════════════════════════════════════════════════════╗${N}"
    echo -e "${P}║              KINGCLOUD WINDOWS CLOUD PC                ║${N}"
    echo -e "${P}╚══════════════════════════════════════════════════════════╝${N}"
    echo

    # ------------------------------------------------------
    # PC NAME
    # ------------------------------------------------------

    read -rp "Windows PC Name [KingCloud-PC]: " display_name
    display_name="${display_name:-KingCloud-PC}"

    cname="$(sanitize_name "$display_name")"

    [ -z "$cname" ] && cname="cloud-pc"

    cname="kingcloud-$cname"

    # ------------------------------------------------------
    # DUPLICATE
    # ------------------------------------------------------

    if docker container inspect "$cname" >/dev/null 2>&1 ||
       [ -f "$LOCK_DIR/$cname.installing" ]; then

        echo
        echo -e "${R}✗ This Cloud PC already exists.${N}"
        sleep 2
        return
    fi

    # ------------------------------------------------------
    # USER
    # ------------------------------------------------------

    echo
    line
    echo -e "${C}Windows User Configuration${N}"
    line

    read -rp "Windows Username [king]: " win_user
    win_user="${win_user:-king}"
    win_user="${win_user// /}"

    if [ -z "$win_user" ]; then
        win_user="king"
    fi

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

    # ------------------------------------------------------
    # NETWORK
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

    # ------------------------------------------------------
    # WEB PORT BUSY
    # ------------------------------------------------------

    if ! is_port_free "$web_port"; then

        echo
        echo -e "${Y}⚠ Port $web_port is already in use.${N}"

        new_port="$(find_free_port "$web_port")"

        if [ -z "$new_port" ]; then
            echo -e "${R}✗ No free port found.${N}"
            sleep 2
            return
        fi

        web_port="$new_port"

        echo -e "${G}✓ Automatically selected: $web_port${N}"
    fi

    # ------------------------------------------------------
    # VNC
    # ------------------------------------------------------

    vnc_port="$(find_free_port 5900)" || {
        echo -e "${R}✗ VNC port unavailable.${N}"
        sleep 2
        return
    }

    # ------------------------------------------------------
    # RDP
    # ------------------------------------------------------

    rdp_port="$(find_free_port 3389)" || {
        echo -e "${R}✗ RDP port unavailable.${N}"
        sleep 2
        return
    }

    # ------------------------------------------------------
    # KVM
    # ------------------------------------------------------

    echo

    if [ -e /dev/kvm ]; then
        echo -e "${G}✓ KVM detected${N}"
    else
        echo -e "${Y}⚠ KVM not detected${N}"
    fi

    # ------------------------------------------------------
    # PREVIEW
    # ------------------------------------------------------

    echo
    line
    echo -e "${W}CLOUD PC CONFIGURATION${N}"
    line

    echo -e "PC Name    : ${C}$display_name${N}"
    echo -e "Container  : ${C}$cname${N}"
    echo -e "Username   : ${C}$win_user${N}"
    echo -e "RAM        : ${C}${ram}MB${N}"
    echo -e "CPU        : ${C}$cpu${N}"
    echo -e "Disk       : ${C}$disk${N}"
    echo -e "Web Port   : ${C}$web_port${N}"
    echo -e "VNC Port   : ${C}$vnc_port${N}"
    echo -e "RDP Port   : ${C}$rdp_port${N}"
    echo -e "Image      : ${C}$IMAGE${N}"

    echo
    line

    read -rp "Install Cloud PC? [Y/n]: " confirm
    confirm="${confirm:-Y}"

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${Y}Cancelled.${N}"
        sleep 1
        return
    fi

    # ------------------------------------------------------
    # SAVE CONFIG
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

    logfile="$LOG_DIR/$cname.log"

    # ------------------------------------------------------
    # BACKGROUND INSTALL
    # ------------------------------------------------------

    (
        echo "=========================================================="
        echo "KINGCLOUD WINDOWS CLOUD PC"
        echo "=========================================================="
        echo "SERVER: $display_name"
        echo "CONTAINER: $cname"
        echo "IMAGE: $IMAGE"
        echo "STARTED: $(date)"
        echo "=========================================================="
        echo

        echo "[1/3] Pulling Docker image..."

        if ! docker pull "$IMAGE"; then

            echo
            echo "ERROR: IMAGE PULL FAILED"
            echo "IMAGE: $IMAGE"
            echo "TIME: $(date)"

            rm -f "$LOCK_DIR/$cname.installing"

            exit 1
        fi

        echo
        echo "[2/3] Creating persistent volumes..."

        docker volume create "${cname}_data" >/dev/null 2>&1 || true
        docker volume create "${cname}_iso" >/dev/null 2>&1 || true

        echo
        echo "[3/3] Starting Cloud PC..."

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
            echo "✓ KINGCLOUD CLOUD PC STARTED"
            echo "=========================================================="
            echo "SERVER : $display_name"
            echo "WEB    : http://YOUR-VPS-IP:$web_port"
            echo "VNC    : $vnc_port"
            echo "RDP    : $rdp_port"
            echo "TIME   : $(date)"
            echo "=========================================================="

        else

            echo
            echo "=========================================================="
            echo "✗ CLOUD PC FAILED"
            echo "=========================================================="
            echo
            echo "Docker command failed."
            echo "Check the Docker log for details."

        fi

        rm -f "$LOCK_DIR/$cname.installing"

    ) > "$logfile" 2>&1 &

    pid=$!

    echo "$pid" > "$LOCK_DIR/$cname.installing"

    # ------------------------------------------------------
    # NO ENTER REQUIRED
    # ------------------------------------------------------

    echo
    echo -e "${G}✓ $display_name installation started in background.${N}"
    echo -e "${D}The main menu will return automatically.${N}"

    sleep 1
}

# ==========================================================
# LIST
# ==========================================================

list_servers() {

    clear_screen

    echo -e "${P}KINGCLOUD • CLOUD PC LIST${N}"
    line
    echo

    printf "%-22s %-14s %-8s %-6s %-8s %-8s\n" \
        "SERVER" "STATUS" "RAM" "CPU" "WEB" "RDP"

    line

    found=0

    for file in "$INFO_DIR"/*.conf; do

        [ -e "$file" ] || continue

        unset SERVER_NAME CONTAINER_NAME RAM CPU WEB_PORT RDP_PORT

        # shellcheck disable=SC1090
        source "$file"

        found=1

        status="$(server_status "$CONTAINER_NAME")"

        case "$status" in

            RUNNING)
                s="${G}RUNNING${N}"
                ;;

            INSTALLING)
                s="${C}INSTALLING${N}"
                ;;

            STOPPED)
                s="${R}STOPPED${N}"
                ;;

            SUSPENDED)
                s="${Y}SUSPENDED${N}"
                ;;

            *)
                s="${D}$status${N}"
                ;;

        esac

        printf "%-22s %-23b %-8s %-6s %-8s %-8s\n" \
            "$SERVER_NAME" \
            "$s" \
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

    if ! check_docker; then
        sleep 2
        return
    fi

    clear_screen

    echo -e "${G}KINGCLOUD • START ALL${N}"
    line
    echo

    found=0

    for file in "$INFO_DIR"/*.conf; do

        [ -e "$file" ] || continue

        unset SERVER_NAME CONTAINER_NAME

        # shellcheck disable=SC1090
        source "$file"

        found=1

        status="$(server_status "$CONTAINER_NAME")"

        echo -e "${W}$SERVER_NAME${N}"

        case "$status" in

            RUNNING)

                echo -e "  ${G}✓ Already running${N}"
                ;;

            INSTALLING)

                echo -e "  ${C}⏳ Installation is running${N}"
                ;;

            STOPPED|CREATED)

                echo -e "  ${C}▶ Starting...${N}"

                if docker start "$CONTAINER_NAME" >/dev/null 2>&1; then
                    echo -e "  ${G}✓ Started successfully${N}"
                else
                    echo -e "  ${R}✗ Failed to start${N}"
                fi
                ;;

            SUSPENDED)

                echo -e "  ${Y}⏸ Suspended${N}"
                ;;

            RESTARTING)

                echo -e "  ${Y}↻ Restarting${N}"
                ;;

            MISSING)

                echo -e "  ${R}✗ Container missing${N}"
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

    if ! check_docker; then
        sleep 2
        return
    fi

    clear_screen

    echo -e "${R}KINGCLOUD • STOP ALL${N}"
    line
    echo

    found=0

    for file in "$INFO_DIR"/*.conf; do

        [ -e "$file" ] || continue

        unset SERVER_NAME CONTAINER_NAME

        # shellcheck disable=SC1090
        source "$file"

        found=1

        status="$(server_status "$CONTAINER_NAME")"

        echo -e "${W}$SERVER_NAME${N}"

        if [ "$status" = "RUNNING" ]; then

            if docker stop "$CONTAINER_NAME" >/dev/null 2>&1; then
                echo -e "  ${G}✓ Stopped${N}"
            else
                echo -e "  ${R}✗ Stop failed${N}"
            fi

        elif [ "$status" = "INSTALLING" ]; then

            echo -e "  ${C}⏳ Installation running${N}"

        else

            echo -e "  ${D}Status: $status${N}"

        fi

        echo

    done

    [ "$found" -eq 0 ] &&
        echo -e "${D}No Cloud PCs found.${N}"

    echo -e "${G}✓ Stop operation completed.${N}"

    sleep 2
}

# ==========================================================
# RESTART ALL
# ==========================================================

restart_all() {

    if ! check_docker; then
        sleep 2
        return
    fi

    clear_screen

    echo -e "${C}KINGCLOUD • RESTART ALL${N}"
    line
    echo

    found=0

    for file in "$INFO_DIR"/*.conf; do

        [ -e "$file" ] || continue

        unset SERVER_NAME CONTAINER_NAME

        # shellcheck disable=SC1090
        source "$file"

        found=1

        status="$(server_status "$CONTAINER_NAME")"

        echo -e "${W}$SERVER_NAME${N}"

        case "$status" in

            RUNNING|STOPPED|CREATED)

                if docker restart "$CONTAINER_NAME" >/dev/null 2>&1; then
                    echo -e "  ${G}✓ Restarted${N}"
                else
                    echo -e "  ${R}✗ Restart failed${N}"
                fi
                ;;

            INSTALLING)

                echo -e "  ${C}⏳ Installation running${N}"
                ;;

            SUSPENDED)

                echo -e "  ${Y}⏸ Suspended${N}"
                ;;

            *)

                echo -e "  ${D}Status: $status${N}"
                ;;

        esac

        echo

    done

    [ "$found" -eq 0 ] &&
        echo -e "${D}No Cloud PCs found.${N}"

    echo -e "${G}✓ Restart operation completed.${N}"

    sleep 2
}

# ==========================================================
# SELECT SERVER
# ==========================================================

select_server() {

    local action="$1"

    clear_screen

    echo -e "${P}KINGCLOUD • SELECT SERVER${N}"
    line
    echo

    local servers=()
    local i=1

    for file in "$INFO_DIR"/*.conf; do

        [ -e "$file" ] || continue

        unset SERVER_NAME CONTAINER_NAME

        # shellcheck disable=SC1090
        source "$file"

        servers+=("$CONTAINER_NAME")

        status="$(server_status "$CONTAINER_NAME")"

        echo -e "${W}[$i]${N} $SERVER_NAME ${D}[$status]${N}"

        i=$((i + 1))

    done

    if [ "${#servers[@]}" -eq 0 ]; then

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
# DELETE
# ==========================================================

delete_server() {

    local cname="$1"

    unset SERVER_NAME

    if [ -f "$INFO_DIR/$cname.conf" ]; then
        # shellcheck disable=SC1090
        source "$INFO_DIR/$cname.conf"
    fi

    echo
    echo -e "${R}WARNING: This deletes the Cloud PC container and volumes.${N}"
    echo
    echo -e "Server: ${W}${SERVER_NAME:-$cname}${N}"
    echo

    read -rp "Type DELETE to continue: " confirm

    if [ "$confirm" != "DELETE" ]; then
        echo -e "${Y}Cancelled.${N}"
        sleep 1
        return
    fi

    # Stop/Remove container
    docker rm -f "$cname" >/dev/null 2>&1 || true

    # Remove volumes
    docker volume rm "${cname}_data" >/dev/null 2>&1 || true
    docker volume rm "${cname}_iso" >/dev/null 2>&1 || true

    # Remove config
    rm -f "$INFO_DIR/$cname.conf"

    # Remove lock
    rm -f "$LOCK_DIR/$cname.installing"

    echo
    echo -e "${G}✓ Server deleted.${N}"

    sleep 2
}

# ==========================================================
# SUSPEND
# ==========================================================

suspend_server() {

    local cname="$1"

    unset SERVER_NAME

    [ -f "$INFO_DIR/$cname.conf" ] &&
        source "$INFO_DIR/$cname.conf"

    if ! docker container inspect "$cname" >/dev/null 2>&1; then

        echo -e "${R}✗ Container not found.${N}"
        sleep 2
        return
    fi

    status="$(server_status "$cname")"

    if [ "$status" != "RUNNING" ]; then

        echo -e "${Y}Server is not running.${N}"
        sleep 2
        return
    fi

    if docker pause "$cname" >/dev/null 2>&1; then
        echo -e "${Y}⏸ $SERVER_NAME suspended.${N}"
    else
        echo -e "${R}✗ Suspend failed.${N}"
    fi

    sleep 2
}

# ==========================================================
# RESUME
# ==========================================================

resume_server() {

    local cname="$1"

    unset SERVER_NAME

    [ -f "$INFO_DIR/$cname.conf" ] &&
        source "$INFO_DIR/$cname.conf"

    if ! docker container inspect "$cname" >/dev/null 2>&1; then

        echo -e "${R}✗ Container not found.${N}"
        sleep 2
        return
    fi

    status="$(server_status "$cname")"

    case "$status" in

        SUSPENDED)

            if docker unpause "$cname" >/dev/null 2>&1; then
                echo -e "${G}✓ $SERVER_NAME resumed.${N}"
            else
                echo -e "${R}✗ Resume failed.${N}"
            fi
            ;;

        STOPPED)

            if docker start "$cname" >/dev/null 2>&1; then
                echo -e "${G}✓ $SERVER_NAME started.${N}"
            else
                echo -e "${R}✗ Start failed.${N}"
            fi
            ;;

        RUNNING)

            echo -e "${G}✓ Already running.${N}"
            ;;

        *)

            echo -e "${Y}Status: $status${N}"
            ;;

    esac

    sleep 2
}

# ==========================================================
# LOGS
# ==========================================================

show_logs() {

    local cname="$1"

    unset SERVER_NAME

    [ -f "$INFO_DIR/$cname.conf" ] &&
        source "$INFO_DIR/$cname.conf"

    clear_screen

    echo -e "${P}KINGCLOUD • LOGS${N}"
    line

    echo -e "${W}Server:${N} ${SERVER_NAME:-$cname}"

    echo
    echo -e "${C}Installation Log${N}"
    line

    logfile="$LOG_DIR/$cname.log"

    if [ -f "$logfile" ]; then
        tail -n 60 "$logfile"
    else
        echo "No installation log."
    fi

    echo
    echo -e "${C}Docker Log${N}"
    line

    if docker container inspect "$cname" >/dev/null 2>&1; then
        docker logs --tail 40 "$cname" 2>&1 || true
    else
        echo "Container not created yet."
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
║                 KINGCLOUD CLOUD PC                      ║
║                                                          ║
╠══════════════════════════════════════════════════════════╣
║                                                          ║
║  ✓ Windows Cloud PC                                     ║
║  ✓ Multi Server                                          ║
║  ✓ Background Installation                               ║
║  ✓ Custom PC Name                                        ║
║  ✓ Username / Password                                   ║
║  ✓ RAM / CPU / Disk                                      ║
║  ✓ Custom Web Port                                       ║
║  ✓ Auto Free Port                                        ║
║  ✓ VNC / RDP Ports                                       ║
║  ✓ Persistent Volumes                                    ║
║  ✓ Start All                                             ║
║  ✓ Stop All                                              ║
║  ✓ Restart All                                           ║
║  ✓ Suspend / Resume                                      ║
║  ✓ Delete Server                                         ║
║  ✓ Installation Logs                                     ║
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
# CLEAN LOCKS
# ==========================================================

cleanup_locks() {

    for lock in "$LOCK_DIR"/*.installing; do

        [ -e "$lock" ] || continue

        pid="$(cat "$lock" 2>/dev/null || true)"

        if [ -z "$pid" ] ||
           ! kill -0 "$pid" 2>/dev/null; then

            rm -f "$lock"

        fi

    done
}

# ==========================================================
# MAIN MENU
# ==========================================================

while true; do

    cleanup_locks

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
            clear_screen
            echo -e "${G}KINGCLOUD Cloud PC Manager stopped.${N}"
            exit 0
            ;;

        *)
            echo -e "${R}Invalid option.${N}"
            sleep 1
            ;;

    esac

done
