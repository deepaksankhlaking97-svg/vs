#!/usr/bin/env bash

# ============================================================
#        KINGCLOUD CODE-SERVER MANAGER
#        Docker Code-Server Control Panel
# ============================================================

set -o pipefail

IMAGE="ghcr.io/coder/code-server:latest"
TITLE="KINGCLOUD CODE-SERVER MANAGER"

# ---------- Colors ----------
RESET='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'

CYAN='\033[38;5;51m'
BLUE='\033[38;5;39m'
PURPLE='\033[38;5;141m'
GREEN='\033[38;5;82m'
YELLOW='\033[38;5;220m'
RED='\033[38;5;196m'
WHITE='\033[38;5;255m'
GRAY='\033[38;5;245m'

# ---------- Helpers ----------

pause() {
    echo
    read -rp "  Press ENTER to continue..." _
}

line() {
    echo -e "${GRAY}────────────────────────────────────────────────────────────${RESET}"
}

loading() {
    local text="${1:-Loading}"
    local i

    echo -ne "${CYAN}  ${text}${RESET}"

    for i in {1..3}; do
        sleep 0.25
        echo -ne "."
    done

    echo
}

success() {
    echo -e "${GREEN}  ✔ $1${RESET}"
}

error() {
    echo -e "${RED}  ✖ $1${RESET}"
}

info() {
    echo -e "${CYAN}  ➜ $1${RESET}"
}

warning() {
    echo -e "${YELLOW}  ⚠ $1${RESET}"
}

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
        echo
        exit 1
    fi
}

valid_port() {
    [[ "$1" =~ ^[0-9]+$ ]] &&
    (( "$1" >= 1 && "$1" <= 65535 ))
}

port_used() {
    local port="$1"

    if docker ps --format '{{.Ports}}' 2>/dev/null |
        grep -Eq "(^|[:, ])${port}->|0\.0\.0\.0:${port}->|\[::\]:${port}->"; then
        return 0
    fi

    if command -v ss >/dev/null 2>&1 &&
       ss -lnt 2>/dev/null | awk '{print $4}' |
       grep -Eq "[:.]${port}$"; then
        return 0
    fi

    return 1
}

banner() {
    clear

    echo -e "${PURPLE}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║                                                            ║"
    echo "║              ██╗  ██╗██╗███╗   ██╗ ██████╗               ║"
    echo "║              ██║ ██╔╝██║████╗  ██║██╔════╝               ║"
    echo "║              █████╔╝ ██║██╔██╗ ██║██║  ███╗              ║"
    echo "║              ██╔═██╗ ██║██║╚██╗██║██║   ██║              ║"
    echo "║              ██║  ██╗██║██║ ╚████║╚██████╔╝              ║"
    echo "║              ╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝ ╚═════╝               ║"
    echo "║                                                            ║"
    echo "║             ${WHITE}CODE-SERVER CONTROL CENTER${PURPLE}               ║"
    echo "║                    ${CYAN}KINGCLOUD${PURPLE}                          ║"
    echo "║                                                            ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${RESET}"

    echo -e "  ${DIM}${GRAY}Docker • Code Server • Multi Container Manager${RESET}"
    echo
}

# ---------- Install ----------

install_server() {
    clear
    banner

    echo -e "${CYAN}${BOLD}  CREATE NEW CODE-SERVER${RESET}"
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
        error "A container named '$NAME' already exists."
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
    echo -e "  ${WHITE}Server Name :${RESET} ${CYAN}$NAME${RESET}"
    echo -e "  ${WHITE}Public Port :${RESET} ${CYAN}$PORT${RESET}"
    echo -e "  ${WHITE}Container   :${RESET} ${CYAN}$NAME${RESET}"
    echo -e "  ${WHITE}Image       :${RESET} ${CYAN}$IMAGE${RESET}"
    echo -e "  ${WHITE}Forwarding  :${RESET} ${CYAN}$PORT → 8080${RESET}"
    line
    echo

    read -rp "  Create this server? [Y/n]: " CONFIRM
    CONFIRM="${CONFIRM:-Y}"

    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        warning "Installation cancelled."
        pause
        return
    fi

    echo
    loading "Pulling Code-Server image"

    if ! docker pull "$IMAGE"; then
        error "Failed to pull Code-Server image."
        pause
        return
    fi

    echo
    loading "Creating Code-Server container"

    if docker run -d \
        --name "$NAME" \
        -p "${PORT}:8080" \
        -e "PASSWORD=${PASSWORD}" \
        --restart unless-stopped \
        "$IMAGE" >/dev/null; then

        echo
        success "Code-Server created successfully!"
        echo
        line
        echo -e "  ${GREEN}SERVER READY${RESET}"
        echo
        echo -e "  Name      : ${CYAN}$NAME${RESET}"
        echo -e "  Port      : ${CYAN}$PORT${RESET}"
        echo -e "  Forward   : ${CYAN}$PORT → 8080${RESET}"
        echo -e "  Status    : ${GREEN}Running${RESET}"
        echo
        echo -e "  Open in browser:"
        echo -e "  ${BOLD}${CYAN}http://YOUR-SERVER-IP:${PORT}${RESET}"
        line
    else
        error "Failed to create container."
    fi

    pause
}

# ---------- List ----------

list_servers() {
    clear
    banner

    echo -e "${CYAN}${BOLD}  CODE-SERVER LIST${RESET}"
    line
    echo

    mapfile -t CONTAINERS < <(
        docker ps -a \
        --filter "ancestor=$IMAGE" \
        --format '{{.Names}}' 2>/dev/null
    )

    if (( ${#CONTAINERS[@]} == 0 )); then
        warning "No Code-Server containers found."
        echo
        echo -e "  Use option ${GREEN}1${RESET} to create your first server."
        pause
        return
    fi

    printf "  ${BOLD}%-24s %-13s %-24s${RESET}\n" "NAME" "STATUS" "PORT"
    line

    for CONTAINER in "${CONTAINERS[@]}"; do
        STATUS="$(docker inspect -f '{{.State.Status}}' "$CONTAINER" 2>/dev/null)"
        PORTS="$(docker port "$CONTAINER" 8080/tcp 2>/dev/null | head -n1)"

        if [[ "$STATUS" == "running" ]]; then
            STATUS_TEXT="${GREEN}RUNNING${RESET}"
        elif [[ "$STATUS" == "exited" ]]; then
            STATUS_TEXT="${RED}STOPPED${RESET}"
        else
            STATUS_TEXT="${YELLOW}${STATUS^^}${RESET}"
        fi

        [[ -z "$PORTS" ]] && PORTS="Not published"

        printf "  %-24s %-22b %-24s\n" \
            "$CONTAINER" \
            "$STATUS_TEXT" \
            "$PORTS"
    done

    echo
    line
    echo -e "  ${GRAY}Total Code-Servers: ${WHITE}${#CONTAINERS[@]}${RESET}"
    pause
}

# ---------- Restart All ----------

restart_all() {
    clear
    banner

    echo -e "${CYAN}${BOLD}  RESTART ALL CODE-SERVERS${RESET}"
    line
    echo

    mapfile -t CONTAINERS < <(
        docker ps -a \
        --filter "ancestor=$IMAGE" \
        --format '{{.Names}}' 2>/dev/null
    )

    if (( ${#CONTAINERS[@]} == 0 )); then
        warning "No Code-Server containers found."
        pause
        return
    fi

    for CONTAINER in "${CONTAINERS[@]}"; do
        echo -ne "  Restarting ${CYAN}${CONTAINER}${RESET}..."
        if docker restart "$CONTAINER" >/dev/null 2>&1; then
            echo -e " ${GREEN}OK${RESET}"
        else
            echo -e " ${RED}FAILED${RESET}"
        fi
    done

    echo
    success "Restart operation completed."
    pause
}

# ---------- Stop All ----------

stop_all() {
    clear
    banner

    echo -e "${YELLOW}${BOLD}  STOP ALL CODE-SERVERS${RESET}"
    line
    echo

    mapfile -t CONTAINERS < <(
        docker ps \
        --filter "ancestor=$IMAGE" \
        --format '{{.Names}}' 2>/dev/null
    )

    if (( ${#CONTAINERS[@]} == 0 )); then
        warning "No running Code-Servers found."
        pause
        return
    fi

    read -rp "  Stop ALL running Code-Servers? [y/N]: " CONFIRM

    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        warning "Operation cancelled."
        pause
        return
    fi

    echo

    for CONTAINER in "${CONTAINERS[@]}"; do
        echo -ne "  Stopping ${CYAN}${CONTAINER}${RESET}..."
        if docker stop "$CONTAINER" >/dev/null 2>&1; then
            echo -e " ${GREEN}OK${RESET}"
        else
            echo -e " ${RED}FAILED${RESET}"
        fi
    done

    echo
    success "All Code-Servers stopped."
    pause
}

# ---------- Start All ----------

start_all() {
    clear
    banner

    echo -e "${GREEN}${BOLD}  START ALL CODE-SERVERS${RESET}"
    line
    echo

    mapfile -t CONTAINERS < <(
        docker ps -a \
        --filter "ancestor=$IMAGE" \
        --format '{{.Names}}' 2>/dev/null
    )

    if (( ${#CONTAINERS[@]} == 0 )); then
        warning "No Code-Server containers found."
        pause
        return
    fi

    for CONTAINER in "${CONTAINERS[@]}"; do
        STATUS="$(docker inspect -f '{{.State.Status}}' "$CONTAINER" 2>/dev/null)"

        if [[ "$STATUS" == "running" ]]; then
            echo -e "  ${CYAN}${CONTAINER}${RESET} ${GRAY}already running${RESET}"
            continue
        fi

        echo -ne "  Starting ${CYAN}${CONTAINER}${RESET}..."

        if docker start "$CONTAINER" >/dev/null 2>&1; then
            echo -e " ${GREEN}OK${RESET}"
        else
            echo -e " ${RED}FAILED${RESET}"
        fi
    done

    echo
    success "Start operation completed."
    pause
}

# ---------- Coming Soon ----------

coming_soon() {
    clear
    echo

    for i in {1..2}; do
        clear
        echo
        echo -e "${PURPLE}${BOLD}"
        echo "       ╔══════════════════════════════════════╗"
        echo "       ║                                      ║"
        echo "       ║          K I N G C L O U D           ║"
        echo "       ║                                      ║"
        echo "       ╚══════════════════════════════════════╝"
        echo -e "${RESET}"

        echo
        echo -e "             ${CYAN}${BOLD}COMING SOON${RESET}"
        echo

        for j in {1..24}; do
            echo -ne "${BLUE}  █${RESET}"
            sleep 0.035
        done

        echo
        echo
        echo -e "       ${GRAY}New features are being prepared...${RESET}"
        sleep 0.5

        clear
        echo
        echo -e "${PURPLE}${BOLD}"
        echo "       ╔══════════════════════════════════════╗"
        echo "       ║                                      ║"
        echo "       ║          K I N G C L O U D           ║"
        echo "       ║                                      ║"
        echo "       ╚══════════════════════════════════════╝"
        echo -e "${RESET}"

        echo
        echo -e "             ${CYAN}${BOLD}COMING SOON...${RESET}"
        echo
        sleep 0.4
    done

    echo
    success "Stay tuned for upcoming features!"
    echo
    pause
}

# ---------- Main Menu ----------

menu() {
    while true; do
        check_docker
        banner

        RUNNING="$(docker ps --filter "ancestor=$IMAGE" -q 2>/dev/null | wc -l)"
        TOTAL="$(docker ps -a --filter "ancestor=$IMAGE" -q 2>/dev/null | wc -l)"

        echo -e "  ${GREEN}●${RESET} Running: ${WHITE}${RUNNING}${RESET}    ${PURPLE}●${RESET} Total: ${WHITE}${TOTAL}${RESET}"
        echo
        line
        echo

        echo -e "  ${GREEN}[1]${RESET}  🚀  Install Code-Server"
        echo -e "  ${CYAN}[2]${RESET}  📋  List Code-Servers"
        echo -e "  ${YELLOW}[3]${RESET}  🔄  Restart All"
        echo -e "  ${RED}[4]${RESET}  ⏹   Stop All"
        echo -e "  ${GREEN}[5]${RESET}  ▶   Start All"
        echo -e "  ${PURPLE}[6]${RESET}  ✨  Coming Soon"
        echo -e "  ${GRAY}[0]${RESET}  🚪  Exit"

        echo
        line
        echo

        read -rp "  Select option: " OPTION

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
            0)
                clear
                echo
                echo -e "  ${PURPLE}${BOLD}KINGCLOUD${RESET} ${GRAY}Code-Server Manager closed.${RESET}"
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

# ---------- Start ----------
menu
