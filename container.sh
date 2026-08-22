#!/usr/bin/env bash
# ==============================================================
# 👑 KINGCLOUD CODE-SERVER CONTROL CENTER
# Premium Docker / Code-Server Manager
# ==============================================================
set -u

APP_NAME="KINGCLOUD CODE-SERVER CONTROL CENTER"
LABEL="kingcloud.container=true"
IMAGE="ubuntu:24.04"
SUSPEND_LABEL="kingcloud.suspended=true"
VERSION="2.0.0"

# -------------------- Colors --------------------
RESET='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
PURPLE='\033[38;5;141m'
LIGHT_PURPLE='\033[38;5;147m'
CYAN='\033[38;5;51m'
GREEN='\033[38;5;46m'
YELLOW='\033[38;5;226m'
RED='\033[38;5;196m'
BLUE='\033[38;5;39m'
WHITE='\033[97m'
GRAY='\033[38;5;245m'

hide_cursor(){ printf '\033[?25l'; }
show_cursor(){ printf '\033[?25h'; }
cleanup(){ show_cursor; printf "${RESET}"; }
trap cleanup EXIT INT TERM

# -------------------- Helpers --------------------
pause(){
    echo
    read -rp "$(printf "${GRAY}Press Enter to continue...${RESET}")" _
}

hr(){
    printf "${GRAY}%*s${RESET}\n" "$(terminal_width)" "" | tr ' ' '─'
}

terminal_width(){
    local w
    w=$(tput cols 2>/dev/null || echo 80)
    (( w < 60 )) && w=60
    echo "$w"
}

center(){
    local text="$1"
    local width
    width=$(terminal_width)
    local len=${#text}
    local pad=$(( (width - len) / 2 ))
    (( pad < 0 )) && pad=0
    printf "%*s%s\n" "$pad" "" "$text"
}

spinner(){
    local pid="$1"
    local msg="$2"
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r${PURPLE}${frames[$i]}${RESET} ${msg}"
        i=$(( (i + 1) % ${#frames[@]} ))
        sleep 0.08
    done
    printf "\r\033[K"
}

run_anim(){
    local msg="$1"
    shift
    "$@" >/tmp/kc_cmd.out 2>/tmp/kc_cmd.err &
    local pid=$!
    spinner "$pid" "$msg"
    wait "$pid"
    local rc=$?
    if (( rc == 0 )); then
        printf "${GREEN}✔${RESET} %s\n" "$msg"
    else
        printf "${RED}✖${RESET} %s\n" "$msg"
        [[ -s /tmp/kc_cmd.err ]] && sed 's/^/  /' /tmp/kc_cmd.err | tail -8
    fi
    return "$rc"
}

success(){ printf "${GREEN}✔${RESET} %s\n" "$1"; }
error(){ printf "${RED}✖${RESET} %s\n" "$1"; }
info(){ printf "${CYAN}ℹ${RESET} %s\n" "$1"; }
warn(){ printf "${YELLOW}⚠${RESET} %s\n" "$1"; }

valid_name(){
    [[ "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,62}$ ]]
}

docker_ready(){
    command -v docker >/dev/null 2>&1 || return 1
    docker info >/dev/null 2>&1 || return 1
    return 0
}

require_docker(){
    if docker_ready; then return 0; fi
    error "Docker is not installed or the Docker daemon is unavailable."
    echo
    echo "Use [1] Install / Repair Docker first."
    return 1
}

is_kingcloud(){
    docker inspect -f '{{ index .Config.Labels "kingcloud.container" }}' "$1" 2>/dev/null | grep -qx 'true'
}

is_suspended(){
    docker inspect -f '{{ index .Config.Labels "kingcloud.suspended" }}' "$1" 2>/dev/null | grep -qx 'true'
}

all_containers(){
    docker ps -a --filter "label=$LABEL" --format '{{.Names}}' 2>/dev/null
}

mapfile_containers(){
    CONTAINERS=()
    mapfile -t CONTAINERS < <(all_containers)
}

count_running(){
    docker ps --filter "label=$LABEL" -q 2>/dev/null | wc -l
}

count_total(){
    docker ps -a --filter "label=$LABEL" -q 2>/dev/null | wc -l
}

count_suspended(){
    local n=0 name
    while read -r name; do
        [[ -n "$name" ]] && is_suspended "$name" && n=$((n+1))
    done < <(all_containers)
    echo "$n"
}

status_text(){
    local name="$1"
    local status
    status=$(docker inspect -f '{{.State.Status}}' "$name" 2>/dev/null || echo "unknown")
    if is_suspended "$name"; then
        printf "${YELLOW}SUSPENDED${RESET}"
    elif [[ "$status" == "running" ]]; then
        printf "${GREEN}RUNNING${RESET}"
    elif [[ "$status" == "exited" || "$status" == "created" ]]; then
        printf "${RED}STOPPED${RESET}"
    else
        printf "${GRAY}%s${RESET}" "${status^^}"
    fi
}

# -------------------- Logo / Animation --------------------
logo(){
    clear
    hide_cursor
    printf "\n"
    center "${PURPLE}╔══════════════════════════════════════════════════════════╗${RESET}"
    center "${PURPLE}║${RESET}        ${LIGHT_PURPLE}${BOLD}██╗  ██╗ ██████${RESET}${PURPLE}╗${RESET}  ${PURPLE}██╗${RESET}  ${PURPLE}██╗${RESET}       ${PURPLE}║${RESET}"
    center "${PURPLE}║${RESET}        ${LIGHT_PURPLE}${BOLD}██║ ██╔╝██╔════╝${RESET}  ${PURPLE}██║${RESET}  ${PURPLE}██║${RESET}       ${PURPLE}║${RESET}"
    center "${PURPLE}║${RESET}        ${LIGHT_PURPLE}${BOLD}█████╔╝ ██║  ███╗${RESET} ${PURPLE}███████║${RESET}       ${PURPLE}║${RESET}"
    center "${PURPLE}║${RESET}        ${LIGHT_PURPLE}${BOLD}██╔═██╗ ██║   ██║${RESET} ${PURPLE}██╔══██║${RESET}       ${PURPLE}║${RESET}"
    center "${PURPLE}║${RESET}        ${LIGHT_PURPLE}${BOLD}██║  ██╗╚██████╔╝${RESET} ${PURPLE}██║  ██║${RESET}       ${PURPLE}║${RESET}"
    center "${PURPLE}║${RESET}        ${LIGHT_PURPLE}${BOLD}╚═╝  ╚═╝ ╚═════╝${RESET}  ${PURPLE}╚═╝  ╚═╝${RESET}       ${PURPLE}║${RESET}"
    center "${PURPLE}║${RESET}                                                  ${PURPLE}║${RESET}"
    center "${PURPLE}║${RESET}       ${CYAN}CODE-SERVER CONTROL CENTER${RESET}              ${PURPLE}║${RESET}"
    center "${PURPLE}║${RESET}                                                  ${PURPLE}║${RESET}"
    center "${PURPLE}║${RESET}              ${LIGHT_PURPLE}K I N G C L O U D${RESET}             ${PURPLE}║${RESET}"
    center "${PURPLE}╚══════════════════════════════════════════════════════════╝${RESET}"
    printf "\n"
}

boot_animation(){
    local i
    printf "\n"
    for i in 1 2 3; do
        printf "\r${PURPLE}◆${RESET} ${GRAY}Initializing KingCloud Control Center"
        printf "%*s" "$i" "" | tr ' ' '.'
        sleep 0.08
    done
    printf "\r\033[K"
}

# -------------------- Docker Install --------------------
install_docker(){
    logo
    echo
    center "${BOLD}${LIGHT_PURPLE}DOCKER INSTALL / REPAIR${RESET}"
    echo
    if [[ $EUID -ne 0 ]]; then
        error "Run this option as root."
        pause
        return
    fi

    if command -v docker >/dev/null 2>&1; then
        info "Docker command already exists."
        docker --version
        if docker info >/dev/null 2>&1; then
            success "Docker daemon is ready."
            pause
            return
        fi
    fi

    if command -v apt-get >/dev/null 2>&1; then
        run_anim "Updating package index" apt-get update -y || true
        run_anim "Installing Docker" apt-get install -y docker.io curl ca-certificates || {
            error "Docker installation failed."
            pause
            return
        }
    elif command -v dnf >/dev/null 2>&1; then
        run_anim "Installing Docker" dnf install -y docker curl ca-certificates || {
            error "Docker installation failed."
            pause
            return
        }
    elif command -v yum >/dev/null 2>&1; then
        run_anim "Installing Docker" yum install -y docker curl ca-certificates || {
            error "Docker installation failed."
            pause
            return
        }
    else
        error "Unsupported package manager. Install Docker manually."
        pause
        return
    fi

    if command -v systemctl >/dev/null 2>&1; then
        systemctl enable --now docker >/dev/null 2>&1 || true
    fi

    if docker info >/dev/null 2>&1; then
        success "Docker is ready."
    else
        warn "Docker installed, but daemon is not reachable in this environment."
        info "This can happen inside restricted containers without a Docker daemon."
    fi
    pause
}

# -------------------- Create --------------------
create_servers(){
    logo
    center "${BOLD}${LIGHT_PURPLE}CREATE KINGCLOUD SERVERS${RESET}"
    echo
    require_docker || { pause; return; }

    read -rp "$(printf "${CYAN}How many servers? ${RESET}")" count
    [[ "$count" =~ ^[0-9]+$ && "$count" -gt 0 ]] || {
        error "Enter a valid number."
        pause
        return
    }

    echo
    info "Pulling ${IMAGE}..."
    docker pull "$IMAGE" >/dev/null 2>&1 &
    spinner $! "Downloading Ubuntu image"
    wait $! 2>/dev/null || true
    success "Image ready."
    echo

    local created=0
    while (( created < count )); do
        local num=$((created + 1))
        echo
        printf "${PURPLE}┌─ Server %s/%s ───────────────────────────────────────┐${RESET}\n" "$num" "$count"
        read -rp "$(printf "${CYAN}│ Name: ${RESET}")" name
        name=$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')

        if ! valid_name "$name"; then
            error "Invalid name. Use letters, numbers, . _ - only."
            continue
        fi

        if docker ps -a --format '{{.Names}}' | grep -Fxq "$name"; then
            error "Server '$name' already exists."
            continue
        fi

        read -rp "$(printf "${CYAN}│ Memory limit (example 2g, blank = unlimited): ${RESET}")" mem
        read -rp "$(printf "${CYAN}│ CPU limit (example 2, blank = unlimited): ${RESET}")" cpu
        printf "${PURPLE}└──────────────────────────────────────────────────────┘${RESET}\n"

        local args=(run -dit
            --name "$name"
            --hostname "$name"
            --label "$LABEL"
            --label "$SUSPEND_LABEL=false"
            --restart unless-stopped
            "$IMAGE" /bin/bash)

        [[ -n "$mem" ]] && args=(run -dit --name "$name" --hostname "$name" --label "$LABEL" --label "$SUSPEND_LABEL=false" --restart unless-stopped --memory "$mem" "${cpu:+--cpus=$cpu}" "$IMAGE" /bin/bash)

        if docker "${args[@]}" >/dev/null 2>&1; then
            # Basic tools are useful for a fresh Ubuntu code-server container.
            docker exec "$name" bash -lc 'apt-get update -y >/dev/null 2>&1 && apt-get install -y curl sudo git ca-certificates >/dev/null 2>&1 || true' &
            success "Created: $name"
            created=$((created + 1))
        else
            error "Failed to create: $name"
        fi
    done

    echo
    success "$created server(s) created."
    pause
}

# -------------------- Server picker --------------------
pick_server(){
    mapfile_containers
    if (( ${#CONTAINERS[@]} == 0 )); then
        error "No KingCloud servers found."
        return 1
    fi

    echo
    local i name
    for i in "${!CONTAINERS[@]}"; do
        name="${CONTAINERS[$i]}"
        printf " ${PURPLE}[%02d]${RESET} %-28s " "$((i+1))" "$name"
        status_text "$name"
        echo
    done
    echo
    read -rp "$(printf "${CYAN}Select number or type server name: ${RESET}")" choice

    if [[ "$choice" =~ ^[0-9]+$ ]]; then
        local idx=$((choice - 1))
        (( idx >= 0 && idx < ${#CONTAINERS[@]} )) || return 1
        SELECTED="${CONTAINERS[$idx]}"
    else
        docker ps -a --format '{{.Names}}' | grep -Fxq "$choice" || return 1
        is_kingcloud "$choice" || return 1
        SELECTED="$choice"
    fi
    return 0
}

# -------------------- Code-server --------------------
install_codeserver(){
    logo
    center "${BOLD}${LIGHT_PURPLE}CODE-SERVER INSTALLER${RESET}"
    echo
    require_docker || { pause; return; }

    if ! pick_server; then
        error "Invalid server."
        pause
        return
    fi

    local name="$SELECTED"
    if is_suspended "$name"; then
        warn "$name is suspended. Unsuspend it first."
        pause
        return
    fi

    docker start "$name" >/dev/null 2>&1 || true
    echo
    info "Installing Code-Server inside $name..."
    docker exec "$name" bash -lc '
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y >/dev/null 2>&1
        apt-get install -y curl ca-certificates sudo git >/dev/null 2>&1
        if ! command -v code-server >/dev/null 2>&1; then
            curl -fsSL https://code-server.dev/install.sh | sh
        fi
    ' >/tmp/kc_codeserver.out 2>/tmp/kc_codeserver.err &
    local pid=$!
    spinner "$pid" "Installing Code-Server"
    wait "$pid"
    local rc=$?

    if (( rc == 0 )) && docker exec "$name" bash -lc 'command -v code-server >/dev/null 2>&1'; then
        success "Code-Server installed on $name."
        echo
        docker exec "$name" code-server --version 2>/dev/null | head -1 || true
        echo
        info "Start it inside the server with:"
        printf "  ${LIGHT_PURPLE}code-server --bind-addr 0.0.0.0:8080${RESET}\n"
    else
        error "Code-Server installation failed."
        [[ -s /tmp/kc_codeserver.err ]] && tail -10 /tmp/kc_codeserver.err
    fi
    pause
}

open_shell(){
    logo
    center "${BOLD}${LIGHT_PURPLE}SERVER CONSOLE${RESET}"
    echo
    require_docker || { pause; return; }
    pick_server || { error "Invalid server."; pause; return; }

    local name="$SELECTED"
    if is_suspended "$name"; then
        warn "Server is suspended."
        pause
        return
    fi
    docker start "$name" >/dev/null 2>&1 || true
    echo
    printf "${PURPLE}╭─── ${WHITE}%s${PURPLE} ─────────────────────────────────────────╮${RESET}\n" "$name"
    printf "${PURPLE}│${RESET} ${GRAY}Interactive Bash console — type 'exit' to return.${RESET}\n"
    printf "${PURPLE}╰──────────────────────────────────────────────────────╯${RESET}\n\n"
    docker exec -it "$name" /bin/bash
}

server_logs(){
    logo
    center "${BOLD}${LIGHT_PURPLE}SERVER LOGS${RESET}"
    echo
    require_docker || { pause; return; }
    pick_server || { error "Invalid server."; pause; return; }
    echo
    docker logs --tail 100 "$SELECTED" 2>&1
    pause
}

# -------------------- Bulk actions --------------------
restart_all(){
    logo
    center "${BOLD}${LIGHT_PURPLE}RESTART ALL ACTIVE SERVERS${RESET}"
    echo
    require_docker || { pause; return; }

    local name n=0
    while read -r name; do
        [[ -z "$name" ]] && continue
        if is_suspended "$name"; then
            continue
        fi
        docker restart "$name" >/dev/null 2>&1 && {
            success "$name restarted"
            n=$((n+1))
        }
    done < <(all_containers)
    echo
    info "$n server(s) restarted. Suspended servers were skipped."
    pause
}

stop_all(){
    logo
    center "${BOLD}${LIGHT_PURPLE}STOP ALL${RESET}"
    echo
    require_docker || { pause; return; }

    read -rp "$(printf "${YELLOW}Stop all non-suspended servers? [y/N]: ${RESET}")" ans
    [[ "$ans" =~ ^[Yy]$ ]] || { info "Cancelled."; pause; return; }

    local name n=0
    while read -r name; do
        [[ -z "$name" ]] && continue
        is_suspended "$name" && continue
        if docker stop "$name" >/dev/null 2>&1; then
            success "$name stopped"
            n=$((n+1))
        fi
    done < <(all_containers)
    info "$n server(s) stopped."
    pause
}

start_all(){
    logo
    center "${BOLD}${LIGHT_PURPLE}START ALL${RESET}"
    echo
    require_docker || { pause; return; }

    local name n=0
    while read -r name; do
        [[ -z "$name" ]] && continue
        if is_suspended "$name"; then
            warn "$name skipped (suspended)"
            continue
        fi
        if docker start "$name" >/dev/null 2>&1; then
            success "$name started"
            n=$((n+1))
        fi
    done < <(all_containers)
    info "$n server(s) started."
    pause
}

# -------------------- Suspend / Unsuspend --------------------
suspend_server(){
    logo
    center "${BOLD}${LIGHT_PURPLE}SUSPEND SERVER${RESET}"
    echo
    require_docker || { pause; return; }
    pick_server || { error "Invalid server."; pause; return; }

    local name="$SELECTED"
    if is_suspended "$name"; then
        warn "$name is already suspended."
        pause
        return
    fi

    read -rp "$(printf "${YELLOW}Suspend '$name'? [y/N]: ${RESET}")" ans
    [[ "$ans" =~ ^[Yy]$ ]] || { info "Cancelled."; pause; return; }

    docker update --label-add "$SUSPEND_LABEL=true" --restart=no "$name" >/dev/null 2>&1 || true
    docker stop "$name" >/dev/null 2>&1 || true
    success "$name is now suspended."
    pause
}

unsuspend_server(){
    logo
    center "${BOLD}${LIGHT_PURPLE}UNSUSPEND SERVER${RESET}"
    echo
    require_docker || { pause; return; }

    local suspended=()
    local name
    while read -r name; do
        [[ -n "$name" ]] && is_suspended "$name" && suspended+=("$name")
    done < <(all_containers)

    if (( ${#suspended[@]} == 0 )); then
        info "No suspended servers."
        pause
        return
    fi

    for name in "${suspended[@]}"; do
        printf " ${YELLOW}•${RESET} %s\n" "$name"
    done
    echo
    read -rp "$(printf "${CYAN}Type server name to unsuspend: ${RESET}")" name

    printf '%s\n' "${suspended[@]}" | grep -Fxq "$name" || {
        error "Suspended server not found."
        pause
        return
    }

    docker update --label-add "$SUSPEND_LABEL=false" --restart=unless-stopped "$name" >/dev/null 2>&1 || true
    if docker start "$name" >/dev/null 2>&1; then
        success "$name unsuspended and started."
    else
        error "Unsuspended, but failed to start $name."
    fi
    pause
}

# -------------------- Delete --------------------
delete_server(){
    logo
    center "${BOLD}${LIGHT_PURPLE}DELETE SERVER${RESET}"
    echo
    require_docker || { pause; return; }
    pick_server || { error "Invalid server."; pause; return; }

    local name="$SELECTED"
    echo
    warn "This permanently removes the container and its writable container filesystem."
    read -rp "$(printf "${RED}Type '$name' to confirm deletion: ${RESET}")" confirm
    if [[ "$confirm" == "$name" ]]; then
        docker rm -f "$name" >/dev/null 2>&1 && success "$name deleted." || error "Delete failed."
    else
        info "Deletion cancelled."
    fi
    pause
}

# -------------------- Dashboard / List --------------------
list_servers(){
    logo
    center "${BOLD}${LIGHT_PURPLE}KINGCLOUD SERVER LIST${RESET}"
    echo
    require_docker || { pause; return; }

    printf "${PURPLE}%-4s %-27s %-13s %-12s %-12s${RESET}\n" "#" "SERVER" "STATUS" "IMAGE" "UPTIME"
    hr
    local i=0 name status image uptime
    while read -r name; do
        [[ -z "$name" ]] && continue
        i=$((i+1))
        status=$(docker inspect -f '{{.State.Status}}' "$name" 2>/dev/null)
        image=$(docker inspect -f '{{.Config.Image}}' "$name" 2>/dev/null)
        uptime=$(docker inspect -f '{{.State.StartedAt}}' "$name" 2>/dev/null | cut -d'T' -f1)
        printf "${WHITE}%-4s %-27s %-13b %-12s %-12s${RESET}\n" "$i" "$name" "$(status_text "$name")" "${image:0:12}" "${uptime:0:10}"
    done < <(all_containers)

    (( i == 0 )) && info "No servers found."
    echo
    pause
}

stats(){
    logo
    center "${BOLD}${LIGHT_PURPLE}LIVE RESOURCE MONITOR${RESET}"
    echo
    require_docker || { pause; return; }

    local name cpu mem
    while true; do
        clear
        printf "${PURPLE}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"
        center "${LIGHT_PURPLE}${BOLD}KINGCLOUD LIVE MONITOR${RESET}"
        printf "${PURPLE}╚══════════════════════════════════════════════════════════════════════╝${RESET}\n\n"
        printf "${GRAY}Refresh: 2s  •  Press Ctrl+C to return${RESET}\n\n"
        docker stats --no-stream --filter "label=$LABEL" --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}' 2>/dev/null || true
        sleep 2
    done
}

about(){
    logo
    center "${BOLD}${LIGHT_PURPLE}ABOUT KINGCLOUD${RESET}"
    echo
    printf "${CYAN}KINGCLOUD${RESET} ${WHITE}Code-Server Control Center${RESET}\n\n"
    printf "${GRAY}Version:${RESET} ${LIGHT_PURPLE}%s${RESET}\n" "$VERSION"
    printf "${GRAY}Engine :${RESET} Docker\n"
    printf "${GRAY}Image  :${RESET} Ubuntu 24.04\n"
    printf "${GRAY}Design :${RESET} Terminal Cyber / Purple UI\n\n"
    echo "${LIGHT_PURPLE}Features${RESET}"
    echo "  ${GREEN}◆${RESET} Multi-server Docker management"
    echo "  ${GREEN}◆${RESET} Code-Server installer"
    echo "  ${GREEN}◆${RESET} Start / Stop / Restart / Delete"
    echo "  ${GREEN}◆${RESET} Suspend / Unsuspend protection"
    echo "  ${GREEN}◆${RESET} Interactive server console"
    echo "  ${GREEN}◆${RESET} Live Docker resource monitor"
    echo "  ${GREEN}◆${RESET} Server logs"
    echo "  ${GREEN}◆${RESET} Bulk actions"
    echo "  ${GREEN}◆${RESET} Resource limits at creation"
    echo
    printf "${PURPLE}Made for ${LIGHT_PURPLE}KINGCLOUD${PURPLE} • Premium terminal experience${RESET}\n"
    pause
}

coming_soon(){
    logo
    center "${BOLD}${LIGHT_PURPLE}COMING SOON${RESET}"
    echo
    center "${YELLOW}◆${RESET} ${WHITE}KingCloud Cloud Dashboard${RESET}"
    center "${YELLOW}◆${RESET} ${WHITE}Web File Manager${RESET}"
    center "${YELLOW}◆${RESET} ${WHITE}Automatic Backups${RESET}"
    center "${YELLOW}◆${RESET} ${WHITE}Server Templates${RESET}"
    center "${YELLOW}◆${RESET} ${WHITE}Port Manager${RESET}"
    center "${YELLOW}◆${RESET} ${WHITE}One-Click HTTPS${RESET}"
    center "${YELLOW}◆${RESET} ${WHITE}Multi-Node Management${RESET}"
    echo
    pause
}

# -------------------- Main dashboard --------------------
dashboard(){
    logo
    boot_animation

    while true; do
        local running total suspended
        if docker_ready; then
            running=$(count_running)
            total=$(count_total)
            suspended=$(count_suspended)
        else
            running=0
            total=0
            suspended=0
        fi

        clear
        printf "${PURPLE}╔══════════════════════════════════════════════════════════════════╗${RESET}\n"
        center "${LIGHT_PURPLE}${BOLD}👑 KINGCLOUD CODE-SERVER CONTROL CENTER${RESET}"
        printf "${PURPLE}╚══════════════════════════════════════════════════════════════════╝${RESET}\n"
        echo
        printf "${GRAY}Docker${RESET} ${PURPLE}•${RESET} ${GRAY}Multi Server${RESET} ${PURPLE}•${RESET} ${GRAY}Code-Server${RESET} ${PURPLE}•${RESET} ${GRAY}KingCloud${RESET}\n\n"

        printf " ${GREEN}●${RESET} Running    : ${WHITE}%s${RESET}\n" "$running"
        printf " ${BLUE}●${RESET} Total      : ${WHITE}%s${RESET}\n" "$total"
        printf " ${YELLOW}●${RESET} Suspended  : ${WHITE}%s${RESET}\n" "$suspended"
        echo
        hr
        echo

        printf " ${GREEN}[1]${RESET} 🚀 Install Code-Server\n"
        printf " ${CYAN}[2]${RESET} 📋 List Servers\n"
        printf " ${BLUE}[3]${RESET} 🔄 Restart All\n"
        printf " ${RED}[4]${RESET} ⏹  Stop All\n"
        printf " ${GREEN}[5]${RESET} ▶  Start All\n"
        printf " ${YELLOW}[6]${RESET} ✨ Coming Soon\n"
        printf " ${RED}[7]${RESET} 🗑  Delete Server\n"
        printf " ${YELLOW}[8]${RESET} 🔒 Suspend Server\n"
        printf " ${GREEN}[9]${RESET} 🔓 Unsuspend Server\n"
        printf " ${CYAN}[10]${RESET} ℹ  About & Features\n"
        echo
        printf " ${PURPLE}[11]${RESET} ➕ Create Server\n"
        printf " ${CYAN}[12]${RESET} 💻 Open Console\n"
        printf " ${BLUE}[13]${RESET} 📊 Live Resource Monitor\n"
        printf " ${LIGHT_PURPLE}[14]${RESET} 📜 Server Logs\n"
        printf " ${GRAY}[15]${RESET} 🐳 Install / Repair Docker\n"
        printf " ${RED}[0]${RESET} 🚪 Exit\n"
        echo
        hr
        printf "${LIGHT_PURPLE} KINGCLOUD${RESET} ${GRAY}v${VERSION} • Control Center${RESET}\n\n"

        read -rp "$(printf "${CYAN}Select option: ${RESET}")" option
        case "$option" in
            1) install_codeserver ;;
            2) list_servers ;;
            3) restart_all ;;
            4) stop_all ;;
            5) start_all ;;
            6) coming_soon ;;
            7) delete_server ;;
            8) suspend_server ;;
            9) unsuspend_server ;;
            10) about ;;
            11) create_servers ;;
            12) open_shell ;;
            13) stats ;;
            14) server_logs ;;
            15) install_docker ;;
            0)
                clear
                center "${LIGHT_PURPLE}👑 KINGCLOUD CONTROL CENTER CLOSED${RESET}"
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

# -------------------- Startup --------------------
if [[ $EUID -ne 0 ]]; then
    warn "Root is recommended for Docker management."
fi

dashboard
