#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT="/var/www/pterodactyl"
LOG="/var/log/pterodactyl-manager.log"

# ============================================================
# COLORS
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
NC='\033[0m'

BOLD='\033[1m'

# ============================================================
# LOGGING
# ============================================================

mkdir -p "$(dirname "$LOG")"
touch "$LOG"

# ============================================================
# ROOT CHECK
# ============================================================

if [ "$(id -u)" -ne 0 ]; then
    clear
    echo
    echo -e "${RED}${BOLD}✖ ROOT ACCESS REQUIRED${NC}"
    echo
    echo "Run:"
    echo -e "${CYAN}sudo bash $0${NC}"
    echo
    exit 1
fi

# ============================================================
# ANIMATION
# ============================================================

SPINNER_PID=""

spinner_start() {
    local text="$1"

    (
        local chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
        local i=0

        while true; do
            printf "\r${CYAN}${chars:i++%${#chars}:1}${NC} ${WHITE}%s${NC}" "$text"
            sleep 0.08
        done
    ) &

    SPINNER_PID=$!
}

spinner_stop() {
    if [ -n "${SPINNER_PID:-}" ]; then
        kill "$SPINNER_PID" 2>/dev/null || true
        wait "$SPINNER_PID" 2>/dev/null || true
        SPINNER_PID=""
    fi

    printf "\r\033[K"
}

run_cmd() {
    local name="$1"
    shift

    echo
    echo -e "${BLUE}┌─${NC} ${WHITE}${name}${NC}"

    spinner_start "$name"

    if "$@" >>"$LOG" 2>&1; then
        spinner_stop
        echo -e "${GREEN}└─ ✔ ${name}${NC}"
        return 0
    else
        spinner_stop
        echo -e "${RED}└─ ✖ ${name}${NC}"
        echo
        echo -e "${YELLOW}Last log:${NC}"
        tail -20 "$LOG"
        return 1
    fi
}

# ============================================================
# HEADER
# ============================================================

header() {
    clear

    echo
    echo -e "${MAGENTA}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║                                                          ║"
    echo "║          PTERODACTYL PANEL MANAGER                      ║"
    echo "║                                                          ║"
    echo "║          Dependency • Install • Update • Remove          ║"
    echo "║                                                          ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    echo -e "${GRAY}Project: ${PROJECT}${NC}"
    echo
}

# ============================================================
# PROJECT CHECK
# ============================================================

check_project() {

    if [ ! -d "$PROJECT" ]; then
        echo -e "${RED}✖ Project directory not found:${NC}"
        echo "$PROJECT"
        exit 1
    fi

    if [ ! -f "$PROJECT/package.json" ]; then
        echo -e "${RED}✖ package.json not found:${NC}"
        echo "$PROJECT/package.json"
        exit 1
    fi
}

# ============================================================
# NODE INSTALL
# ============================================================

install_node() {

    if command -v node >/dev/null 2>&1; then
        echo -e "${GREEN}✔ Node.js already installed: $(node --version)${NC}"
        return
    fi

    echo
    echo -e "${CYAN}Installing Node.js 22...${NC}"

    run_cmd "Downloading NodeSource setup" \
        bash -c 'curl -fsSL https://deb.nodesource.com/setup_22.x | bash -'

    run_cmd "Installing Node.js" \
        apt-get install -y nodejs

    echo -e "${GREEN}✔ Node.js installed: $(node --version)${NC}"
}

# ============================================================
# YARN INSTALL
# ============================================================

install_yarn() {

    echo
    echo -e "${CYAN}Checking Yarn...${NC}"

    if command -v yarn >/dev/null 2>&1; then
        echo -e "${GREEN}✔ Yarn already installed: $(yarn --version)${NC}"
        return
    fi

    if ! command -v corepack >/dev/null 2>&1; then

        run_cmd "Installing Corepack" \
            npm install -g corepack

    fi

    run_cmd "Enabling Corepack" \
        corepack enable

    run_cmd "Preparing Yarn 1.22.22" \
        corepack prepare yarn@1.22.22 --activate

    hash -r

    # Fallback wrapper
    if ! command -v yarn >/dev/null 2>&1; then

        echo -e "${YELLOW}Creating Yarn command wrapper...${NC}"

        cat > /usr/local/bin/yarn <<'EOF'
#!/usr/bin/env bash
exec corepack yarn "$@"
EOF

        cat > /usr/local/bin/yarnpkg <<'EOF'
#!/usr/bin/env bash
exec corepack yarn "$@"
EOF

        chmod +x /usr/local/bin/yarn
        chmod +x /usr/local/bin/yarnpkg

        hash -r
    fi

    if ! command -v yarn >/dev/null 2>&1; then
        echo -e "${RED}✖ Yarn installation failed.${NC}"
        exit 1
    fi

    echo -e "${GREEN}✔ Yarn: $(yarn --version)${NC}"
}

# ============================================================
# SYSTEM DEPENDENCIES
# ============================================================

install_system_dependencies() {

    echo
    echo -e "${CYAN}Installing required system packages...${NC}"

    run_cmd "Updating APT package list" \
        apt-get update -y

    run_cmd "Installing curl" \
        apt-get install -y curl

    run_cmd "Installing Git" \
        apt-get install -y git

    run_cmd "Installing build tools" \
        apt-get install -y build-essential

    run_cmd "Installing Python3" \
        apt-get install -y python3
}

# ============================================================
# INSTALL / FIX
# ============================================================

install_fix() {

    header

    echo -e "${CYAN}${BOLD}INSTALL / FIX MODE${NC}"
    echo
    echo "This will:"
    echo " • Check Node.js"
    echo " • Setup Yarn"
    echo " • Remove broken node_modules"
    echo " • Install dependencies"
    echo " • Fix Webpack"
    echo " • Fix React"
    echo

    read -rp "Press ENTER to continue or Ctrl+C to cancel..."

    check_project

    cd "$PROJECT"

    echo
    echo -e "${MAGENTA}━━━ SYSTEM ━━━${NC}"

    install_system_dependencies

    echo
    echo -e "${MAGENTA}━━━ NODE.JS ━━━${NC}"

    install_node

    echo
    echo -e "${MAGENTA}━━━ YARN ━━━${NC}"

    install_yarn

    echo
    echo -e "${MAGENTA}━━━ CLEANING ━━━${NC}"

    run_cmd "Removing node_modules" \
        rm -rf node_modules

    echo
    echo -e "${MAGENTA}━━━ DEPENDENCIES ━━━${NC}"

    if [ -f yarn.lock ]; then

        if ! run_cmd "Installing packages from yarn.lock" \
            yarn install --frozen-lockfile; then

            run_cmd "Installing packages with Yarn" \
                yarn install
        fi

    else

        run_cmd "Installing packages from package.json" \
            yarn install

    fi

    echo
    echo -e "${MAGENTA}━━━ WEBPACK ━━━${NC}"

    if node -e "require.resolve('webpack')" >/dev/null 2>&1; then

        echo -e "${GREEN}✔ Webpack already installed${NC}"

    else

        run_cmd "Installing Webpack" \
            yarn add --dev webpack

    fi

    echo
    echo -e "${MAGENTA}━━━ REACT ━━━${NC}"

    if node -e "require.resolve('react')" >/dev/null 2>&1; then

        echo -e "${GREEN}✔ React already installed${NC}"

    else

        run_cmd "Installing React + React DOM" \
            yarn add react react-dom

    fi

    echo
    echo -e "${MAGENTA}━━━ FINAL CHECK ━━━${NC}"

    echo

    if node -e "require.resolve('webpack')" >/dev/null 2>&1; then
        echo -e "${GREEN}✔ Webpack: $(node -e "console.log(require('webpack/package.json').version)")${NC}"
    else
        echo -e "${RED}✖ Webpack missing${NC}"
    fi

    if node -e "require.resolve('react')" >/dev/null 2>&1; then
        echo -e "${GREEN}✔ React: $(node -e "console.log(require('react/package.json').version)")${NC}"
    else
        echo -e "${RED}✖ React missing${NC}"
    fi

    echo
    echo -e "${GREEN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║                  INSTALL COMPLETE ✔                      ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    read -rp "Press ENTER to return to menu..."
}

# ============================================================
# UPDATE
# ============================================================

update_panel() {

    header

    echo -e "${CYAN}${BOLD}UPDATE MODE${NC}"
    echo
    echo "This will update the Pterodactyl dependencies."
    echo

    read -rp "Press ENTER to continue or Ctrl+C to cancel..."

    check_project

    cd "$PROJECT"

    echo
    echo -e "${MAGENTA}━━━ CHECKING TOOLS ━━━${NC}"

    install_node
    install_yarn

    echo
    echo -e "${MAGENTA}━━━ UPDATING PACKAGES ━━━${NC}"

    run_cmd "Checking outdated packages" \
        yarn outdated || true

    echo
    echo -e "${YELLOW}Updating dependencies...${NC}"

    run_cmd "Updating Yarn dependencies" \
        yarn upgrade

    echo
    echo -e "${MAGENTA}━━━ VERIFY ━━━${NC}"

    if node -e "require.resolve('webpack')" >/dev/null 2>&1; then
        echo -e "${GREEN}✔ Webpack OK${NC}"
    else
        echo -e "${YELLOW}Webpack missing → installing...${NC}"
        run_cmd "Installing Webpack" yarn add --dev webpack
    fi

    if node -e "require.resolve('react')" >/dev/null 2>&1; then
        echo -e "${GREEN}✔ React OK${NC}"
    else
        echo -e "${YELLOW}React missing → installing...${NC}"
        run_cmd "Installing React" yarn add react react-dom
    fi

    echo
    echo -e "${GREEN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║                    UPDATE COMPLETE ✔                     ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    read -rp "Press ENTER to return to menu..."
}

# ============================================================
# UNINSTALL
# ============================================================

uninstall_dependencies() {

    header

    echo -e "${RED}${BOLD}UNINSTALL MODE${NC}"
    echo
    echo "This will remove:"
    echo " • node_modules"
    echo " • Yarn cache"
    echo " • Corepack Yarn setup"
    echo
    echo "package.json and yarn.lock WILL NOT be deleted."
    echo

    read -rp "Type REMOVE to continue: " CONFIRM

    if [ "$CONFIRM" != "REMOVE" ]; then
        echo
        echo -e "${YELLOW}Cancelled.${NC}"
        sleep 2
        return
    fi

    check_project

    cd "$PROJECT"

    echo
    echo -e "${MAGENTA}━━━ REMOVING PROJECT DEPENDENCIES ━━━${NC}"

    if [ -d node_modules ]; then
        run_cmd "Removing node_modules" \
            rm -rf node_modules
    else
        echo -e "${GRAY}node_modules not found.${NC}"
    fi

    echo
    echo -e "${MAGENTA}━━━ CLEANING YARN ━━━${NC}"

    if command -v yarn >/dev/null 2>&1; then
        run_cmd "Cleaning Yarn cache" \
            yarn cache clean || true
    fi

    echo
    echo -e "${MAGENTA}━━━ REMOVING YARN WRAPPERS ━━━${NC}"

    rm -f /usr/local/bin/yarn
    rm -f /usr/local/bin/yarnpkg

    echo -e "${GREEN}✔ Yarn wrappers removed${NC}"

    echo
    echo -e "${YELLOW}Note:${NC} Node.js ko remove nahi kiya gaya."
    echo "System ke other applications Node.js use kar sakte hain."

    echo
    echo -e "${GREEN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║                  UNINSTALL COMPLETE ✔                    ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    read -rp "Press ENTER to return to menu..."
}

# ============================================================
# MAIN MENU
# ============================================================

while true; do

    header

    echo -e "${WHITE}${BOLD}SELECT OPTION${NC}"
    echo

    echo -e " ${GREEN}[1]${NC} Install / Fix"
    echo -e "     ${GRAY}Fresh dependencies + Webpack + React repair${NC}"
    echo

    echo -e " ${CYAN}[2]${NC} Update"
    echo -e "     ${GRAY}Update installed project dependencies${NC}"
    echo

    echo -e " ${RED}[3]${NC} Uninstall"
    echo -e "     ${GRAY}Remove node_modules + Yarn setup${NC}"
    echo

    echo -e "${GRAY}──────────────────────────────────────────────────────${NC}"
    echo

    read -rp "Enter option [1-3]: " OPTION

    case "$OPTION" in

        1)
            install_fix
            ;;

        2)
            update_panel
            ;;

        3)
            uninstall_dependencies
            ;;

        *)
            echo
            echo -e "${RED}✖ Invalid option.${NC}"
            sleep 1
            ;;

    esac

done
