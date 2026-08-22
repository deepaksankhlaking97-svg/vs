#!/usr/bin/env bash

# ============================================================
#        👑 KINGCLOUD • DOCKER CONTROL CENTER
#        Premium Terminal GUI • Username/Password Edition
# ============================================================

set +e

# ---------------- COLORS ----------------
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

# ---------------- CONFIG ----------------
LABEL="kingcloud.container=true"
IMAGE="ubuntu:24.04"

KC_DIR="${HOME}/.kingcloud"
CRED_DIR="${KC_DIR}/credentials"

mkdir -p "$CRED_DIR"
chmod 700 "$KC_DIR" 2>/dev/null
chmod 700 "$CRED_DIR" 2>/dev/null

# ---------------- CLEAN EXIT ----------------
cleanup() {
    printf "\033[0m\033[?25h"
    clear
    exit 0
}

trap cleanup INT TERM

hide_cursor() {
    printf "\033[?25l"
}

show_cursor() {
    printf "\033[?25h"
}

pause_screen() {
    echo
    read -rp "  ${GRAY}Press Enter to continue...${RESET}"
}

line() {
    printf "${PURPLE}  ─────────────────────────────────────────────────────${RESET}\n"
}

# ============================================================
#                         LOGO
# ============================================================

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

# ============================================================
#                     INTRO ANIMATION
# ============================================================

intro() {
    clear
    hide_cursor

    local frames=(
        "  ${PURPLE}◆${RESET} Initializing KINGCLOUD..."
        "  ${CYAN}◆${RESET} Loading Docker Control Center..."
        "  ${BLUE}◆${RESET} Connecting to container engine..."
        "  ${LIGHT_PURPLE}◆${RESET} Loading authentication..."
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

# ============================================================
#                    DOCKER CHECK
# ============================================================

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
                printf "  ${RED}Unsupported package manager.${RESET}\n"
                pause_screen
                return 1
            fi

            command -v systemctl >/dev/null 2>&1 && {
                systemctl enable docker 2>/dev/null
                systemctl start docker 2>/dev/null
            }

            if ! command -v docker >/dev/null 2>&1; then
                printf "  ${RED}Docker installation failed.${RESET}\n"
                pause_screen
                return 1
            fi

            printf "  ${GREEN}✔ Docker installed successfully.${RESET}\n"
            sleep 1

        else
            return 1
        fi
    fi

    if ! docker info >/dev/null 2>&1; then

        echo
        printf "  ${RED}✖ Docker daemon is not accessible.${RESET}\n"
        printf "  ${GRAY}Start Docker and run the script again.${RESET}\n"

        pause_screen
        return 1
    fi

    return 0
}

# ============================================================
#                 PASSWORD HASH SYSTEM
# ============================================================

hash_password() {

    local password="$1"

    if command -v sha256sum >/dev/null 2>&1; then
        printf '%s' "$password" | sha256sum | awk '{print $1}'
    else
        printf '%s' "$password" | shasum -a 256 | awk '{print $1}'
    fi
}

save_credentials() {

    local name="$1"
    local username="$2"
    local password="$3"

    local file="${CRED_DIR}/${name}.cred"
    local hash

    hash=$(hash_password "$password")

    {
        echo "username=$username"
        echo "password_hash=$hash"
    } > "$file"

    chmod 600 "$file"
}

get_username() {

    local name="$1"
    local file="${CRED_DIR}/${name}.cred"

    if [ -f "$file" ]; then
        sed -n 's/^username=//p' "$file"
    fi
}

get_password_hash() {

    local name="$1"
    local file="${CRED_DIR}/${name}.cred"

    if [ -f "$file" ]; then
        sed -n 's/^password_hash=//p' "$file"
    fi
}

verify_credentials() {

    local name="$1"
    local username="$2"
    local password="$3"

    local saved_user
    local saved_hash
    local entered_hash

    saved_user=$(get_username "$name")
    saved_hash=$(get_password_hash "$name")
    entered_hash=$(hash_password "$password")

    [ "$username" = "$saved_user" ] &&
    [ "$entered_hash" = "$saved_hash" ]
}

delete_credentials() {

    local name="$1"

    rm -f "${CRED_DIR}/${name}.cred"
}

# ============================================================
#              INSTALL USER INSIDE CONTAINER
# ============================================================

setup_container_user() {

    local name="$1"
    local username="$2"
    local password="$3"

    docker exec "$name" bash -c "
        apt-get update -qq >/dev/null 2>&1 &&
        apt-get install -y -qq sudo >/dev/null 2>&1 || true

        if ! id '$username' >/dev/null 2>&1; then
            useradd -m -s /bin/bash '$username'
        fi

        echo '$username:$password' | chpasswd

        usermod -aG sudo '$username' 2>/dev/null || true

        echo '$username ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/kingcloud-$username
        chmod 440 /etc/sudoers.d/kingcloud-$username

        mkdir -p /home/$username
        chown -R $username:$username /home/$username
    " >/tmp/kc_user_setup.log 2>&1

    return $?
}

# ============================================================
#                    CONTAINER LIST
# ============================================================

get_containers() {

    mapfile -t CONTAINERS < <(
        docker ps -a \
            --filter "label=$LABEL" \
            --format '{{.Names}}' | sort
    )
}

container_status() {

    local name="$1"

    docker inspect \
        -f '{{.State.Status}}' \
        "$name" 2>/dev/null
}

is_suspended() {

    local name="$1"

    docker inspect \
        -f '{{index .Config.Labels "kingcloud.suspended"}}' \
        "$name" 2>/dev/null
}

# ============================================================
#                    DASHBOARD
# ============================================================

dashboard() {

    get_containers

    local total=${#CONTAINERS[@]}
    local running=0
    local stopped=0
    local suspended=0

    for name in "${CONTAINERS[@]}"; do

        local status
        status=$(container_status "$name")

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

# ============================================================
#                     MAIN SCREEN
# ============================================================

main_screen() {

    clear
    logo

    printf "  ${GRAY}Docker  •  Containers  •  Authentication  •  Control${RESET}\n"
    echo

    dashboard

    echo
    line
    echo

    printf "  ${PURPLE}${BOLD}[1]${RESET}   🚀 Create Container\n"
    printf "  ${CYAN}${BOLD}[2]${RESET}   📋 Container List\n"
    printf "  ${BLUE}${BOLD}[3]${RESET}   🖥  Open Console\n"
    printf "  ${GREEN}${BOLD}[4]${RESET}   ▶  Start Container\n"
    printf "  ${RED}${BOLD}[5]${RESET}   ■  Stop Container\n"
    printf "  ${PURPLE}${BOLD}[6]${RESET}   🔄 Restart Container\n"
    printf "  ${YELLOW}${BOLD}[7]${RESET}   🗑  Delete Container\n"
    printf "  ${YELLOW}${BOLD}[8]${RESET}   🔒 Suspend Container\n"
    printf "  ${GREEN}${BOLD}[9]${RESET}   🔓 Unsuspend Container\n"
    printf "  ${CYAN}${BOLD}[10]${RESET}  📜 Container Logs\n"
    printf "  ${BLUE}${BOLD}[11]${RESET}  📊 Resource Monitor\n"
    printf "  ${PURPLE}${BOLD}[12]${RESET}  ⚡ Bulk Controls\n"
    printf "  ${CYAN}${BOLD}[13]${RESET}  🔍 Inspect Container\n"
    printf "  ${LIGHT_PURPLE}${BOLD}[14]${RESET}  🧰 Execute Command\n"
    printf "  ${YELLOW}${BOLD}[15]${RESET}  ✨ About & Features\n"
    printf "  ${RED}${BOLD}[0]${RESET}   Exit\n"

    echo
    line
    printf "  ${GRAY}KINGCLOUD • Fast • Secure • Powerful${RESET}\n"
    echo
}

# ============================================================
#                 CREATE CONTAINER
# ============================================================

create_container() {

    clear
    logo

    printf "  ${PURPLE}${BOLD}CREATE KINGCLOUD CONTAINER${RESET}\n"
    line
    echo

    # ONLY NAME
    read -rp "  ${WHITE}Container name:${RESET} " NAME

    NAME=$(echo "$NAME" |
        tr '[:upper:]' '[:lower:]' |
        tr ' ' '-')

    if [ -z "$NAME" ]; then
        printf "  ${RED}✖ Name cannot be empty.${RESET}\n"
        pause_screen
        return
    fi

    if ! [[ "$NAME" =~ ^[a-z0-9][a-z0-9_.-]*$ ]]; then
        printf "  ${RED}✖ Invalid container name.${RESET}\n"
        printf "  ${GRAY}Use letters, numbers, -, _ or .${RESET}\n"
        pause_screen
        return
    fi

    if docker ps -a --format '{{.Names}}' |
        grep -Fxq "$NAME"; then

        printf "  ${RED}✖ Container '$NAME' already exists.${RESET}\n"
        pause_screen
        return
    fi

    echo

    # USERNAME
    read -rp "  ${WHITE}Username:${RESET} " USERNAME

    if [ -z "$USERNAME" ]; then
        printf "  ${RED}✖ Username cannot be empty.${RESET}\n"
        pause_screen
        return
    fi

    if ! [[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        printf "  ${RED}✖ Invalid username.${RESET}\n"
        pause_screen
        return
    fi

    # PASSWORD
    echo
    read -rsp "  ${WHITE}Password:${RESET} " PASSWORD
    echo

    if [ -z "$PASSWORD" ]; then
        printf "  ${RED}✖ Password cannot be empty.${RESET}\n"
        pause_screen
        return
    fi

    if [ "${#PASSWORD}" -lt 4 ]; then
        printf "  ${RED}✖ Password must be at least 4 characters.${RESET}\n"
        pause_screen
        return
    fi

    echo
    printf "  ${PURPLE}Preparing container...${RESET}\n"

    # Pull image if needed
    if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then

        docker pull "$IMAGE" >/tmp/kc_pull.log 2>&1 &

        local PID=$!
        local chars='|/-\'
        local i=0

        hide_cursor

        while kill -0 "$PID" 2>/dev/null; do
            printf "\r  ${PURPLE}${chars:i++%4:1}${RESET} Pulling Ubuntu 24.04..."
            sleep 0.1
        done

        wait "$PID"

        printf "\r\033[K"
        show_cursor
    fi

    echo
    printf "  ${PURPLE}Creating ${WHITE}$NAME${PURPLE}...${RESET}\n"

    docker run -dit \
        --name "$NAME" \
        --hostname "$NAME" \
        --label "$LABEL" \
        --label "kingcloud.suspended=false" \
        --restart unless-stopped \
        "$IMAGE" \
        /bin/bash >/tmp/kc_create.log 2>&1

    if [ $? -ne 0 ]; then

        printf "  ${RED}✖ Container creation failed.${RESET}\n"
        sed 's/^/  /' /tmp/kc_create.log

        pause_screen
        return
    fi

    echo
    printf "  ${CYAN}Setting up user account...${RESET}\n"

    setup_container_user "$NAME" "$USERNAME" "$PASSWORD"

    if [ $? -ne 0 ]; then

        printf "  ${RED}✖ User setup failed.${RESET}\n"
        printf "  ${GRAY}Container was created but credentials could not be configured.${RESET}\n"

        pause_screen
        return
    fi

    # Save only hash locally
    save_credentials "$NAME" "$USERNAME" "$PASSWORD"

    echo
    printf "  ${GREEN}╔══════════════════════════════════════════════╗${RESET}\n"
    printf "  ${GREEN}║       ✔ CONTAINER CREATED SUCCESSFULLY      ║${RESET}\n"
    printf "  ${GREEN}╚══════════════════════════════════════════════╝${RESET}\n"

    echo
    printf "  ${GRAY}Container:${RESET} ${WHITE}$NAME${RESET}\n"
    printf "  ${GRAY}Username :${RESET} ${WHITE}$USERNAME${RESET}\n"
    printf "  ${GRAY}Password :${RESET} ${GREEN}Configured${RESET}\n"
    printf "  ${GRAY}Memory   :${RESET} ${GREEN}Not requested${RESET}\n"
    printf "  ${GRAY}CPU      :${RESET} ${GREEN}Not requested${RESET}\n"

    echo
    printf "  ${GREEN}✔ Ready to use.${RESET}\n"

    pause_screen
}

# ============================================================
#                 SELECT CONTAINER
# ============================================================

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

        status=$(container_status "$name")

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

    if [ "$index" -lt 0 ] ||
       [ "$index" -ge "${#CONTAINERS[@]}" ]; then
        return 1
    fi

    SELECTED="${CONTAINERS[$index]}"

    return 0
}

# ============================================================
#                       LIST
# ============================================================

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

    printf "  ${GRAY}%-24s %-14s %-18s${RESET}\n" \
        "NAME" "STATUS" "IMAGE"

    line

    for name in "${CONTAINERS[@]}"; do

        local status
        status=$(container_status "$name")

        if [ "$(is_suspended "$name")" = "true" ]; then

            printf "  ${YELLOW}%-24s${RESET} ${YELLOW}%-14s${RESET} %-18s\n" \
                "$name" "suspended" "$IMAGE"

        elif [ "$status" = "running" ]; then

            printf "  ${GREEN}%-24s${RESET} ${GREEN}%-14s${RESET} %-18s\n" \
                "$name" "$status" "$IMAGE"

        else

            printf "  ${RED}%-24s${RESET} ${RED}%-14s${RESET} %-18s\n" \
                "$name" "$status" "$IMAGE"

        fi

    done

    echo
    pause_screen
}

# ============================================================
#                 START AUTHENTICATION
# ============================================================

authenticate_start() {

    local name="$1"

    echo
    printf "  ${PURPLE}${BOLD}KINGCLOUD AUTHENTICATION${RESET}\n"
    line
    echo

    printf "  ${GRAY}Starting:${RESET} ${WHITE}$name${RESET}\n\n"

    read -rp "  ${WHITE}Username:${RESET} " LOGIN_USER

    echo
    read -rsp "  ${WHITE}Password:${RESET} " LOGIN_PASS
    echo

    echo

    if verify_credentials "$name" "$LOGIN_USER" "$LOGIN_PASS"; then

        printf "  ${GREEN}✔ Authentication successful.${RESET}\n"
        return 0

    else

        printf "  ${RED}✖ Invalid username or password.${RESET}\n"
        return 1
    fi
}

# ============================================================
#                       START
# ============================================================

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

        printf "\n  ${YELLOW}✖ Container is suspended.${RESET}\n"
        printf "  ${GRAY}Use Unsuspend first.${RESET}\n"

        pause_screen
        return
    fi

    if [ "$(container_status "$SELECTED")" = "running" ]; then

        printf "\n  ${CYAN}Container is already running.${RESET}\n"
        pause_screen
        return
    fi

    # USERNAME + PASSWORD REQUIRED
    if ! authenticate_start "$SELECTED"; then
        pause_screen
        return
    fi

    echo
    printf "  ${PURPLE}Starting container...${RESET}\n"

    docker start "$SELECTED" >/tmp/kc_start.log 2>&1

    if [ $? -eq 0 ]; then

        printf "  ${GREEN}✔ $SELECTED started successfully.${RESET}\n"

    else

        printf "  ${RED}✖ Failed to start container.${RESET}\n"
        sed 's/^/  /' /tmp/kc_start.log

    fi

    pause_screen
}

# ============================================================
#                       STOP
# ============================================================

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

    docker stop "$SELECTED" >/tmp/kc_stop.log 2>&1

    if [ $? -eq 0 ]; then
        printf "  ${GREEN}✔ $SELECTED stopped.${RESET}\n"
    else
        printf "  ${RED}✖ Failed to stop $SELECTED.${RESET}\n"
    fi

    pause_screen
}

# ============================================================
#                     RESTART
# ============================================================

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
        pause_screen
        return
    fi

    if [ "$(container_status "$SELECTED")" != "running" ]; then

        printf "  ${YELLOW}Container is stopped.${RESET}\n"
        printf "  ${GRAY}Use Start to authenticate and start it.${RESET}\n"

        pause_screen
        return
    fi

    docker restart "$SELECTED" >/tmp/kc_restart.log 2>&1

    if [ $? -eq 0 ]; then
        printf "  ${GREEN}✔ $SELECTED restarted.${RESET}\n"
    else
        printf "  ${RED}✖ Restart failed.${RESET}\n"
    fi

    pause_screen
}

# ============================================================
#                      DELETE
# ============================================================

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

    printf "  ${RED}WARNING:${RESET} This permanently removes:\n"
    printf "  ${WHITE}$SELECTED${RESET}\n\n"

    read -rp "  Type DELETE to confirm: " CONFIRM

    if [ "$CONFIRM" = "DELETE" ]; then

        docker rm -f "$SELECTED" >/tmp/kc_delete.log 2>&1

        if [ $? -eq 0 ]; then

            delete_credentials "$SELECTED"

            printf "  ${GREEN}✔ $SELECTED deleted.${RESET}\n"

        else

            printf "  ${RED}✖ Delete failed.${RESET}\n"

        fi

    else

        printf "  ${YELLOW}Cancelled.${RESET}\n"

    fi

    pause_screen
}

# ============================================================
#                      SUSPEND
# ============================================================

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

    if [ "$(is_suspended "$SELECTED")" = "true" ]; then

        printf "  ${YELLOW}Already suspended.${RESET}\n"
        pause_screen
        return
    fi

    docker stop "$SELECTED" >/dev/null 2>&1

    docker update \
        --restart=no \
        "$SELECTED" >/dev/null 2>&1

    docker update \
        --label-add "kingcloud.suspended=true" \
        "$SELECTED" >/dev/null 2>&1

    printf "  ${YELLOW}🔒 $SELECTED suspended.${RESET}\n"

    pause_screen
}

# ============================================================
#                    UNSUSPEND
# ============================================================

unsuspend_container() {

    clear
    logo

    printf "  ${GREEN}${BOLD}UNSUSPEND CONTAINER${RESET}\n"
    line
    echo

    get_containers

    local found=0

    for name in "${CONTAINERS[@]}"; do

        if [ "$(is_suspended "$name")" = "true" ]; then

            found=1
            printf "  ${YELLOW}•${RESET} $name"

            echo
        fi

    done

    if [ "$found" -eq 0 ]; then

        printf "\n  ${GRAY}No suspended containers.${RESET}\n"
        pause_screen
        return
    fi

    echo

    read -rp "  Enter container name: " NAME

    if ! docker ps -a --format '{{.Names}}' |
        grep -Fxq "$NAME"; then

        printf "  ${RED}✖ Container not found.${RESET}\n"
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

    # Authentication before starting unsuspended container
    if ! authenticate_start "$NAME"; then
        pause_screen
        return
    fi

    docker start "$NAME" >/dev/null 2>&1

    if [ $? -eq 0 ]; then
        printf "  ${GREEN}✔ $NAME unsuspended and started.${RESET}\n"
    else
        printf "  ${RED}✖ Failed to start $NAME.${RESET}\n"
    fi

    pause_screen
}

# ============================================================
#                      CONSOLE
# ============================================================

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

    if [ "$(is_suspended "$SELECTED")" = "true" ]; then

        printf "  ${YELLOW}✖ Container is suspended.${RESET}\n"
        pause_screen
        return
    fi

    if [ "$(container_status "$SELECTED")" != "running" ]; then

        printf "  ${YELLOW}Container is stopped.${RESET}\n"
        printf "  ${GRAY}Start it first using Start Container.${RESET}\n"

        pause_screen
        return
    fi

    clear

    printf "${PURPLE}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════╗"
    printf "║                 👑 KINGCLOUD CONSOLE                    ║\n"
    printf "║                 %-36s ║\n" "$SELECTED"
    echo "╚══════════════════════════════════════════════════════════╝"
    printf "${RESET}\n"

    docker exec -it "$SELECTED" /bin/bash

    pause_screen
}

# ============================================================
#                       LOGS
# ============================================================

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
    printf "║                    📜 LOGS                              ║\n"
    printf "║                 %-36s ║\n" "$SELECTED"
    echo "╚══════════════════════════════════════════════════════════╝"
    printf "${RESET}\n"

    docker logs --tail 100 "$SELECTED" 2>&1

    pause_screen
}

# ============================================================
#                  RESOURCE MONITOR
# ============================================================

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

# ============================================================
#                    BULK CONTROLS
# ============================================================

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
        printf "  ${CYAN}[4]${RESET} 📋 Refresh\n"
        printf "  ${GRAY}[0]${RESET} ← Back\n"

        echo
        read -rp "  Select: " B

        case "$B" in

            1)

                get_containers

                for name in "${CONTAINERS[@]}"; do

                    if [ "$(is_suspended "$name")" != "true" ] &&
                       [ "$(container_status "$name")" != "running" ]; then

                        echo
                        printf "  ${WHITE}$name${RESET}\n"

                        if authenticate_start "$name"; then
                            docker start "$name" >/dev/null 2>&1
                            printf "  ${GREEN}✔ Started${RESET}\n"
                        else
                            printf "  ${RED}✖ Skipped${RESET}\n"
                        fi

                    fi

                done

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

                    if [ "$(is_suspended "$name")" != "true" ] &&
                       [ "$(container_status "$name")" = "running" ]; then

                        docker restart "$name" >/dev/null 2>&1

                    fi

                done

                printf "  ${GREEN}✔ Running containers restarted.${RESET}\n"

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

# ============================================================
#                       INSPECT
# ============================================================

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

    if command -v less >/dev/null 2>&1; then
        docker inspect "$SELECTED" | less -R
    else
        docker inspect "$SELECTED"
    fi

    pause_screen
}

# ============================================================
#                  EXECUTE COMMAND
# ============================================================

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

    if [ "$(container_status "$SELECTED")" != "running" ]; then

        printf "  ${YELLOW}Container is not running.${RESET}\n"

        read -rp "  Start it? [Y/n]: " A

        if [[ "$A" =~ ^[Nn]$ ]]; then
            pause_screen
            return
        fi

        if ! authenticate_start "$SELECTED"; then
            pause_screen
            return
        fi

        docker start "$SELECTED" >/dev/null 2>&1
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

# ============================================================
#                    ABOUT / FEATURES
# ============================================================

about_features() {

    clear
    logo

    printf "  ${LIGHT_PURPLE}${BOLD}KINGCLOUD • ABOUT & FEATURES${RESET}\n"
    line
    echo

    printf "  ${PURPLE}◆${RESET} Premium Terminal GUI\n"
    printf "  ${PURPLE}◆${RESET} Animated startup\n"
    printf "  ${PURPLE}◆${RESET} Username + Password authentication\n"
    printf "  ${PURPLE}◆${RESET} Create with only Name / Username / Password\n"
    printf "  ${PURPLE}◆${RESET} Start authentication\n"
    printf "  ${PURPLE}◆${RESET} Container console\n"
    printf "  ${PURPLE}◆${RESET} Start / Stop / Restart\n"
    printf "  ${PURPLE}◆${RESET} Suspend / Unsuspend\n"
    printf "  ${PURPLE}◆${RESET} Delete protection\n"
    printf "  ${PURPLE}◆${RESET} Container logs\n"
    printf "  ${PURPLE}◆${RESET} Resource monitor\n"
    printf "  ${PURPLE}◆${RESET} Docker inspect\n"
    printf "  ${PURPLE}◆${RESET} Execute commands\n"
    printf "  ${PURPLE}◆${RESET} Bulk controls\n"
    printf "  ${PURPLE}◆${RESET} Ubuntu 24.04\n"
    printf "  ${PURPLE}◆${RESET} No memory prompt\n"
    printf "  ${PURPLE}◆${RESET} No CPU prompt\n"

    echo
    line

    printf "  ${GRAY}KINGCLOUD Container Control Center${RESET}\n"

    pause_screen
}

# ============================================================
#                      MAIN LOOP
# ============================================================

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

            printf "\n"
            printf "  ${RED}✖ Invalid option.${RESET}\n"
            sleep 1
            ;;

    esac

done
