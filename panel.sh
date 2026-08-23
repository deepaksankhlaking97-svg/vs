#!/usr/bin/env bash

# ============================================================
#                 👑 KINGCLOUD PANEL HUB
#                  PufferPanel Manager
# ============================================================

set -u

# ---------------- COLORS ----------------
RESET="\033[0m"
BOLD="\033[1m"
DIM="\033[2m"

PURPLE="\033[38;5;141m"
CYAN="\033[38;5;51m"
GREEN="\033[38;5;82m"
RED="\033[38;5;196m"
YELLOW="\033[38;5;226m"
WHITE="\033[97m"
GRAY="\033[90m"

# ---------------- SETTINGS ----------------
LOG_FILE="/tmp/kingcloud-pufferpanel.log"

# ---------------- FUNCTIONS ----------------

clear_screen() {
    clear
}

line() {
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

pause_screen() {
    echo
    echo -e "${GRAY}Press Enter to continue...${RESET}"
    read -r
}

banner() {
    clear_screen

    echo
    echo -e "${PURPLE}${BOLD}"
    echo "     ██╗  ██╗██╗███╗   ██╗ ██████╗ ██████╗██╗      "
    echo "     ██║ ██╔╝██║████╗  ██║██╔════╝██╔════╝██║      "
    echo "     █████╔╝ ██║██╔██╗ ██║██║     ██║     ██║      "
    echo "     ██╔═██╗ ██║██║╚██╗██║██║     ██║     ██║      "
    echo "     ██║  ██╗██║██║ ╚████║╚██████╗╚██████╗███████╗ "
    echo "     ╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚═════╝╚══════╝ "
    echo -e "${RESET}"

    echo -e "${CYAN}${BOLD}                 PANEL MANAGEMENT HUB${RESET}"
    echo -e "${GRAY}                 PufferPanel Manager${RESET}"
    echo
    line
    echo
}

spinner() {
    local pid=$1
    local text="$2"
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0

    while kill -0 "$pid" 2>/dev/null; do
        printf "\r${CYAN}${spin:i++%${#spin}:1}${RESET} ${WHITE}%s${RESET}" "$text"
        sleep 0.1
    done

    printf "\r"
}

run_silent() {
    "$@" >>"$LOG_FILE" 2>&1 &
    local pid=$!

    spinner "$pid" "$2"

    wait "$pid"
    return $?
}

status_ok() {
    echo -e "${GREEN}✔${RESET} $1"
}

status_fail() {
    echo -e "${RED}✘${RESET} $1"
}

status_info() {
    echo -e "${CYAN}➜${RESET} $1"
}

# ============================================================
#                    INSTALL PUFFERPANEL
# ============================================================

install_pufferpanel() {

    banner

    echo -e "${CYAN}${BOLD}Installing PufferPanel${RESET}"
    echo

    # Root check
    if [[ $EUID -ne 0 ]]; then
        status_fail "Please run this script as root."
        echo
        echo -e "${YELLOW}Use:${RESET} sudo bash installer.sh"
        pause_screen
        return
    fi

    # Already installed check
    if command -v pufferpanel >/dev/null 2>&1; then
        status_info "PufferPanel is already installed."
        echo
        pause_screen
        return
    fi

    rm -f "$LOG_FILE"

    # Step 1
    if run_silent apt-get update -y "Updating package lists..."; then
        status_ok "Package lists updated"
    else
        status_fail "Failed to update packages"
        echo -e "${GRAY}See log: $LOG_FILE${RESET}"
        pause_screen
        return
    fi

    # Step 2
    if run_silent apt-get install -y sudo curl ca-certificates "Installing required packages..."; then
        status_ok "Required packages installed"
    else
        status_fail "Failed to install required packages"
        pause_screen
        return
    fi

    # Step 3
    if run_silent bash -c \
        'curl -fsSL "https://packagecloud.io/install/repositories/pufferpanel/pufferpanel/script.deb.sh?any=true" | bash' \
        "Connecting to PufferPanel repository..."; then

        status_ok "PufferPanel repository added"
    else
        status_fail "Repository setup failed"
        echo -e "${GRAY}See log: $LOG_FILE${RESET}"
        pause_screen
        return
    fi

    # Step 4
    if run_silent apt-get update -y "Refreshing PufferPanel packages..."; then
        status_ok "Repository refreshed"
    else
        status_fail "Repository refresh failed"
        pause_screen
        return
    fi

    # Step 5
    if run_silent apt-get install -y pufferpanel "Installing PufferPanel..."; then
        status_ok "PufferPanel installed"
    else
        status_fail "PufferPanel installation failed"
        echo -e "${GRAY}See log: $LOG_FILE${RESET}"
        pause_screen
        return
    fi

    echo
    line
    echo
    echo -e "${GREEN}${BOLD}✔ PufferPanel installation completed${RESET}"
    echo

    # Admin user
    echo -e "${YELLOW}${BOLD}Admin Setup${RESET}"
    echo
    echo -e "${WHITE}Create your PufferPanel admin account.${RESET}"
    echo

    # This command is intentionally hidden.
    if pufferpanel user add; then
        status_ok "Admin user created"
    else
        status_fail "Admin user creation failed"
    fi

    echo
    echo -e "${CYAN}Starting PufferPanel service...${RESET}"

    if systemctl enable --now pufferpanel >/dev/null 2>&1; then
        status_ok "PufferPanel service started"
    else
        status_fail "Could not start PufferPanel service"
    fi

    echo
    echo -e "${GREEN}${BOLD}PufferPanel is ready!${RESET}"
    echo
    echo -e "${GRAY}Panel service: ${WHITE}pufferpanel${RESET}"
    echo -e "${GRAY}The installation commands were hidden from the screen.${RESET}"

    pause_screen
}

# ============================================================
#                       START
# ============================================================

start_pufferpanel() {

    banner

    echo -e "${CYAN}${BOLD}Starting PufferPanel${RESET}"
    echo

    if ! command -v pufferpanel >/dev/null 2>&1; then
        status_fail "PufferPanel is not installed."
        pause_screen
        return
    fi

    if systemctl enable --now pufferpanel >/dev/null 2>&1; then
        status_ok "PufferPanel started successfully"
    else
        status_fail "Failed to start PufferPanel"
        echo
        echo -e "${GRAY}Check service logs with:${RESET}"
        echo -e "${WHITE}journalctl -u pufferpanel${RESET}"
    fi

    pause_screen
}

# ============================================================
#                       RESTART
# ============================================================

restart_pufferpanel() {

    banner

    echo -e "${YELLOW}${BOLD}Restarting PufferPanel${RESET}"
    echo

    if ! command -v pufferpanel >/dev/null 2>&1; then
        status_fail "PufferPanel is not installed."
        pause_screen
        return
    fi

    if systemctl restart pufferpanel >/dev/null 2>&1; then
        status_ok "PufferPanel restarted successfully"
    else
        status_fail "Failed to restart PufferPanel"
    fi

    pause_screen
}

# ============================================================
#                       UNINSTALL
# ============================================================

uninstall_pufferpanel() {

    banner

    echo -e "${RED}${BOLD}Uninstall PufferPanel${RESET}"
    echo
    echo -e "${YELLOW}WARNING:${RESET}"
    echo "This will remove PufferPanel, its service, configuration"
    echo "and local PufferPanel data."
    echo

    read -rp "Type YES to continue: " confirm

    if [[ "$confirm" != "YES" ]]; then
        echo
        status_info "Uninstall cancelled."
        pause_screen
        return
    fi

    echo
    rm -f "$LOG_FILE"

    # Stop service
    if systemctl stop pufferpanel >/dev/null 2>&1; then
        status_ok "PufferPanel service stopped"
    else
        status_info "PufferPanel service was not running"
    fi

    # Disable service
    systemctl disable pufferpanel >/dev/null 2>&1 || true
    status_ok "PufferPanel service disabled"

    # Remove package
    if apt-get purge -y pufferpanel >/dev/null 2>&1; then
        status_ok "PufferPanel package removed"
    else
        status_info "PufferPanel package was already removed"
    fi

    # Remove package repository
    rm -f /etc/apt/sources.list.d/pufferpanel.list
    rm -f /etc/apt/sources.list.d/pufferpanel*.list
    status_ok "PufferPanel repository removed"

    # Remove configuration
    rm -rf /etc/pufferpanel
    status_ok "Configuration removed"

    # Remove local data
    rm -rf /var/lib/pufferpanel
    status_ok "PufferPanel data removed"

    # Remove logs
    rm -rf /var/log/pufferpanel
    status_ok "PufferPanel logs removed"

    # Refresh apt
    apt-get update -y >/dev/null 2>&1 || true

    echo
    line
    echo
    echo -e "${GREEN}${BOLD}✔ PufferPanel completely uninstalled${RESET}"
    echo

    pause_screen
}

# ============================================================
#                    PUFFERPANEL MENU
# ============================================================

puffer_menu() {

    while true; do

        banner

        echo -e "${WHITE}${BOLD}PufferPanel${RESET}"
        echo
        echo -e "${GREEN}1.${RESET} Install"
        echo -e "${CYAN}2.${RESET} Start"
        echo -e "${YELLOW}3.${RESET} Restart"
        echo -e "${RED}4.${RESET} Uninstall"
        echo -e "${GRAY}5.${RESET} Back"
        echo

        line
        echo

        read -rp "Select option: " choice

        case "$choice" in
            1)
                install_pufferpanel
                ;;
            2)
                start_pufferpanel
                ;;
            3)
                restart_pufferpanel
                ;;
            4)
                uninstall_pufferpanel
                ;;
            5)
                return
                ;;
            *)
                echo
                status_fail "Invalid option"
                sleep 1
                ;;
        esac

    done
}

# ============================================================
#                       MAIN MENU
# ============================================================

main_menu() {

    while true; do

        banner

        echo -e "${WHITE}${BOLD}Select Panel${RESET}"
        echo
        echo -e "${PURPLE}1.${RESET} PufferPanel"
        echo -e "${RED}2.${RESET} Exit"
        echo

        line
        echo

        read -rp "Select option: " choice

        case "$choice" in
            1)
                puffer_menu
                ;;
            2)
                clear
                echo
                echo -e "${PURPLE}${BOLD}👑 KINGCLOUD${RESET}"
                echo -e "${GRAY}Panel Manager closed.${RESET}"
                echo
                exit 0
                ;;
            *)
                echo
                status_fail "Invalid option"
                sleep 1
                ;;
        esac

    done
}

# ============================================================
#                         START
# ============================================================

main_menu
