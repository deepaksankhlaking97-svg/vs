#!/usr/bin/env bash

set -u

# ============================================================
#                 👑 KINGCLOUD INSTALLER HUB
#                   Premium VPS Installer
# ============================================================

RESET="\033[0m"
BOLD="\033[1m"
DIM="\033[2m"

PURPLE="\033[38;5;141m"
CYAN="\033[38;5;51m"
BLUE="\033[38;5;75m"
GREEN="\033[38;5;82m"
YELLOW="\033[38;5;220m"
RED="\033[38;5;203m"
WHITE="\033[38;5;255m"
GRAY="\033[38;5;245m"

# ============================================================
# TERMINAL
# ============================================================

clear_screen() {
    printf '\033[2J\033[H'
}

hide_cursor() {
    printf '\033[?25l'
}

show_cursor() {
    printf '\033[?25h'
}

cleanup() {
    show_cursor
}

trap cleanup EXIT
trap 'exit 0' INT TERM

# ============================================================
# HELPERS
# ============================================================

line() {
    printf '%b\n' "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

center() {
    local text="$1"
    local width
    local clean
    local len
    local pad

    width=$(tput cols 2>/dev/null || echo 80)

    clean=$(printf '%b' "$text" | sed $'s/\033\\[[0-9;]*m//g')
    len=${#clean}

    pad=$(( (width - len) / 2 ))

    if [ "$pad" -lt 0 ]; then
        pad=0
    fi

    printf '%*s%b\n' "$pad" "" "$text"
}

pause_screen() {
    echo
    printf '%b' "${GRAY}Press ENTER to return to KINGCLOUD menu...${RESET}"
    read -r
}

spinner() {
    local text="$1"
    local duration="${2:-2}"

    local frames=(
        "⠋"
        "⠙"
        "⠹"
        "⠸"
        "⠼"
        "⠴"
        "⠦"
        "⠧"
        "⠇"
        "⠏"
    )

    local end
    local i=0

    end=$((SECONDS + duration))

    while [ "$SECONDS" -lt "$end" ]; do
        printf '\r%b' \
            "${CYAN}${frames[$((i % ${#frames[@]}))]}${RESET} ${WHITE}${text}${RESET}"
        sleep 0.08
        i=$((i + 1))
    done

    printf '\r%b\n' "${GREEN}✔${RESET} ${WHITE}${text}${RESET}"
}

progress() {
    local title="$1"
    local width=40
    local i
    local filled
    local empty

    for i in $(seq 0 2 100); do
        filled=$((i * width / 100))
        empty=$((width - filled))

        printf '\r%b' "${CYAN}${title}${RESET} ["

        if [ "$filled" -gt 0 ]; then
            printf '%*s' "$filled" '' | tr ' ' '█'
        fi

        if [ "$empty" -gt 0 ]; then
            printf '%b' "${GRAY}"
            printf '%*s' "$empty" '' | tr ' ' '░'
            printf '%b' "${RESET}"
        fi

        printf ' %3d%%' "$i"

        sleep 0.015
    done

    echo
}

# ============================================================
# VM LAUNCH ANIMATION
# ============================================================

vm_animation() {
    clear_screen
    hide_cursor

    echo

    center "${PURPLE}${BOLD}╔══════════════════════════════════════════════╗${RESET}"
    center "${PURPLE}${BOLD}║              👑 KINGCLOUD                   ║${RESET}"
    center "${CYAN}${BOLD}║              VM MANAGER                     ║${RESET}"
    center "${PURPLE}${BOLD}╚══════════════════════════════════════════════╝${RESET}"

    echo
    line
    echo

    center "${WHITE}${BOLD}VIRTUAL MACHINE CONTROL CENTER${RESET}"
    center "${GRAY}Preparing secure VM management environment${RESET}"

    echo
    echo

    spinner "Initializing VM subsystem" 1
    spinner "Checking virtualization environment" 1
    spinner "Loading VM management module" 1
    spinner "Connecting to KINGCLOUD VM service" 1

    echo

    progress "Launching VM Manager"

    echo

    printf ' %b\n' "${CYAN}VM Engine${RESET}    ${GREEN}● READY${RESET}"
    printf ' %b\n' "${CYAN}Hypervisor${RESET}  ${GREEN}● READY${RESET}"
    printf ' %b\n' "${CYAN}Network${RESET}     ${GREEN}● READY${RESET}"
    printf ' %b\n' "${CYAN}Storage${RESET}     ${GREEN}● READY${RESET}"

    echo
    echo

    center "${GREEN}${BOLD}✔ VM MANAGER READY${RESET}"

    sleep 1

    clear_screen
    hide_cursor

    echo

    center "${PURPLE}${BOLD}╔══════════════════════════════════════════════╗${RESET}"
    center "${PURPLE}${BOLD}║             👑 KINGCLOUD VM                 ║${RESET}"
    center "${PURPLE}${BOLD}║             CONTROL PANEL                   ║${RESET}"
    center "${PURPLE}${BOLD}╚══════════════════════════════════════════════╝${RESET}"

    echo
    line
    echo

    spinner "Downloading latest VM module" 1
    spinner "Starting VM control interface" 1

    echo

    printf '%b\n' \
        "${GREEN}${BOLD}✔${RESET} ${WHITE}Opening KINGCLOUD VM Manager...${RESET}"

    sleep 1
}

# ============================================================
# OPEN VM MANAGER
# ============================================================

open_vm_manager() {

    vm_animation

    echo
    line
    echo

    # VM manager remote installer
    bash <(curl -fsSL \
        "https://raw.githubusercontent.com/deepaksankhlaking97-svg/vs/refs/heads/main/kingcloud-vm.sh")

    echo
    printf '%b\n' "${GREEN}${BOLD}✔ VM Manager closed successfully.${RESET}"

    sleep 1
}

# ============================================================
# LOGO
# ============================================================

logo() {
    echo

    center "${PURPLE}${BOLD}██╗  ██╗██╗███╗   ██╗ ██████╗${RESET}"
    center "${PURPLE}${BOLD}██║ ██╔╝██║████╗  ██║██╔════╝${RESET}"
    center "${CYAN}${BOLD}█████╔╝ ██║██╔██╗ ██║██║  ███╗${RESET}"
    center "${CYAN}${BOLD}██╔═██╗ ██║██║╚██╗██║██║   ██║${RESET}"
    center "${PURPLE}${BOLD}██║  ██╗██║██║ ╚████║╚██████╔╝${RESET}"
    center "${PURPLE}${BOLD}╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝ ╚═════╝${RESET}"

    echo

    center "${WHITE}${BOLD}C L O U D   I N S T A L L E R   H U B${RESET}"
    center "${GRAY}Premium VPS Tools • Fast • Simple • Reliable${RESET}"

    echo
}

# ============================================================
# STARTUP
# ============================================================

startup() {
    clear_screen
    hide_cursor

    echo

    center "${PURPLE}${BOLD}╔══════════════════════════════════════════════╗${RESET}"
    center "${PURPLE}${BOLD}║              👑 KINGCLOUD                   ║${RESET}"
    center "${PURPLE}${BOLD}║           VPS INSTALLER HUB                 ║${RESET}"
    center "${PURPLE}${BOLD}╚══════════════════════════════════════════════╝${RESET}"

    echo

    center "${GRAY}Initializing cloud environment...${RESET}"

    echo

    spinner "Connecting to KINGCLOUD" 1
    spinner "Detecting VPS environment" 1
    spinner "Loading installer modules" 1
    spinner "Preparing control interface" 1

    echo

    printf ' %b\n' "${CYAN}System${RESET}   ${GREEN}● ONLINE${RESET}"
    printf ' %b\n' "${CYAN}Network${RESET}  ${GREEN}● READY${RESET}"
    printf ' %b\n' "${CYAN}Modules${RESET}  ${GREEN}● LOADED${RESET}"
    printf ' %b\n' "${CYAN}VPS${RESET}      ${GREEN}● DETECTED${RESET}"

    echo

    progress "Starting KINGCLOUD"

    echo

    center "${GREEN}${BOLD}✔ KINGCLOUD READY${RESET}"

    sleep 1
}

# ============================================================
# HEADER
# ============================================================

header() {
    clear_screen

    echo

    center "${PURPLE}${BOLD}👑 KINGCLOUD INSTALLER HUB${RESET}"
    center "${GRAY}────────────────────────────────────────────${RESET}"

    echo

    printf ' %b' "${CYAN}Server:${RESET} ${WHITE}KINGCLOUD${RESET}"
    printf '    %b' "${CYAN}Mode:${RESET} ${GREEN}ONLINE${RESET}"
    printf '    %b\n' "${CYAN}Version:${RESET} ${WHITE}2.0${RESET}"

    echo

    line
    echo
}

# ============================================================
# VS CODE
# ============================================================

install_vscode() {
    clear_screen
    hide_cursor

    logo

    echo

    center "${CYAN}${BOLD}VS CODE INSTALLER${RESET}"

    echo
    line
    echo

    center "${WHITE}Visual Studio Code${RESET}"
    center "${GRAY}Automatic installation for your VPS${RESET}"

    echo

    printf ' %b\n' "${CYAN}Package:${RESET} ${WHITE}VS Code${RESET}"
    printf ' %b\n' "${CYAN}Target:${RESET}  ${WHITE}Current VPS${RESET}"
    printf ' %b\n' "${CYAN}Mode:${RESET}    ${GREEN}Automatic${RESET}"

    echo
    line
    echo

    read -r -p \
        "$(printf '%b' "${YELLOW}Start VS Code installation? [Y/n]: ${RESET}")" answer

    answer=${answer:-Y}

    if [[ "$answer" =~ ^[Yy]$ ]]; then

        clear_screen
        hide_cursor

        logo

        echo

        center "${CYAN}${BOLD}VS CODE INSTALLATION${RESET}"

        echo
        line
        echo

        spinner "Connecting to installer" 1
        spinner "Preparing VS Code installation" 1

        echo

        printf '%b\n' \
            "${CYAN}▶${RESET} ${WHITE}Starting installation...${RESET}"

        echo

        if bash <(curl -fsSL \
            "https://raw.githubusercontent.com/deepaksankhlaking97-svg/vs/refs/heads/main/vs.sh")
        then
            echo
            printf '%b\n' \
                "${GREEN}${BOLD}✔ VS Code installation completed.${RESET}"
        else
            echo
            printf '%b\n' \
                "${RED}${BOLD}✖ VS Code installation failed.${RESET}"
        fi

    else

        echo
        printf '%b\n' "${YELLOW}Installation cancelled.${RESET}"

    fi

    pause_screen
}

# ============================================================
# CONTAINER
# ============================================================

install_container() {
    clear_screen
    hide_cursor

    logo

    echo

    center "${CYAN}${BOLD}CONTAINER INSTALLER${RESET}"

    echo
    line
    echo

    center "${WHITE}KINGCLOUD Container Environment${RESET}"
    center "${GRAY}Automatic installation for your VPS${RESET}"

    echo

    printf ' %b\n' "${CYAN}Package:${RESET} ${WHITE}Container Environment${RESET}"
    printf ' %b\n' "${CYAN}Target:${RESET}  ${WHITE}Current VPS${RESET}"
    printf ' %b\n' "${CYAN}Mode:${RESET}    ${GREEN}Automatic${RESET}"

    echo
    line
    echo

    read -r -p \
        "$(printf '%b' "${YELLOW}Start Container installation? [Y/n]: ${RESET}")" answer

    answer=${answer:-Y}

    if [[ "$answer" =~ ^[Yy]$ ]]; then

        clear_screen
        hide_cursor

        logo

        echo

        center "${CYAN}${BOLD}CONTAINER INSTALLATION${RESET}"

        echo
        line
        echo

        spinner "Connecting to container installer" 1
        spinner "Preparing container environment" 1

        echo

        printf '%b\n' \
            "${CYAN}▶${RESET} ${WHITE}Starting installation...${RESET}"

        echo

        if bash <(curl -fsSL \
            "https://raw.githubusercontent.com/deepaksankhlaking97-svg/vs/refs/heads/main/container.sh")
        then
            echo
            printf '%b\n' \
                "${GREEN}${BOLD}✔ Container installation completed.${RESET}"
        else
            echo
            printf '%b\n' \
                "${RED}${BOLD}✖ Container installation failed.${RESET}"
        fi

    else

        echo
        printf '%b\n' "${YELLOW}Installation cancelled.${RESET}"

    fi

    pause_screen
}

# ============================================================
# ABOUT
# ============================================================

about() {
    clear_screen
    hide_cursor

    echo

    center "${PURPLE}${BOLD}👑 ABOUT KINGCLOUD${RESET}"

    echo
    line
    echo

    center "${WHITE}${BOLD}KINGCLOUD INSTALLER HUB${RESET}"

    echo

    center "${GRAY}Premium terminal interface for KINGCLOUD VPS tools.${RESET}"
    center "${GRAY}Fast installation • Clean interface • Easy navigation${RESET}"

    echo

    printf ' %b\n' "${CYAN}Features:${RESET}"

    echo " ${GREEN}✔${RESET} Premium startup animation"
    echo " ${GREEN}✔${RESET} VPS detection"
    echo " ${GREEN}✔${RESET} VS Code installer"
    echo " ${GREEN}✔${RESET} Container installer"
    echo " ${GREEN}✔${RESET} VM Manager"
    echo " ${GREEN}✔${RESET} VM launch animation"
    echo " ${GREEN}✔${RESET} Clean terminal GUI"
    echo " ${GREEN}✔${RESET} Simple navigation"

    echo

    center "${PURPLE}${BOLD}KINGCLOUD${RESET} ${GRAY}— Build. Deploy. Manage.${RESET}"

    pause_screen
}

# ============================================================
# MENU
# ============================================================

menu() {

    while true; do

        header

        printf ' %b\n\n' "${PURPLE}${BOLD}MAIN MENU${RESET}"

        printf ' %b\n' \
            "${CYAN}${BOLD}[1]${RESET}  ${WHITE}VS Code Installer${RESET}"
        printf '      %b\n\n' \
            "${GRAY}Install VS Code on your VPS${RESET}"

        printf ' %b\n' \
            "${CYAN}${BOLD}[2]${RESET}  ${WHITE}Container Installer${RESET}"
        printf '      %b\n\n' \
            "${GRAY}Install container environment on your VPS${RESET}"

        printf ' %b\n' \
            "${PURPLE}${BOLD}[3]${RESET}  ${WHITE}Create / Manage VMs${RESET}"
        printf '      %b\n\n' \
            "${GRAY}Open KINGCLOUD Virtual Machine Manager${RESET}"

        printf ' %b\n' \
            "${BLUE}${BOLD}[4]${RESET}  ${WHITE}About KINGCLOUD${RESET}"
        printf '      %b\n\n' \
            "${GRAY}Information about KINGCLOUD${RESET}"

        printf ' %b\n\n' \
            "${RED}${BOLD}[0]${RESET}  ${WHITE}Exit${RESET}"

        line

        echo

        read -r -p \
            "$(printf '%b' " ${PURPLE}${BOLD}KINGCLOUD ❯ ${RESET}")" choice

        case "$choice" in

            1)
                install_vscode
                ;;

            2)
                install_container
                ;;

            3)
                open_vm_manager
                ;;

            4)
                about
                ;;

            0)
                clear_screen
                show_cursor

                echo
                center "${PURPLE}${BOLD}👑 Thank you for using KINGCLOUD!${RESET}"
                echo

                exit 0
                ;;

            *)
                printf '\n%b\n' \
                    " ${RED}✖ Invalid option. Please choose 0-4.${RESET}"
                sleep 1
                ;;

        esac

    done
}

# ============================================================
# START
# ============================================================

startup
menu
