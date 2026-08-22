#!/usr/bin/env bash

# ============================================================
#        👑 KINGCLOUD • DOCKER CONTROL CENTER
#        Premium Terminal GUI • v3.0
# ============================================================

set +e

# -------------------- COLORS --------------------
RESET="\033[0m"
BOLD="\033[1m"
DIM="\033[2m"

PURPLE="\033[38;5;141m"
LIGHT_PURPLE="\033[38;5;183m"
CYAN="\033[38;5;51m"
GREEN="\033[38;5;82m"
YELLOW="\033[38;5;226m"
RED="\033[38;5;196m"
BLUE="\033[38;5;75m"
WHITE="\033[97m"
GRAY="\033[90m"

# -------------------- CONFIG --------------------
LABEL="kingcloud.container=true"
IMAGE="ubuntu:24.04"

# -------------------- TERMINAL --------------------
cleanup() {
    printf "\033[0m\033[?25h"
    clear
    exit 0
}

trap cleanup INT TERM

hide_cursor() { printf "\033[?25l"; }
show_cursor() { printf "\033[?25h"; }

pause_screen() {
    echo
    read -rp "  ${GRAY}Press Enter to continue...${RESET}"
}

line() {
    printf "${PURPLE}  ─────────────────────────────────────────────────────${RESET}\n"
}

# -------------------- ANIMATION --------------------
spinner() {
    local pid=$1
    local text="${2:-Working}"
    local chars=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0

    hide_cursor

    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${PURPLE}${chars[$i]}${RESET} ${WHITE}${text}${RESET}..."
        i=$(( (i + 1) % ${#chars[@]} ))
        sleep 0.08
    done

    printf "\r\033[K"
    show_cursor
}

run_loading() {
    local text="$1"
    shift

    "$@" >/tmp/kc_command.log 2>&1 &
    local pid=$!

    spinner "$pid" "$text"
    wait "$pid"
    local result=$?

    if [ "$result" -eq 0 ]; then
        printf "  ${GREEN}✔${RESET} ${WHITE}${text}${RESET}\n"
    else
        printf "  ${RED}✖${RESET} ${WHITE}${text} failed${RESET}\n"
        echo
        sed 's/^/  /' /tmp/kc_command.log | tail -20
    fi

    return "$result"
}

# -------------------- HEADER --------------------
logo() {
    echo
    printf "${PURPLE}"
    cat <<'EOF'
       ██╗  ██╗██╗███╗   ██╗ ██████╗
       ██║ ██╔╝██║████╗  ██║██╔════╝
       █████╔╝ ██║██╔██╗ ██║██║  ███╗
       ██╔═██╗ ██║██║╚██╗██║██║   ██║
       ██║  ██╗██║██║ ╚████║╚██████╔╝
       ╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝ ╚═════╝
EOF
    printf "${RESET}"

    echo
    printf "              ${LIGHT_PURPLE}${BOLD}CONTAINER CONTROL CENTER${RESET}\n"
    printf "                 ${PURPLE}K I N G C L O U D${RESET}\n"
    echo
}

# -------------------- INTRO --------------------
intro() {
    clear
    hide_cursor

    local frames=(
        "  ${PURPLE}◆${RESET} Initializing KINGCLOUD..."
        "  ${CYAN}◆${RESET} Loading Docker Control Center..."
        "  ${BLUE}◆${RESET} Connecting to container engine..."
        "  ${LIGHT_PURPLE}◆${RESET} Loading management modules..."
        "  ${GREEN}◆${RESET} KINGCLOUD is ready."
    )

    for frame in "${frames[@]}"; do
        printf "\r\033[K$frame"
        sleep 0.25
    done

    show_cursor
    sleep 0.4
    clear
}

# -------------------- DOCKER CHECK --------------------
docker_check() {
    if ! command -v docker >/dev/null 2>&1; then
        echo
        printf "  ${RED}✖ Docker is not installed.${RESET}\n"
        echo
        read -rp "  Install Docker now? [y/N]: " ans

        if [[ "$ans" =~ ^[Yy]$ ]]; then
            clear
            logo
            printf "  ${PURPLE}Installing Docker...${RESET}\n\n"

            if command -v apt >/dev/null 2>&1; then
                apt update -y
                apt install -y docker.io
            else
                echo "  ${RED}Unsupported package manager.${RESET}"
                pause_screen
                return 1
            fi

            command -v systemctl >/dev/null 2>&1 && {
                systemctl enable docker 2>/dev/null
                systemctl start docker 2>/dev/null
            }

            if ! command -v docker >/dev/null 2>&1; then
                echo "  ${RED}Docker installation failed.${RESET}"
                pause_screen
                return 1
            fi

            echo
            printf "  ${GREEN}✔ Docker installed successfully.${RESET}\n"
            sleep 1
        else
            return 1
        fi
    fi

    if ! docker info >/dev/null 2>&1; then
        echo
        printf "  ${RED}✖ Docker daemon is not accessible.${RESET}\n"
        echo "  ${GRAY}Try starting Docker and run the script again.${RESET}"
        pause_screen
        return 1
    fi

    return 0
}

# -------------------- CONTAINER LIST --------------------
get_containers() {
    mapfile -t CONTAINERS < <(
        docker ps -a \
            --filter "label=$LABEL" \
            --format '{{.Names}}' | sort
    )
}

container_count() {
    get_containers
    echo "${#CONTAINERS[@]}"
}

# -------------------- STATUS --------------------
status_value() {
    local name="$1"
    docker inspect -f '{{.State.Status}}' "$name" 2>/dev/null
}

is_suspended() {
    local name="$1"
    docker inspect -f '{{index .Config.Labels "kingcloud.suspended"}}' "$name" 2>/dev/null
}

# -------------------- DASHBOARD --------------------
dashboard() {
    get_containers

    local total=${#CONTAINERS[@]}
    local running=0
    local stopped=0
    local suspended=0

    for name in "${CONTAINERS[@]}"; do
        local status
        status=$(status_value "$name")

        if [ "$status" = "running" ]; then
            running=$((running + 1))
        else
            stopped=$((stopped + 1))
        fi

        if [ "$(is_suspended "$name")" = "true" ]; then
            suspended=$((suspended + 1))
        fi
    done

    printf "  ${GREEN}●${RESET} Running    : ${WHITE}${running}${RESET}\n"
    printf "  ${CYAN}●${RESET} Total      : ${WHITE}${total}${RESET}\n"
    printf "  ${YELLOW}●${RESET} Suspended  : ${WHITE}${suspended}${RESET}\n"
    printf "  ${RED}●${RESET} Stopped    : ${WHITE}${stopped}${RESET}\n"
}

# -------------------- MAIN SCREEN --------------------
main_screen() {
    clear
    logo

    printf "  ${GRAY}Docker  •  Containers  •  Control  •  Monitoring${RESET}\n"
    echo

    dashboard

    echo
    line
    echo

    printf "  ${PURPLE}${BOLD}[1]${RESET}  🚀 Create Container\n"
    printf "  ${CYAN}${BOLD}[2]${RESET}  📋 Container List\n"
    printf "  ${BLUE}${BOLD}[3]${RESET}  🖥  Open Console\n"
    printf "  ${GREEN}${BOLD}[4]${RESET}  ▶  Start Container\n"
    printf "  ${RED}${BOLD}[5]${RESET}  ■  Stop Container\n"
    printf "  ${PURPLE}${BOLD}[6]${RESET}  🔄 Restart Container\n"
    printf "  ${YELLOW}${BOLD}[7]${RESET}  🗑  Delete Container\n"
    printf "  ${YELLOW}${BOLD}[8]${RESET}  🔒 Suspend Container\n"
    printf "  ${GREEN}${BOLD}[9]${RESET}  🔓 Unsuspend Container\n"
    printf "  ${CYAN}${BOLD}[10]${RESET} 📜 Container Logs\n"
    printf "  ${BLUE}${BOLD}[11]${RESET} 📊 Resource Monitor\n"
    printf "  ${PURPLE}${BOLD}[12]${RESET} ⚡ Bulk Controls\n"
    printf "  ${CYAN}${BOLD}[13]${RESET} 🔍 Inspect Container\n"
    printf "  ${LIGHT_PURPLE}${BOLD}[14]${RESET} 🧰 Execute Command\n"
    printf "  ${YELLOW}${BOLD}[15]${RESET} ✨ About & Features\n"
    printf "  ${RED}${BOLD}[0]${RESET}  Exit\n"

    echo
    line
    printf "  ${GRAY}KINGCLOUD • Fast • Simple • Powerful${RESET}\n"
    echo
}

# -------------------- CREATE --------------------
create_container() {
    clear
    logo

    printf "  ${PURPLE}${BOLD}CREATE CONTAINER${RESET}\n"
    line
    echo

    read -rp "  Container name: " NAME

    NAME=$(echo "$NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' )

    if [ -z "$NAME" ]; then
        printf "  ${RED}✖ Name cannot be empty.${RESET}\n"
        pause_screen
        return
    fi

    if docker ps -a --format '{{.Names}}' | grep -Fxq "$NAME"; then
        printf "  ${RED}✖ Container already exists.${RESET}\n"
        pause_screen
        return
    fi

    read -rp "  Hostname [$NAME]: " HOSTNAME
    HOSTNAME=${HOSTNAME:-$NAME}

    read -rp "  Memory limit [unlimited]: " MEMORY
    read -rp "  CPU limit [unlimited]: " CPU

    echo
    printf "  ${GRAY}Preparing Ubuntu 24.04 image...${RESET}\n"

    docker image inspect "$IMAGE" >/dev/null 2>&1 || {
        run_loading "Pulling Ubuntu image" docker pull "$IMAGE"
    }

    echo
    printf "  ${PURPLE}Creating ${WHITE}$NAME${PURPLE}...${RESET}\n"

    CMD=(docker run -dit
        --name "$NAME"
        --hostname "$HOSTNAME"
        --label "$LABEL"
        --label "kingcloud.suspended=false"
        --restart unless-stopped
        "$IMAGE"
        /bin/bash
    )

    [ -n "$MEMORY" ] && CMD+=(--memory "$MEMORY")
    [ -n "$CPU" ] && CMD+=(--cpus "$CPU")

    # Rebuild command correctly with resource arguments before image.
    CMD=(docker run -dit
        --name "$NAME"
        --hostname "$HOSTNAME"
        --label "$LABEL"
        --label "kingcloud.suspended=false"
        --restart unless-stopped
    )

    [ -n "$MEMORY" ] && CMD+=(--memory "$MEMORY")
    [ -n "$CPU" ] && CMD+=(--cpus "$CPU")

    CMD+=("$IMAGE" /bin/bash)

    "${CMD[@]}" >/tmp/kc_create.log 2>&1

    if [ $? -eq 0 ]; then
        echo
        printf "  ${GREEN}✔ Container created successfully!${RESET}\n"
        printf "  ${GRAY}Name:${RESET} $NAME\n"
        printf "  ${GRAY}Image:${RESET} $IMAGE\n"
    else
        echo
        printf "  ${RED}✖ Creation failed.${RESET}\n"
        sed 's/^/  /' /tmp/kc_create.log
    fi

    pause_screen
}

# -------------------- SELECT CONTAINER --------------------
select_container() {
    get_containers

    if [ "${#CONTAINERS[@]}" -eq 0 ]; then
        printf "  ${YELLOW}No KINGCLOUD containers found.${RESET}\n"
        return 1
    fi

    echo
    for i in "${!CONTAINERS[@]}"; do
        local name="${CONTAINERS[$i]}"
        local status
        status=$(status_value "$name")

        if [ "$(is_suspended "$name")" = "true" ]; then
            printf "  ${YELLOW}%2d${RESET}  %-25s ${YELLOW}[SUSPENDED]${RESET}\n" \
                "$((i+1))" "$name"
        elif [ "$status" = "running" ]; then
            printf "  ${GREEN}%2d${RESET}  %-25s ${GREEN}[%s]${RESET}\n" \
                "$((i+1))" "$name" "$status"
        else
            printf "  ${RED}%2d${RESET}  %-25s ${RED}[%s]${RESET}\n" \
                "$((i+1))" "$name" "$status"
        fi
    done

    echo
    read -rp "  Select number: " CHOICE

    if ! [[ "$CHOICE" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    local index=$((CHOICE - 1))

    if [ "$index" -lt 0 ] || [ "$index" -ge "${#CONTAINERS[@]}" ]; then
        return 1
    fi

    SELECTED="${CONTAINERS[$index]}"
    return 0
}

# -------------------- LIST --------------------
list_containers() {
    clear
    logo

    printf "  ${PURPLE}${BOLD}CONTAINER LIST${RESET}\n"
    line
    echo

    get_containers

    if [ "${#CONTAINERS[@]}" -eq 0 ]; then
        printf "  ${GRAY}No containers available.${RESET}\n"
        pause_screen
        return
    fi

    printf "  ${GRAY}%-24s %-12s %-18s${RESET}\n" "NAME" "STATUS" "IMAGE"
    line

    for name in "${CONTAINERS[@]}"; do
        local status
        status=$(status_value "$name")

        if [ "$status" = "running" ]; then
            printf "  ${GREEN}%-24s${RESET} ${GREEN}%-12s${RESET} %-18s\n" \
                "$name" "$status" "$IMAGE"
        else
            printf "  ${RED}%-24s${RESET} ${RED}%-12s${RESET} %-18s\n" \
                "$name" "$status" "$IMAGE"
        fi
    done

    echo
    pause_screen
}

# -------------------- OPEN CONSOLE --------------------
open_console() {
    clear
    logo

    printf "  ${PURPLE}${BOLD}OPEN CONSOLE${RESET}\n"
    line

    if ! select_container; then
        printf "  ${RED}Invalid selection.${RESET}\n"
        pause_screen
        return
    fi

    local name="$SELECTED"

    if [ "$(is_suspended "$name")" = "true" ]; then
        printf "  ${YELLOW}Container is suspended.${RESET}\n"
        pause_screen
        return
    fi

    if [ "$(status_value "$name")" != "running" ]; then
        printf "  ${CYAN}Starting $name...${RESET}\n"
        docker start "$name" >/dev/null
    fi

    clear
    printf "${PURPLE}"
    echo "╔══════════════════════════════════════════════════════════╗"
    printf "║                 👑 KINGCLOUD CONSOLE                    ║\n"
    printf "║                 %-36s ║\n" "$name"
    echo "╚══════════════════════════════════════════════════════════╝"
    printf "${RESET}\n"

    docker exec -it "$name" /bin/bash

    pause_screen
}

# -------------------- START --------------------
start_container() {
    clear
    logo
    printf "  ${GREEN}${BOLD}START CONTAINER${RESET}\n"
    line

    if ! select_container; then
        printf "  ${RED}Invalid selection.${RESET}\n"
        pause_screen
        return
    fi

    if [ "$(is_suspended "$SELECTED")" = "true" ]; then
        printf "  ${YELLOW}✖ Container is suspended. Unsuspend it first.${RESET}\n"
    else
        run_loading "Starting $SELECTED" docker start "$SELECTED"
    fi

    pause_screen
}

# -------------------- STOP --------------------
stop_container() {
    clear
    logo
    printf "  ${RED}${BOLD}STOP CONTAINER${RESET}\n"
    line

    if ! select_container; then
        printf "  ${RED}Invalid selection.${RESET}\n"
        pause_screen
        return
    fi

    run_loading "Stopping $SELECTED" docker stop "$SELECTED"
    pause_screen
}

# -------------------- RESTART --------------------
restart_container() {
    clear
    logo
    printf "  ${PURPLE}${BOLD}RESTART CONTAINER${RESET}\n"
    line

    if ! select_container; then
        printf "  ${RED}Invalid selection.${RESET}\n"
        pause_screen
        return
    fi

    if [ "$(is_suspended "$SELECTED")" = "true" ]; then
        printf "  ${YELLOW}✖ Container is suspended.${RESET}\n"
    else
        run_loading "Restarting $SELECTED" docker restart "$SELECTED"
    fi

    pause_screen
}

# -------------------- DELETE --------------------
delete_container() {
    clear
    logo
    printf "  ${RED}${BOLD}DELETE CONTAINER${RESET}\n"
    line

    if ! select_container; then
        printf "  ${RED}Invalid selection.${RESET}\n"
        pause_screen
        return
    fi

    echo
    printf "  ${RED}WARNING:${RESET} This permanently removes ${WHITE}$SELECTED${RESET}.\n"
    read -rp "  Type DELETE to confirm: " CONFIRM

    if [ "$CONFIRM" = "DELETE" ]; then
        run_loading "Deleting $SELECTED" docker rm -f "$SELECTED"
    else
        printf "  ${YELLOW}Cancelled.${RESET}\n"
    fi

    pause_screen
}

# -------------------- SUSPEND --------------------
suspend_container() {
    clear
    logo
    printf "  ${YELLOW}${BOLD}SUSPEND CONTAINER${RESET}\n"
    line

    if ! select_container; then
        printf "  ${RED}Invalid selection.${RESET}\n"
        pause_screen
        return
    fi

    docker stop "$SELECTED" >/dev/null 2>&1

    docker update \
        --restart=no \
        "$SELECTED" >/dev/null 2>&1

    docker commit "$SELECTED" "$SELECTED:kingcloud-suspended" >/dev/null 2>&1

    docker rm "$SELECTED" >/dev/null 2>&1

    docker run -dit \
        --name "$SELECTED" \
        --hostname "$SELECTED" \
        --label "$LABEL" \
        --label "kingcloud.suspended=true" \
        "$SELECTED:kingcloud-suspended" \
        /bin/bash >/dev/null 2>&1

    printf "  ${YELLOW}🔒 $SELECTED is now suspended.${RESET}\n"
    pause_screen
}

# -------------------- UNSUSPEND --------------------
unsuspend_container() {
    clear
    logo
    printf "  ${GREEN}${BOLD}UNSUSPEND CONTAINER${RESET}\n"
    line

    get_containers

    local found=0

    for name in "${CONTAINERS[@]}"; do
        if [ "$(is_suspended "$name")" = "true" ]; then
            found=1
            printf "  ${YELLOW}•${RESET} $name\n"
        fi
    done

    if [ "$found" -eq 0 ]; then
        printf "  ${GRAY}No suspended containers.${RESET}\n"
        pause_screen
        return
    fi

    echo
    read -rp "  Enter container name to unsuspend: " NAME

    if ! docker ps -a --format '{{.Names}}' | grep -Fxq "$NAME"; then
        printf "  ${RED}Container not found.${RESET}\n"
        pause_screen
        return
    fi

    if [ "$(is_suspended "$NAME")" != "true" ]; then
        printf "  ${YELLOW}Container is not suspended.${RESET}\n"
        pause_screen
        return
    fi

    docker update \
        --restart unless-stopped \
        "$NAME" >/dev/null 2>&1

    docker update \
        --label-add "kingcloud.suspended=false" \
        "$NAME" >/dev/null 2>&1

    docker start "$NAME" >/dev/null 2>&1

    printf "  ${GREEN}✔ $NAME unsuspended and started.${RESET}\n"
    pause_screen
}

# -------------------- LOGS --------------------
container_logs() {
    clear
    logo
    printf "  ${CYAN}${BOLD}CONTAINER LOGS${RESET}\n"
    line

    if ! select_container; then
        printf "  ${RED}Invalid selection.${RESET}\n"
        pause_screen
        return
    fi

    clear
    printf "${PURPLE}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════╗"
    printf "║                 📜 CONTAINER LOGS                        ║\n"
    printf "║                 %-36s ║\n" "$SELECTED"
    echo "╚══════════════════════════════════════════════════════════╝"
    printf "${RESET}\n"

    docker logs --tail 100 "$SELECTED" 2>&1

    pause_screen
}

# -------------------- RESOURCE MONITOR --------------------
resource_monitor() {
    clear
    logo

    printf "  ${BLUE}${BOLD}RESOURCE MONITOR${RESET}\n"
    line
    echo

    get_containers

    if [ "${#CONTAINERS[@]}" -eq 0 ]; then
        printf "  ${GRAY}No containers found.${RESET}\n"
        pause_screen
        return
    fi

    docker stats \
        --no-stream \
        --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}" \
        "${CONTAINERS[@]}" 2>/dev/null

    echo
    pause_screen
}

# -------------------- BULK CONTROLS --------------------
bulk_controls() {
    while true; do
        clear
        logo

        printf "  ${PURPLE}${BOLD}BULK CONTROLS${RESET}\n"
        line
        echo

        printf "  ${GREEN}[1]${RESET} ▶ Start All\n"
        printf "  ${RED}[2]${RESET} ■ Stop All\n"
        printf "  ${PURPLE}[3]${RESET} 🔄 Restart All\n"
        printf "  ${CYAN}[4]${RESET} 📋 Refresh Status\n"
        printf "  ${GRAY}[0]${RESET} ← Back\n"

        echo
        read -rp "  Select: " B

        case "$B" in
            1)
                get_containers
                for name in "${CONTAINERS[@]}"; do
                    if [ "$(is_suspended "$name")" != "true" ]; then
                        docker start "$name" >/dev/null 2>&1
                    fi
                done
                printf "  ${GREEN}✔ All eligible containers started.${RESET}\n"
                pause_screen
                ;;
            2)
                get_containers
                for name in "${CONTAINERS[@]}"; do
                    docker stop "$name" >/dev/null 2>&1
                done
                printf "  ${GREEN}✔ All containers stopped.${RESET}\n"
                pause_screen
                ;;
            3)
                get_containers
                for name in "${CONTAINERS[@]}"; do
                    if [ "$(is_suspended "$name")" != "true" ]; then
                        docker restart "$name" >/dev/null 2>&1
                    fi
                done
                printf "  ${GREEN}✔ All eligible containers restarted.${RESET}\n"
                pause_screen
                ;;
            4)
                pause_screen
                ;;
            0)
                return
                ;;
            *)
                printf "  ${RED}Invalid option.${RESET}\n"
                sleep 1
                ;;
        esac
    done
}

# -------------------- INSPECT --------------------
inspect_container() {
    clear
    logo

    printf "  ${BLUE}${BOLD}CONTAINER INSPECTOR${RESET}\n"
    line

    if ! select_container; then
        printf "  ${RED}Invalid selection.${RESET}\n"
        pause_screen
        return
    fi

    echo
    docker inspect "$SELECTED" | less -R

    pause_screen
}

# -------------------- EXEC COMMAND --------------------
execute_command() {
    clear
    logo

    printf "  ${LIGHT_PURPLE}${BOLD}EXECUTE COMMAND${RESET}\n"
    line

    if ! select_container; then
        printf "  ${RED}Invalid selection.${RESET}\n"
        pause_screen
        return
    fi

    if [ "$(status_value "$SELECTED")" != "running" ]; then
        printf "  ${YELLOW}Container is not running.${RESET}\n"
        read -rp "  Start it? [Y/n]: " A

        if [[ ! "$A" =~ ^[Nn]$ ]]; then
            docker start "$SELECTED" >/dev/null 2>&1
        else
            pause_screen
            return
        fi
    fi

    echo
    read -rp "  Command: " COMMAND

    if [ -z "$COMMAND" ]; then
        printf "  ${RED}Command cannot be empty.${RESET}\n"
        pause_screen
        return
    fi

    echo
    printf "  ${PURPLE}Running:${RESET} $COMMAND\n\n"

    docker exec -it "$SELECTED" /bin/bash -lc "$COMMAND"

    echo
    pause_screen
}

# -------------------- ABOUT --------------------
about_features() {
    clear
    logo

    printf "  ${LIGHT_PURPLE}${BOLD}KINGCLOUD • ABOUT & FEATURES${RESET}\n"
    line
    echo

    printf "  ${PURPLE}◆${RESET} Premium Terminal GUI\n"
    printf "  ${PURPLE}◆${RESET} Animated loading system\n"
    printf "  ${PURPLE}◆${RESET} Docker container management\n"
    printf "  ${PURPLE}◆${RESET} Create / Start / Stop / Restart\n"
    printf "  ${PURPLE}◆${RESET} Delete with confirmation\n"
    printf "  ${PURPLE}◆${RESET} Suspend / Unsuspend system\n"
    printf "  ${PURPLE}◆${RESET} Live Docker resource monitor\n"
    printf "  ${PURPLE}◆${RESET} Container console access\n"
    printf "  ${PURPLE}◆${RESET} Container logs viewer\n"
    printf "  ${PURPLE}◆${RESET} Docker inspect viewer\n"
    printf "  ${PURPLE}◆${RESET} Custom command executor\n"
    printf "  ${PURPLE}◆${RESET} Bulk Start / Stop / Restart\n"
    printf "  ${PURPLE}◆${RESET} Ubuntu 24.04 base image\n"
    printf "  ${PURPLE}◆${RESET} Memory / CPU limits\n"
    printf "  ${PURPLE}◆${RESET} Auto restart support\n"
    printf "  ${PURPLE}◆${RESET} KINGCLOUD purple-black theme\n"

    echo
    line
    printf "  ${GRAY}KINGCLOUD Container Control Center${RESET}\n"
    printf "  ${GRAY}Built for fast terminal management.${RESET}\n"

    pause_screen
}

# -------------------- MAIN LOOP --------------------
intro

if ! docker_check; then
    exit 1
fi

while true; do

    main_screen

    read -rp "  ${PURPLE}KINGCLOUD${RESET} › " OPTION

    case "$OPTION" in
        1)  create_container ;;
        2)  list_containers ;;
        3)  open_console ;;
        4)  start_container ;;
        5)  stop_container ;;
        6)  restart_container ;;
        7)  delete_container ;;
        8)  suspend_container ;;
        9)  unsuspend_container ;;
        10) container_logs ;;
        11) resource_monitor ;;
        12) bulk_controls ;;
        13) inspect_container ;;
        14) execute_command ;;
        15) about_features ;;

        0)
            clear
            printf "\n"
            printf "  ${PURPLE}👑 KINGCLOUD${RESET}\n"
            printf "  ${GRAY}Container Control Center closed.${RESET}\n\n"
            show_cursor
            exit 0
            ;;

        *)
            printf "\n  ${RED}✖ Invalid option.${RESET}\n"
            sleep 1
            ;;
    esac

done
