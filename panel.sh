#!/usr/bin/env bash

# ============================================================
#                    👑 KING PANEL HUB
#                    Premium Panel Manager
# ============================================================

set -u

# ---------------- COLORS ----------------
RESET="\033[0m"
BOLD="\033[1m"

PURPLE="\033[38;5;141m"
CYAN="\033[38;5;51m"
GREEN="\033[38;5;82m"
RED="\033[38;5;196m"
YELLOW="\033[38;5;226m"
WHITE="\033[97m"
GRAY="\033[90m"

LOG_FILE="/tmp/king-panel.log"

# ============================================================
#                       BASIC FUNCTIONS
# ============================================================

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

ok() {
    echo -e "${GREEN}✔${RESET} $1"
}

fail() {
    echo -e "${RED}✘${RESET} $1"
}

info() {
    echo -e "${CYAN}➜${RESET} $1"
}

warning() {
    echo -e "${YELLOW}⚠${RESET} $1"
}

# ============================================================
#                         BANNER
# ============================================================

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

    echo -e "${CYAN}${BOLD}                    KING PANEL HUB${RESET}"
    echo -e "${GRAY}                    Premium Manager${RESET}"

    echo
    line
    echo
}

# ============================================================
#                    ROOT CHECK
# ============================================================

check_root() {

    if [[ $EUID -ne 0 ]]; then
        fail "Root permission required."
        echo
        echo -e "${GRAY}Run this script using:${RESET}"
        echo -e "${WHITE}sudo bash script.sh${RESET}"
        return 1
    fi

    return 0
}

# ============================================================
#                 WAIT FOR APT LOCK
# ============================================================

wait_for_apt() {

    local tries=0

    while fuser \
        /var/lib/dpkg/lock-frontend \
        /var/lib/dpkg/lock \
        /var/cache/apt/archives/lock \
        >/dev/null 2>&1
    do

        tries=$((tries + 1))

        if [[ $tries -gt 60 ]]; then
            return 1
        fi

        printf "\r${CYAN}⠋${RESET} Waiting for package manager..."
        sleep 2

    done

    printf "\r\033[K"

    return 0
}

# ============================================================
#                 FIX DPKG STATE
# ============================================================

fix_dpkg() {

    dpkg --configure -a >>"$LOG_FILE" 2>&1 || true

    apt-get -f install -y >>"$LOG_FILE" 2>&1 || true
}

# ============================================================
#                  APT UPDATE WITH RETRY
# ============================================================

update_packages() {

    wait_for_apt || return 1

    local attempt=1

    while [[ $attempt -le 3 ]]; do

        if apt-get update \
            -o Acquire::Retries=3 \
            -o Dpkg::Use-Pty=0 \
            >>"$LOG_FILE" 2>&1
        then
            return 0
        fi

        fix_dpkg

        sleep 2

        attempt=$((attempt + 1))
    done

    return 1
}

# ============================================================
#                    SILENT COMMAND
# ============================================================

run_quiet() {

    local message="$1"
    shift

    echo -ne "${CYAN}⠋${RESET} ${WHITE}${message}${RESET}"

    "$@" >>"$LOG_FILE" 2>&1 &
    local pid=$!

    local dots=0

    while kill -0 "$pid" 2>/dev/null; do

        case $((dots % 4)) in
            0) symbol="⠋" ;;
            1) symbol="⠙" ;;
            2) symbol="⠹" ;;
            3) symbol="⠸" ;;
        esac

        printf "\r${CYAN}${symbol}${RESET} ${WHITE}${message}${RESET}"
        dots=$((dots + 1))

        sleep 0.12
    done

    wait "$pid"
    local result=$?

    if [[ $result -eq 0 ]]; then
        printf "\r\033[K"
        ok "$message"
    else
        printf "\r\033[K"
        fail "$message"

        echo -e "${GRAY}Detailed error: ${LOG_FILE}${RESET}"
    fi

    return $result
}

# ============================================================
#                    INSTALL PANEL
# ============================================================

install_panel() {

    banner

    echo -e "${CYAN}${BOLD}Installing Panel${RESET}"
    echo

    if ! check_root; then
        pause_screen
        return
    fi

    rm -f "$LOG_FILE"
    touch "$LOG_FILE"

    # --------------------------------------------------------
    # Check existing installation
    # --------------------------------------------------------

    if command -v pufferpanel >/dev/null 2>&1; then

        warning "Panel is already installed."
        echo

        if systemctl is-active --quiet pufferpanel; then
            ok "Panel service is already running."
        else
            info "Panel is installed but currently stopped."
        fi

        pause_screen
        return
    fi

    # --------------------------------------------------------
    # Prepare package manager
    # --------------------------------------------------------

    info "Preparing system..."
    fix_dpkg

    # --------------------------------------------------------
    # Update packages
    # --------------------------------------------------------

    if update_packages; then
        ok "Package lists updated"
    else
        fail "Unable to update package lists"

        echo
        echo -e "${YELLOW}Possible causes:${RESET}"
        echo "• Another apt process is running"
        echo "• Repository/network problem"
        echo "• Broken dpkg state"
        echo
        echo -e "${GRAY}Log: ${LOG_FILE}${RESET}"

        pause_screen
        return
    fi

    # --------------------------------------------------------
    # Install dependencies
    # --------------------------------------------------------

    if run_quiet \
        "Installing required packages..." \
        apt-get install -y \
        curl \
        ca-certificates \
        sudo
    then
        :
    else
        pause_screen
        return
    fi

    # --------------------------------------------------------
    # Add repository
    # --------------------------------------------------------

    echo
    if run_quiet \
        "Connecting to panel repository..." \
        bash -c \
        'curl -fsSL "https://packagecloud.io/install/repositories/pufferpanel/pufferpanel/script.deb.sh?any=true" | bash'
    then
        :
    else
        pause_screen
        return
    fi

    # --------------------------------------------------------
    # Refresh repository
    # --------------------------------------------------------

    if update_packages; then
        ok "Repository information updated"
    else
        fail "Repository refresh failed"
        pause_screen
        return
    fi

    # --------------------------------------------------------
    # Install
    # --------------------------------------------------------

    if run_quiet \
        "Installing panel..." \
        apt-get install -y pufferpanel
    then
        :
    else
        pause_screen
        return
    fi

    echo
    line
    echo

    echo -e "${GREEN}${BOLD}✔ Panel installation completed${RESET}"
    echo

    # --------------------------------------------------------
    # Admin User
    # --------------------------------------------------------

    echo -e "${CYAN}${BOLD}Admin Account Setup${RESET}"
    echo
    echo -e "${GRAY}Create your administrator account below.${RESET}"
    echo

    # Command hidden; interactive input remains visible.
    if pufferpanel user add; then
        echo
        ok "Admin account created"
    else
        echo
        fail "Admin account creation failed"
    fi

    echo

    # --------------------------------------------------------
    # Start service
    # --------------------------------------------------------

    if systemctl enable --now pufferpanel >/dev/null 2>&1; then
        ok "Panel service started"
    else
        fail "Panel service could not be started"
    fi

    echo
    line
    echo

    echo -e "${GREEN}${BOLD}👑 KING PANEL IS READY${RESET}"
    echo
    echo -e "${GRAY}Panel service has been enabled and started.${RESET}"

    pause_screen
}

# ============================================================
#                         START
# ============================================================

start_panel() {

    banner

    echo -e "${CYAN}${BOLD}Starting Panel${RESET}"
    echo

    if ! command -v pufferpanel >/dev/null 2>&1; then
        fail "Panel is not installed."
        pause_screen
        return
    fi

    if systemctl enable --now pufferpanel >/dev/null 2>&1; then
        ok "Panel started successfully"
    else
        fail "Failed to start panel"
    fi

    pause_screen
}

# ============================================================
#                        RESTART
# ============================================================

restart_panel() {

    banner

    echo -e "${YELLOW}${BOLD}Restarting Panel${RESET}"
    echo

    if ! command -v pufferpanel >/dev/null 2>&1; then
        fail "Panel is not installed."
        pause_screen
        return
    fi

    if systemctl restart pufferpanel >/dev/null 2>&1; then
        ok "Panel restarted successfully"
    else
        fail "Failed to restart panel"
    fi

    pause_screen
}

# ============================================================
#                       UNINSTALL
# ============================================================

uninstall_panel() {

    banner

    echo -e "${RED}${BOLD}Complete Panel Uninstall${RESET}"
    echo

    if ! command -v pufferpanel >/dev/null 2>&1 &&
       [[ ! -d /etc/pufferpanel ]] &&
       [[ ! -d /var/lib/pufferpanel ]]
    then
        info "Panel is not installed."
        pause_screen
        return
    fi

    echo -e "${YELLOW}WARNING:${RESET}"
    echo
    echo "This will remove:"
    echo "• Panel package"
    echo "• Panel service"
    echo "• Panel configuration"
    echo "• Panel local data"
    echo "• Panel logs"
    echo "• Panel repository"
    echo

    read -rp "Type YES to completely uninstall: " confirm

    if [[ "$confirm" != "YES" ]]; then
        echo
        info "Uninstall cancelled."
        pause_screen
        return
    fi

    echo

    # Stop
    if systemctl stop pufferpanel >/dev/null 2>&1; then
        ok "Panel stopped"
    else
        info "Panel was not running"
    fi

    # Disable
    systemctl disable pufferpanel >/dev/null 2>&1 || true
    ok "Panel service disabled"

    # Remove package
    if apt-get purge -y pufferpanel >/dev/null 2>&1; then
        ok "Panel package removed"
    else
        info "Panel package already removed"
    fi

    # Remove repository
    rm -f /etc/apt/sources.list.d/pufferpanel.list
    rm -f /etc/apt/sources.list.d/pufferpanel*.list

    ok "Panel repository removed"

    # Remove config
    rm -rf /etc/pufferpanel
    ok "Panel configuration removed"

    # Remove data
    rm -rf /var/lib/pufferpanel
    ok "Panel data removed"

    # Remove logs
    rm -rf /var/log/pufferpanel
    ok "Panel logs removed"

    # Remove systemd leftovers
    rm -f /etc/systemd/system/pufferpanel.service
    systemctl daemon-reload >/dev/null 2>&1 || true

    ok "System service cleaned"

    # Refresh apt
    apt-get update >/dev/null 2>&1 || true

    echo
    line
    echo

    echo -e "${GREEN}${BOLD}✔ KING PANEL COMPLETELY UNINSTALLED${RESET}"
    echo

    pause_screen
}

# ============================================================
#                    PANEL SUB MENU
# ============================================================

panel_menu() {

    while true; do

        banner

        echo -e "${WHITE}${BOLD}KING PANEL${RESET}"
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
                install_panel
                ;;

            2)
                start_panel
                ;;

            3)
                restart_panel
                ;;

            4)
                uninstall_panel
                ;;

            5)
                return
                ;;

            *)
                fail "Invalid option"
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

        echo -e "${PURPLE}1.${RESET} King Panel"
        echo -e "${RED}2.${RESET} Exit"

        echo
        line
        echo

        read -rp "Select option: " choice

        case "$choice" in

            1)
                panel_menu
                ;;

            2)
                clear
                echo
                echo -e "${PURPLE}${BOLD}👑 KING${RESET}"
                echo -e "${GRAY}Panel Manager closed.${RESET}"
                echo
                exit 0
                ;;

            *)
                fail "Invalid option"
                sleep 1
                ;;

        esac

    done
}

# ============================================================
#                         START
# ============================================================

main_menu
