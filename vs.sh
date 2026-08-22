#!/usr/bin/env bash

# ============================================================
#              KINGCLOUD CODE-SERVER MANAGER
#                    VERSION 2.0
# ============================================================

set -o pipefail

IMAGE="ghcr.io/coder/code-server:latest"
VERSION="2.0.0"

# ============================================================
# COLORS
# ============================================================

RESET='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'

PURPLE='\033[38;5;141m'
CYAN='\033[38;5;51m'
BLUE='\033[38;5;39m'
GREEN='\033[38;5;82m'
YELLOW='\033[38;5;220m'
RED='\033[38;5;196m'
WHITE='\033[38;5;255m'
GRAY='\033[38;5;245m'

# ============================================================
# HELPERS
# ============================================================

pause() {
    echo
    read -rp "  Press ENTER to continue..." _
}

line() {
    echo -e "${GRAY}────────────────────────────────────────────────────────────${RESET}"
}

success() {
    echo -e "${GREEN}  ✔ $1${RESET}"
}

error() {
    echo -e "${RED}  ✖ $1${RESET}"
}

warning() {
    echo -e "${YELLOW}  ⚠ $1${RESET}"
}

info() {
    echo -e "${CYAN}  ➜ $1${RESET}"
}

loading() {
    local TEXT="$1"

    echo -ne "  ${CYAN}${TEXT}${RESET}"

    for i in {1..3}; do
        sleep 0.20
        echo -ne "."
    done

    echo
}

# ============================================================
# BANNER
# ============================================================

banner() {

    clear

    echo -e "${PURPLE}${BOLD}"

    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║                                                            ║"
    echo "║              ██╗  ██╗██╗███╗   ██╗ ██████╗               ║"
    echo "║              ██║ ██╔╝██║████╗  ██║██╔════╝               ║"
    echo "║              █████╔╝ ██║██╔██╗ ██║██║  ███╗              ║"
    echo "║              ██╔═██╗ ██║██║╚██╗██║██║   ██║              ║"
    echo "║              ██║  ██╗██║██║ ╚████║╚██████╔╝              ║"
    echo "║              ╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝ ╚═════╝               ║"
    echo "║                                                            ║"
    echo "║              CODE-SERVER CONTROL CENTER                    ║"
    echo "║                                                            ║"
    echo "║                   K I N G C L O U D                        ║"
    echo "║                                                            ║"
    echo "╚════════════════════════════════════════════════════════════╝"

    echo -e "${RESET}"

    echo -e "  ${DIM}${GRAY}Docker • Multi Server • Code-Server Management${RESET}"
    echo
}

# ============================================================
# DOCKER CHECK
# ============================================================

check_docker() {

    if ! command -v docker >/dev/null 2>&1; then

        error "Docker is not installed."
        echo
        echo "Install Docker first."

        exit 1
    fi

    if ! docker info >/dev/null 2>&1; then

        error "Docker is not running or permission was denied."
        echo
        echo "Try:"
        echo "  sudo systemctl start docker"

        exit 1
    fi
}

# ============================================================
# SERVER LIST
# ============================================================

get_servers() {

    docker ps -a \
        --filter "ancestor=$IMAGE" \
        --format '{{.Names}}'
}

# ============================================================
# SUSPENDED SERVERS
# ============================================================

get_suspended_servers() {

    while IFS= read -r NAME; do

        [[ -z "$NAME" ]] && continue

        SUSPENDED=$(docker inspect \
            -f '{{index .Config.Labels "kingcloud.suspended"}}' \
            "$NAME" 2>/dev/null)

        if [[ "$SUSPENDED" == "true" ]]; then
            echo "$NAME"
        fi

    done < <(get_servers)
}

# ============================================================
# PORT
# ============================================================

valid_port() {

    [[ "$1" =~ ^[0-9]+$ ]] &&
    (( "$1" >= 1 && "$1" <= 65535 ))
}

port_used() {

    local PORT="$1"

    if docker ps --format '{{.Ports}}' 2>/dev/null |
        grep -Eq "(^|[:, ])${PORT}->"; then

        return 0
    fi

    if command -v ss >/dev/null 2>&1; then

        if ss -lnt 2>/dev/null |
            awk '{print $4}' |
            grep -Eq "[:.]${PORT}$"; then

            return 0
        fi
    fi

    return 1
}

# ============================================================
# INSTALL
# ============================================================

install_server() {

    clear
    banner

    echo -e "${CYAN}${BOLD}  🚀 CREATE NEW CODE-SERVER${RESET}"
    line
    echo

    read -rp "  Enter server name: " NAME

    NAME="${NAME// /-}"

    if [[ -z "$NAME" ]]; then
        error "Server name cannot be empty."
        pause
        return
    fi

    if docker container inspect "$NAME" >/dev/null 2>&1; then
        error "Server '$NAME' already exists."
        pause
        return
    fi

    echo

    while true; do

        read -rp "  Enter public port: " PORT

        if ! valid_port "$PORT"; then
            error "Invalid port. Use 1-65535."
            continue
        fi

        if port_used "$PORT"; then
            error "Port $PORT is already in use."
            continue
        fi

        break

    done

    echo

    while true; do

        read -rsp "  Enter password: " PASSWORD
        echo

        if [[ -z "$PASSWORD" ]]; then
            error "Password cannot be empty."
            continue
        fi

        if (( ${#PASSWORD} < 4 )); then
            warning "Password should be at least 4 characters."
            continue
        fi

        break

    done

    echo
    line

    echo -e "  Name        : ${CYAN}$NAME${RESET}"
    echo -e "  Public Port : ${CYAN}$PORT${RESET}"
    echo -e "  Forward     : ${CYAN}$PORT → 8080${RESET}"
    echo -e "  Image       : ${CYAN}$IMAGE${RESET}"

    line
    echo

    read -rp "  Create server? [Y/n]: " CONFIRM

    CONFIRM="${CONFIRM:-Y}"

    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then

        warning "Installation cancelled."
        pause
        return

    fi

    echo

    loading "Pulling Code-Server image"

    if ! docker pull "$IMAGE"; then

        error "Failed to pull image."
        pause
        return

    fi

    echo

    loading "Creating Code-Server"

    if docker run -d \
        --name "$NAME" \
        -p "${PORT}:8080" \
        -e "PASSWORD=${PASSWORD}" \
        --label "kingcloud.type=code-server" \
        --label "kingcloud.suspended=false" \
        --restart unless-stopped \
        "$IMAGE" >/dev/null; then

        echo

        success "Server created successfully!"

        echo
        line

        echo -e "  Name    : ${CYAN}$NAME${RESET}"
        echo -e "  Port    : ${CYAN}$PORT${RESET}"
        echo -e "  Forward : ${CYAN}$PORT → 8080${RESET}"
        echo -e "  Status  : ${GREEN}RUNNING${RESET}"

        echo
        echo -e "  URL:"
        echo -e "  ${BOLD}${CYAN}http://YOUR-SERVER-IP:${PORT}${RESET}"

        line

    else

        error "Failed to create server."

    fi

    pause
}

# ============================================================
# LIST SERVERS
# ============================================================

list_servers() {

    clear
    banner

    echo -e "${CYAN}${BOLD}  📋 ALL CODE-SERVERS${RESET}"
    line
    echo

    mapfile -t SERVERS < <(get_servers)

    if (( ${#SERVERS[@]} == 0 )); then

        warning "No Code-Servers found."
        pause
        return

    fi

    printf "  ${BOLD}%-22s %-14s %-25s %-12s${RESET}\n" \
        "NAME" "STATUS" "PORT" "MODE"

    line

    for NAME in "${SERVERS[@]}"; do

        STATUS=$(docker inspect \
            -f '{{.State.Status}}' \
            "$NAME" 2>/dev/null)

        SUSPENDED=$(docker inspect \
            -f '{{index .Config.Labels "kingcloud.suspended"}}' \
            "$NAME" 2>/dev/null)

        PORT=$(docker port "$NAME" 8080/tcp 2>/dev/null | head -n1)

        [[ -z "$PORT" ]] && PORT="Not published"

        if [[ "$SUSPENDED" == "true" ]]; then

            STATUS_TEXT="${YELLOW}SUSPENDED${RESET}"
            MODE="${RED}LOCKED${RESET}"

        elif [[ "$STATUS" == "running" ]]; then

            STATUS_TEXT="${GREEN}RUNNING${RESET}"
            MODE="${GREEN}ACTIVE${RESET}"

        elif [[ "$STATUS" == "exited" ]]; then

            STATUS_TEXT="${RED}STOPPED${RESET}"
            MODE="${GRAY}NORMAL${RESET}"

        else

            STATUS_TEXT="${YELLOW}${STATUS^^}${RESET}"
            MODE="${GRAY}NORMAL${RESET}"

        fi

        printf "  %-22s %-22b %-25s %-12b\n" \
            "$NAME" \
            "$STATUS_TEXT" \
            "$PORT" \
            "$MODE"

    done

    echo
    line

    echo -e "  Total: ${WHITE}${#SERVERS[@]}${RESET}"

    pause
}

# ============================================================
# RESTART ALL
# ============================================================

restart_all() {

    clear
    banner

    echo -e "${YELLOW}${BOLD}  🔄 RESTART ALL${RESET}"
    line
    echo

    mapfile -t SERVERS < <(get_servers)

    if (( ${#SERVERS[@]} == 0 )); then

        warning "No servers found."
        pause
        return

    fi

    for NAME in "${SERVERS[@]}"; do

        SUSPENDED=$(docker inspect \
            -f '{{index .Config.Labels "kingcloud.suspended"}}' \
            "$NAME" 2>/dev/null)

        if [[ "$SUSPENDED" == "true" ]]; then

            echo -e "  ${YELLOW}$NAME${RESET} → ${GRAY}SKIPPED / SUSPENDED${RESET}"

            continue
        fi

        echo -ne "  Restarting ${CYAN}$NAME${RESET}..."

        if docker restart "$NAME" >/dev/null 2>&1; then
            echo -e " ${GREEN}OK${RESET}"
        else
            echo -e " ${RED}FAILED${RESET}"
        fi

    done

    echo

    success "Restart completed."

    pause
}

# ============================================================
# STOP ALL
# ============================================================

stop_all() {

    clear
    banner

    echo -e "${RED}${BOLD}  ⏹ STOP ALL${RESET}"
    line
    echo

    mapfile -t SERVERS < <(
        docker ps \
            --filter "ancestor=$IMAGE" \
            --format '{{.Names}}'
    )

    if (( ${#SERVERS[@]} == 0 )); then

        warning "No running servers."
        pause
        return

    fi

    echo -e "  Running: ${WHITE}${#SERVERS[@]}${RESET}"
    echo

    read -rp "  Stop ALL running servers? [y/N]: " CONFIRM

    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then

        warning "Cancelled."
        pause
        return

    fi

    echo

    for NAME in "${SERVERS[@]}"; do

        echo -ne "  Stopping ${CYAN}$NAME${RESET}..."

        if docker stop "$NAME" >/dev/null 2>&1; then
            echo -e " ${GREEN}OK${RESET}"
        else
            echo -e " ${RED}FAILED${RESET}"
        fi

    done

    echo

    success "All running servers stopped."

    pause
}

# ============================================================
# START ALL
# ============================================================

start_all() {

    clear
    banner

    echo -e "${GREEN}${BOLD}  ▶ START ALL${RESET}"
    line
    echo

    mapfile -t SERVERS < <(get_servers)

    if (( ${#SERVERS[@]} == 0 )); then

        warning "No servers found."
        pause
        return

    fi

    for NAME in "${SERVERS[@]}"; do

        SUSPENDED=$(docker inspect \
            -f '{{index .Config.Labels "kingcloud.suspended"}}' \
            "$NAME" 2>/dev/null)

        STATUS=$(docker inspect \
            -f '{{.State.Status}}' \
            "$NAME" 2>/dev/null)

        if [[ "$SUSPENDED" == "true" ]]; then

            echo -e "  ${YELLOW}$NAME${RESET} → ${RED}SUSPENDED / SKIPPED${RESET}"

            continue
        fi

        if [[ "$STATUS" == "running" ]]; then

            echo -e "  ${CYAN}$NAME${RESET} → ${GREEN}ALREADY RUNNING${RESET}"

            continue
        fi

        echo -ne "  Starting ${CYAN}$NAME${RESET}..."

        if docker start "$NAME" >/dev/null 2>&1; then
            echo -e " ${GREEN}OK${RESET}"
        else
            echo -e " ${RED}FAILED${RESET}"
        fi

    done

    echo

    success "Start completed."

    pause
}

# ============================================================
# DELETE SERVER
# ============================================================

delete_server() {

    clear
    banner

    echo -e "${RED}${BOLD}  🗑 DELETE SERVER${RESET}"
    line
    echo

    read -rp "  Enter server name: " NAME

    if [[ -z "$NAME" ]]; then

        error "Name cannot be empty."
        pause
        return

    fi

    if ! docker container inspect "$NAME" >/dev/null 2>&1; then

        error "Server '$NAME' not found."
        pause
        return

    fi

    echo

    warning "This permanently deletes the Docker container."

    echo

    read -rp "  Type '$NAME' to confirm: " CONFIRM

    if [[ "$CONFIRM" != "$NAME" ]]; then

        error "Confirmation failed."
        warning "Delete cancelled."

        pause
        return

    fi

    echo

    loading "Deleting $NAME"

    if docker rm -f "$NAME" >/dev/null 2>&1; then

        success "Server '$NAME' deleted successfully."

    else

        error "Failed to delete server."

    fi

    pause
}

# ============================================================
# SUSPEND SERVER
# ============================================================

suspend_server() {

    clear
    banner

    echo -e "${YELLOW}${BOLD}  🔒 SUSPEND SERVER${RESET}"
    line
    echo

    read -rp "  Enter server name: " NAME

    if [[ -z "$NAME" ]]; then

        error "Name cannot be empty."
        pause
        return

    fi

    if ! docker container inspect "$NAME" >/dev/null 2>&1; then

        error "Server '$NAME' not found."
        pause
        return

    fi

    SUSPENDED=$(docker inspect \
        -f '{{index .Config.Labels "kingcloud.suspended"}}' \
        "$NAME" 2>/dev/null)

    if [[ "$SUSPENDED" == "true" ]]; then

        warning "This server is already suspended."
        info "Use option 9 to unsuspend it."

        pause
        return

    fi

    echo

    echo -e "  Server: ${WHITE}$NAME${RESET}"

    echo

    read -rp "  Suspend this server? [y/N]: " CONFIRM

    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then

        warning "Suspend cancelled."
        pause
        return

    fi

    echo

    loading "Stopping server"

    docker stop "$NAME" >/dev/null 2>&1

    # Important:
    # Disable automatic restart while suspended.
    docker update \
        --restart=no \
        "$NAME" >/dev/null 2>&1

    docker container update \
        --label-add kingcloud.suspended=true \
        "$NAME" >/dev/null 2>&1

    echo

    success "Server '$NAME' is now SUSPENDED."

    info "It will NOT automatically start."

    info "Start All / Restart All will skip it."

    info "Use option 9 to manually unsuspend."

    pause
}

# ============================================================
# UNSUSPEND SERVER
# ============================================================

unsuspend_server() {

    clear
    banner

    echo -e "${GREEN}${BOLD}  🔓 UNSUSPEND SERVER${RESET}"
    line
    echo

    mapfile -t SUSPENDED_SERVERS < <(
        get_suspended_servers
    )

    if (( ${#SUSPENDED_SERVERS[@]} == 0 )); then

        warning "No suspended servers found."

        pause
        return

    fi

    echo -e "  ${YELLOW}${BOLD}SUSPENDED SERVERS${RESET}"
    echo

    for i in "${!SUSPENDED_SERVERS[@]}"; do

        NUMBER=$((i + 1))

        NAME="${SUSPENDED_SERVERS[$i]}"

        PORT=$(docker port "$NAME" 8080/tcp 2>/dev/null | head -n1)

        echo -e "  ${YELLOW}[$NUMBER]${RESET} ${WHITE}$NAME${RESET}  ${GRAY}$PORT${RESET}"

    done

    echo

    line

    echo

    read -rp "  Enter server name to unsuspend: " NAME

    if [[ -z "$NAME" ]]; then

        error "Name cannot be empty."
        pause
        return

    fi

    FOUND="false"

    for SERVER in "${SUSPENDED_SERVERS[@]}"; do

        if [[ "$SERVER" == "$NAME" ]]; then

            FOUND="true"
            break

        fi

    done

    if [[ "$FOUND" != "true" ]]; then

        error "Suspended server '$NAME' not found."

        info "Type the exact server name from the list."

        pause
        return

    fi

    echo

    loading "Removing suspension"

    # Restore normal Docker restart policy.
    docker update \
        --restart unless-stopped \
        "$NAME" >/dev/null 2>&1

    docker container update \
        --label-add kingcloud.suspended=false \
        "$NAME" >/dev/null 2>&1

    echo

    loading "Starting server"

    if docker start "$NAME" >/dev/null 2>&1; then

        echo

        success "Server '$NAME' UNSUSPENDED."

        success "Server started successfully."

        echo

        PORT=$(docker port "$NAME" 8080/tcp 2>/dev/null | head -n1)

        info "Port: ${PORT:-Not published}"

    else

        error "Server was unsuspended but failed to start."

        warning "Check Docker logs with: docker logs $NAME"

    fi

    pause
}

# ============================================================
# ABOUT / FEATURES
# ============================================================

about() {

    clear

    echo -e "${PURPLE}${BOLD}"

    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║                                                            ║"
    echo "║                    K I N G C L O U D                       ║"
    echo "║                                                            ║"
    echo "║               CODE-SERVER MANAGER                          ║"
    echo "║                                                            ║"
    echo "╚════════════════════════════════════════════════════════════╝"

    echo -e "${RESET}"

    echo

    echo -e "${CYAN}${BOLD}  ABOUT${RESET}"

    line

    echo

    echo -e "  Name       : ${WHITE}KingCloud Code-Server Manager${RESET}"
    echo -e "  Version    : ${WHITE}$VERSION${RESET}"
    echo -e "  Platform   : ${WHITE}Docker${RESET}"
    echo -e "  Image      : ${WHITE}$IMAGE${RESET}"

    echo

    echo -e "${CYAN}${BOLD}  FEATURES${RESET}"

    line

    echo

    echo -e "  ${GREEN}✔${RESET} Multiple Code-Servers"
    echo -e "  ${GREEN}✔${RESET} Custom Server Names"
    echo -e "  ${GREEN}✔${RESET} Custom Public Ports"
    echo -e "  ${GREEN}✔${RESET} Password Protection"
    echo -e "  ${GREEN}✔${RESET} Automatic Port Forwarding"
    echo -e "  ${GREEN}✔${RESET} Port Availability Check"
    echo -e "  ${GREEN}✔${RESET} Install Server"
    echo -e "  ${GREEN}✔${RESET} Server List"
    echo -e "  ${GREEN}✔${RESET} Start All"
    echo -e "  ${GREEN}✔${RESET} Stop All"
    echo -e "  ${GREEN}✔${RESET} Restart All"
    echo -e "  ${GREEN}✔${RESET} Delete Server"
    echo -e "  ${GREEN}✔${RESET} Suspend Server"
    echo -e "  ${GREEN}✔${RESET} Suspended Server List"
    echo -e "  ${GREEN}✔${RESET} Manual Unsuspend"
    echo -e "  ${GREEN}✔${RESET} Suspended Server Protection"
    echo -e "  ${GREEN}✔${RESET} Docker Auto-Restart"
    echo -e "  ${GREEN}✔${RESET} Status Monitoring"
    echo -e "  ${GREEN}✔${RESET} Premium Terminal UI"
    echo -e "  ${GREEN}✔${RESET} Loading Animations"

    echo

    echo -e "${CYAN}${BOLD}  SUSPEND SYSTEM${RESET}"

    line

    echo

    echo -e "  ${GREEN}NORMAL${RESET}"
    echo -e "     ↓"
    echo -e "  ${YELLOW}Suspend${RESET}"
    echo -e "     ↓"
    echo -e "  ${RED}SUSPENDED${RESET}"
    echo -e "     ↓"
    echo -e "  ${CYAN}Unsuspend by name${RESET}"
    echo -e "     ↓"
    echo -e "  ${GREEN}STARTED${RESET}"

    echo

    echo -e "  ${GRAY}Suspended servers never start through Start All or Restart All.${RESET}"

    echo

    line

    echo

    echo -e "  ${PURPLE}${BOLD}KINGCLOUD${RESET}"
    echo -e "  ${GRAY}Code-Server Control Center${RESET}"

    echo

    pause
}

# ============================================================
# COMING SOON
# ============================================================

coming_soon() {

    clear

    echo

    echo -e "${PURPLE}${BOLD}"

    echo "       ╔════════════════════════════════════════╗"
    echo "       ║                                        ║"
    echo "       ║            K I N G C L O U D           ║"
    echo "       ║                                        ║"
    echo "       ║              COMING SOON               ║"
    echo "       ║                                        ║"
    echo "       ╚════════════════════════════════════════╝"

    echo -e "${RESET}"

    echo

    for i in {1..30}; do

        echo -ne "${CYAN}  █${RESET}"
        sleep 0.04

    done

    echo
    echo

    echo -e "  ${PURPLE}${BOLD}✨ MORE FEATURES ARE COMING${RESET}"

    echo
    echo -e "  ${GRAY}KingCloud Control Center is under development.${RESET}"

    echo

    pause
}

# ============================================================
# MAIN MENU
# ============================================================

main_menu() {

    while true; do

        check_docker

        banner

        RUNNING=$(docker ps \
            --filter "ancestor=$IMAGE" \
            -q 2>/dev/null | wc -l)

        TOTAL=$(docker ps -a \
            --filter "ancestor=$IMAGE" \
            -q 2>/dev/null | wc -l)

        SUSPENDED=$(get_suspended_servers | wc -l)

        echo -e "  ${GREEN}●${RESET} Running  : ${WHITE}$RUNNING${RESET}"
        echo -e "  ${PURPLE}●${RESET} Total    : ${WHITE}$TOTAL${RESET}"
        echo -e "  ${YELLOW}●${RESET} Suspended: ${WHITE}$SUSPENDED${RESET}"

        echo

        line

        echo

        echo -e "  ${GREEN}${BOLD}[1]${RESET}  🚀 Install Code-Server"
        echo -e "  ${CYAN}${BOLD}[2]${RESET}  📋 List Code-Servers"
        echo -e "  ${YELLOW}${BOLD}[3]${RESET}  🔄 Restart All"
        echo -e "  ${RED}${BOLD}[4]${RESET}  ⏹  Stop All"
        echo -e "  ${GREEN}${BOLD}[5]${RESET}  ▶  Start All"
        echo -e "  ${PURPLE}${BOLD}[6]${RESET}  ✨ Coming Soon"
        echo -e "  ${RED}${BOLD}[7]${RESET}  🗑  Delete Server"
        echo -e "  ${YELLOW}${BOLD}[8]${RESET}  🔒 Suspend Server"
        echo -e "  ${GREEN}${BOLD}[9]${RESET}  🔓 Unsuspend Server"
        echo -e "  ${CYAN}${BOLD}[10]${RESET} ℹ  About & Features"

        echo

        line

        echo

        echo -e "  ${GRAY}[0]${RESET}  🚪 Exit"

        echo

        read -rp "  ${CYAN}Select option:${RESET} " OPTION

        case "$OPTION" in

            1)
                install_server
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
                coming_soon
                ;;

            7)
                delete_server
                ;;

            8)
                suspend_server
                ;;

            9)
                unsuspend_server
                ;;

            10)
                about
                ;;

            0)
                clear
                echo
                echo -e "  ${PURPLE}${BOLD}KINGCLOUD${RESET}"
                echo -e "  ${GRAY}Code-Server Manager closed.${RESET}"
                echo
                exit 0
                ;;

            *)
                error "Invalid option."
                sleep 1
                ;;

        esac

    done
}

# ============================================================
# START
# ============================================================

check_docker
main_menu
