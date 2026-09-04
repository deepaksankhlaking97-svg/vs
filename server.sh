#!/usr/bin/env bash

# ============================================================
# KINGCLOUD MINECRAFT VPS + WEB PANEL
# ============================================================

set -u

BASE="/opt/minecraft/server"
PANEL_DIR="/opt/kingcloud-panel"
SERVICE="minecraft"
PANEL_SERVICE="kingcloud-panel"
PINGGY_SERVICE="minecraft-pinggy"

MC_PORT="25565"
PANEL_PORT="8080"

RESET="\033[0m"
BOLD="\033[1m"
CYAN="\033[1;36m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
WHITE="\033[1;37m"
BLUE="\033[1;34m"
GRAY="\033[0;37m"

# ============================================================
# ROOT CHECK
# ============================================================

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}✖ Run this script as root${RESET}"
    echo
    echo "sudo bash kingcloud.sh"
    exit 1
fi

# ============================================================
# FUNCTIONS
# ============================================================

pause_menu() {
    echo
    read -rp "Press ENTER to continue..."
}

success() {
    echo -e "${GREEN}✓${RESET} $1"
}

error() {
    echo -e "${RED}✖${RESET} $1"
}

info() {
    echo -e "${CYAN}➜${RESET} $1"
}

loading() {
    local text="$1"
    local seconds="${2:-2}"
    local spin='|/-\'
    local end=$((SECONDS + seconds))

    while [ "$SECONDS" -lt "$end" ]; do
        for ((i=0;i<4;i++)); do
            printf "\r${CYAN}[${spin:i:1}]${RESET} ${WHITE}${text}${RESET}"
            sleep 0.1
            [ "$SECONDS" -ge "$end" ] && break
        done
    done

    printf "\r${GREEN}[✓]${RESET} ${WHITE}${text}${RESET}\n"
}

banner() {
    clear

    echo -e "${CYAN}${BOLD}"
    echo "╔════════════════════════════════════════════════╗"
    echo "║                                                ║"
    echo "║           KINGCLOUD MINECRAFT VPS              ║"
    echo "║               WEB MANAGEMENT                   ║"
    echo "║                                                ║"
    echo "╚════════════════════════════════════════════════╝"
    echo -e "${RESET}"

    echo -e "${GRAY}"
    echo " Minecraft : $BASE"
    echo " Minecraft : $MC_PORT"
    echo " Panel     : $PANEL_PORT"
    echo -e "${RESET}"
}

# ============================================================
# INSTALL DEPENDENCIES
# ============================================================

install_dependencies() {

    info "Updating packages..."

    apt-get update -y >/dev/null 2>&1

    apt-get install -y \
        curl \
        wget \
        jq \
        openssh-client \
        ca-certificates \
        python3 \
        python3-pip \
        >/dev/null 2>&1

    success "Dependencies installed"
}

# ============================================================
# JAVA
# ============================================================

install_java() {

    if command -v java >/dev/null 2>&1; then
        success "Java already installed"
        java -version 2>&1 | head -n 1
        return
    fi

    info "Installing Java 21..."

    apt-get install -y openjdk-21-jre-headless >/dev/null 2>&1

    if command -v java >/dev/null 2>&1; then
        success "Java installed"
    else
        error "Java installation failed"
        return 1
    fi
}

# ============================================================
# RAM
# ============================================================

get_ram() {

    RAM_MB=$(free -m | awk '/^Mem:/ {print $2}')

    if [ -z "$RAM_MB" ]; then
        RAM_MB=4096
    fi

    if [ "$RAM_MB" -le 2048 ]; then
        SERVER_RAM="1G"
    elif [ "$RAM_MB" -le 4096 ]; then
        SERVER_RAM="2G"
    elif [ "$RAM_MB" -le 8192 ]; then
        SERVER_RAM="4G"
    elif [ "$RAM_MB" -le 16384 ]; then
        SERVER_RAM="8G"
    elif [ "$RAM_MB" -le 32768 ]; then
        SERVER_RAM="16G"
    else
        SERVER_RAM="24G"
    fi
}

# ============================================================
# PAPER
# ============================================================

download_paper() {

    mkdir -p "$BASE"
    cd "$BASE" || return 1

    echo
    echo -e "${WHITE}${BOLD}Minecraft Version${RESET}"
    echo

    read -rp "Version [1.21.11]: " MC_VERSION
    MC_VERSION="${MC_VERSION:-1.21.11}"

    info "Connecting to PaperMC..."

    BUILDS=$(curl -fsSL \
        --retry 3 \
        --connect-timeout 10 \
        --max-time 30 \
        "https://fill.papermc.io/v3/projects/paper/versions/${MC_VERSION}/builds" \
        2>/dev/null || true)

    if [ -z "$BUILDS" ]; then
        error "Could not connect to PaperMC"
        return 1
    fi

    PAPER_URL=$(echo "$BUILDS" | jq -r '
        map(select(.channel=="STABLE"))
        | sort_by(.id)
        | last
        | .downloads["server:default"].url // empty
    ' 2>/dev/null || true)

    if [ -z "$PAPER_URL" ]; then
        error "No stable Paper build found for $MC_VERSION"
        echo
        echo "Try another supported Paper version."
        return 1
    fi

    success "Paper build found"

    echo
    info "Downloading Paper $MC_VERSION..."

    rm -f "$BASE/server.jar"

    if ! curl -fL \
        --retry 3 \
        --connect-timeout 15 \
        --max-time 600 \
        "$PAPER_URL" \
        -o "$BASE/server.jar"; then

        error "Paper download failed"
        return 1
    fi

    if [ ! -s "$BASE/server.jar" ]; then
        error "server.jar is empty"
        return 1
    fi

    echo "$MC_VERSION" > "$BASE/minecraft-version.txt"

    success "Paper downloaded"
}

# ============================================================
# MINECRAFT SERVICE
# ============================================================

create_minecraft_service() {

    get_ram

    JAVA_PATH="$(command -v java)"

    cat > "/etc/systemd/system/minecraft.service" <<EOF
[Unit]
Description=KINGCLOUD Minecraft Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$BASE

ExecStart=$JAVA_PATH -Xms1G -Xmx${SERVER_RAM} -XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 -XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch -jar $BASE/server.jar nogui

Restart=on-failure
RestartSec=10

LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable minecraft >/dev/null 2>&1

    success "Minecraft service configured"
}

# ============================================================
# MINECRAFT CONFIG
# ============================================================

create_minecraft_config() {

    echo "eula=true" > "$BASE/eula.txt"

    if [ ! -f "$BASE/server.properties" ]; then
        cat > "$BASE/server.properties" <<EOF
motd=§bKINGCLOUD §fMinecraft Server
server-port=25565
online-mode=true
difficulty=normal
gamemode=survival
max-players=20
view-distance=10
simulation-distance=8
spawn-protection=16
white-list=false
enable-command-block=false
EOF
    fi

    mkdir -p "$BASE/plugins"
    mkdir -p "$BASE/backups"
    mkdir -p "$BASE/logs"

    success "Minecraft configuration ready"
}

# ============================================================
# PINGGY
# ============================================================

create_pinggy_service() {

    cat > "/etc/systemd/system/${PINGGY_SERVICE}.service" <<EOF
[Unit]
Description=KINGCLOUD Minecraft Pinggy TCP Tunnel
After=network.target minecraft.service

[Service]
Type=simple

ExecStart=/usr/bin/ssh -p 443 -o StrictHostKeyChecking=no -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -R0:127.0.0.1:25565 tcp@free.pinggy.io

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "$PINGGY_SERVICE" >/dev/null 2>&1

    success "Pinggy service created"
}

# ============================================================
# WEB PANEL
# ============================================================

install_panel() {

    banner

    echo
    echo -e "${CYAN}${BOLD}KINGCLOUD WEB PANEL INSTALLATION${RESET}"
    echo

    mkdir -p "$PANEL_DIR"

    # --------------------------------------------------------
    # PASSWORD
    # --------------------------------------------------------

    echo -e "${YELLOW}Create panel login${RESET}"
    echo

    read -rp "Panel username [admin]: " PANEL_USER
    PANEL_USER="${PANEL_USER:-admin}"

    while true; do

        read -rsp "Panel password: " PANEL_PASS
        echo

        if [ "${#PANEL_PASS}" -lt 8 ]; then
            error "Password must be at least 8 characters"
            continue
        fi

        break
    done

    # Escape for Python string
    PANEL_USER_PY=$(printf '%s' "$PANEL_USER" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')
    PANEL_PASS_PY=$(printf '%s' "$PANEL_PASS" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')

    # --------------------------------------------------------
    # PYTHON PANEL
    # --------------------------------------------------------

    cat > "$PANEL_DIR/panel.py" <<'PYEOF'
#!/usr/bin/env python3

import os
import json
import time
import uuid
import shutil
import hashlib
import secrets
import subprocess
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

BASE = "/opt/minecraft/server"
PORT = 8080

USERNAME = PANEL_USERNAME
PASSWORD = PANEL_PASSWORD

SESSIONS = {}

MAX_BODY = 20 * 1024 * 1024


def html_escape(s):
    return (
        str(s)
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
        .replace("'", "&#039;")
    )


def safe_path(rel):
    rel = urllib.parse.unquote(rel or "")
    rel = rel.replace("\\", "/")

    if rel.startswith("/"):
        rel = rel[1:]

    full = os.path.realpath(os.path.join(BASE, rel))

    if full != BASE and not full.startswith(BASE + os.sep):
        raise ValueError("Invalid path")

    return full


def service_status(service):
    p = subprocess.run(
        ["systemctl", "is-active", service],
        capture_output=True,
        text=True
    )

    return p.stdout.strip() == "active"


def service_action(action):
    return subprocess.run(
        ["systemctl", action, "minecraft"],
        capture_output=True,
        text=True,
        timeout=30
    )


def recent_logs(lines=150):
    p = subprocess.run(
        [
            "journalctl",
            "-u",
            "minecraft",
            "-n",
            str(lines),
            "--no-pager",
            "-o",
            "cat"
        ],
        capture_output=True,
        text=True,
        timeout=10
    )

    return p.stdout


def send_json(handler, data, status=200):
    raw = json.dumps(data).encode()

    handler.send_response(status)
    handler.send_header("Content-Type", "application/json")
    handler.send_header("Content-Length", str(len(raw)))
    handler.end_headers()
    handler.wfile.write(raw)


class Handler(BaseHTTPRequestHandler):

    def log_message(self, fmt, *args):
        pass

    def session_ok(self):
        cookie = self.headers.get("Cookie", "")

        for item in cookie.split(";"):
            item = item.strip()

            if item.startswith("kc_session="):
                token = item.split("=", 1)[1]

                if token in SESSIONS:
                    if SESSIONS[token] > time.time():
                        return True

        return False

    def require_auth(self):
        if not self.session_ok():
            self.send_response(302)
            self.send_header("Location", "/login")
            self.end_headers()
            return False

        return True

    def body(self):
        length = int(self.headers.get("Content-Length", "0"))

        if length > MAX_BODY:
            raise ValueError("Request too large")

        return self.rfile.read(length)

    def do_GET(self):

        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        if path == "/login":

            self.login_page()
            return

        if path == "/logout":

            self.logout()
            return

        if not self.require_auth():
            return

        if path == "/":
            self.dashboard()
            return

        if path == "/api/status":

            send_json(
                self,
                {
                    "minecraft": service_status("minecraft"),
                    "pinggy": service_status("minecraft-pinggy"),
                    "logs": recent_logs(200)
                }
            )
            return

        if path == "/api/files":

            query = urllib.parse.parse_qs(parsed.query)
            rel = query.get("path", [""])[0]

            try:
                folder = safe_path(rel)

                if not os.path.isdir(folder):
                    send_json(self, {"error": "Folder not found"}, 404)
                    return

                files = []

                for name in sorted(os.listdir(folder)):
                    full = os.path.join(folder, name)

                    try:
                        size = os.path.getsize(full)
                    except:
                        size = 0

                    files.append(
                        {
                            "name": name,
                            "dir": os.path.isdir(full),
                            "size": size
                        }
                    )

                send_json(
                    self,
                    {
                        "path": rel,
                        "files": files
                    }
                )

            except Exception as e:
                send_json(self, {"error": str(e)}, 400)

            return

        if path == "/api/read":

            query = urllib.parse.parse_qs(parsed.query)
            rel = query.get("path", [""])[0]

            try:
                full = safe_path(rel)

                if not os.path.isfile(full):
                    send_json(self, {"error": "File not found"}, 404)
                    return

                if os.path.getsize(full) > 5 * 1024 * 1024:
                    send_json(self, {"error": "File is too large to edit"}, 400)
                    return

                with open(full, "r", encoding="utf-8", errors="replace") as f:
                    content = f.read()

                send_json(
                    self,
                    {
                        "path": rel,
                        "content": content
                    }
                )

            except Exception as e:
                send_json(self, {"error": str(e)}, 400)

            return

        if path == "/api/download":

            query = urllib.parse.parse_qs(parsed.query)
            rel = query.get("path", [""])[0]

            try:
                full = safe_path(rel)

                if not os.path.isfile(full):
                    self.send_error(404)
                    return

                filename = os.path.basename(full)

                with open(full, "rb") as f:
                    data = f.read()

                self.send_response(200)
                self.send_header(
                    "Content-Type",
                    "application/octet-stream"
                )
                self.send_header(
                    "Content-Disposition",
                    f'attachment; filename="{filename}"'
                )
                self.send_header(
                    "Content-Length",
                    str(len(data))
                )
                self.end_headers()
                self.wfile.write(data)

            except Exception as e:
                self.send_error(400, str(e))

            return

        self.send_error(404)

    def do_POST(self):

        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        if path == "/login":

            self.login()
            return

        if not self.require_auth():
            return

        try:
            raw = self.body()

            if raw:
                data = json.loads(raw.decode())
            else:
                data = {}

        except Exception:
            send_json(self, {"error": "Invalid JSON"}, 400)
            return

        # ----------------------------------------------------
        # SERVICE
        # ----------------------------------------------------

        if path == "/api/action":

            action = data.get("action")

            if action not in ["start", "stop", "restart"]:
                send_json(self, {"error": "Invalid action"}, 400)
                return

            result = service_action(action)

            send_json(
                self,
                {
                    "ok": result.returncode == 0,
                    "output": result.stdout + result.stderr
                }
            )
            return

        # ----------------------------------------------------
        # MINECRAFT COMMAND
        # ----------------------------------------------------

        if path == "/api/command":

            command = str(data.get("command", "")).strip()

            if not command:
                send_json(self, {"error": "Command is empty"}, 400)
                return

            # Send command directly to Minecraft through systemd stdin
            # systemctl service does not expose stdin reliably,
            # therefore use the Minecraft RCON protocol if enabled.

            send_json(
                self,
                {
                    "error":
                    "Enable RCON in server.properties for remote console commands. "
                    "Use the server console or enable RCON first."
                },
                400
            )
            return

        # ----------------------------------------------------
        # SAVE FILE
        # ----------------------------------------------------

        if path == "/api/save":

            rel = data.get("path", "")
            content = data.get("content", "")

            try:
                full = safe_path(rel)

                if os.path.isdir(full):
                    send_json(self, {"error": "Cannot edit a directory"}, 400)
                    return

                with open(full, "w", encoding="utf-8") as f:
                    f.write(content)

                send_json(self, {"ok": True})

            except Exception as e:
                send_json(self, {"error": str(e)}, 400)

            return

        # ----------------------------------------------------
        # DELETE
        # ----------------------------------------------------

        if path == "/api/delete":

            rel = data.get("path", "")

            try:
                full = safe_path(rel)

                if full == BASE:
                    send_json(self, {"error": "Cannot delete server root"}, 400)
                    return

                if os.path.isdir(full):
                    shutil.rmtree(full)
                else:
                    os.remove(full)

                send_json(self, {"ok": True})

            except Exception as e:
                send_json(self, {"error": str(e)}, 400)

            return

        # ----------------------------------------------------
        # RENAME
        # ----------------------------------------------------

        if path == "/api/rename":

            old = data.get("old", "")
            new = data.get("new", "")

            try:
                old_full = safe_path(old)
                new_full = safe_path(new)

                if old_full == BASE:
                    send_json(self, {"error": "Invalid source"}, 400)
                    return

                if os.path.exists(new_full):
                    send_json(self, {"error": "Destination already exists"}, 400)
                    return

                os.rename(old_full, new_full)

                send_json(self, {"ok": True})

            except Exception as e:
                send_json(self, {"error": str(e)}, 400)

            return

        # ----------------------------------------------------
        # CREATE FOLDER
        # ----------------------------------------------------

        if path == "/api/mkdir":

            rel = data.get("path", "")

            try:
                full = safe_path(rel)

                os.makedirs(full, exist_ok=False)

                send_json(self, {"ok": True})

            except Exception as e:
                send_json(self, {"error": str(e)}, 400)

            return

        # ----------------------------------------------------
        # UPLOAD
        # ----------------------------------------------------

        if path == "/api/upload":

            rel = data.get("path", "")
            filename = os.path.basename(data.get("filename", ""))
            content = data.get("content", "")

            if not filename:
                send_json(self, {"error": "Invalid filename"}, 400)
                return

            try:
                folder = safe_path(rel)

                if not os.path.isdir(folder):
                    send_json(self, {"error": "Folder not found"}, 404)
                    return

                full = os.path.join(folder, filename)

                decoded = __import__("base64").b64decode(content)

                if len(decoded) > MAX_BODY:
                    send_json(self, {"error": "File too large"}, 400)
                    return

                with open(full, "wb") as f:
                    f.write(decoded)

                send_json(self, {"ok": True})

            except Exception as e:
                send_json(self, {"error": str(e)}, 400)

            return

        self.send_error(404)

    # ========================================================
    # LOGIN
    # ========================================================

    def login_page(self, error=""):

        msg = ""

        if error:
            msg = f'<div class="error">{html_escape(error)}</div>'

        page = f"""
<!DOCTYPE html>
<html>
<head>
<title>KingCloud Login</title>
<style>
* {{
box-sizing:border-box;
}}

body {{
margin:0;
font-family:Arial,sans-serif;
background:#09090f;
color:white;
display:flex;
align-items:center;
justify-content:center;
height:100vh;
}}

.login {{
width:380px;
background:#11111a;
padding:35px;
border-radius:18px;
box-shadow:0 0 50px #000;
}}

.logo {{
font-size:28px;
font-weight:bold;
margin-bottom:8px;
}}

.sub {{
color:#888;
margin-bottom:25px;
}}

input {{
width:100%;
padding:13px;
margin:8px 0;
border-radius:9px;
border:1px solid #333;
background:#08080d;
color:white;
}}

button {{
width:100%;
padding:13px;
margin-top:12px;
border:0;
border-radius:9px;
background:#7c3aed;
color:white;
font-weight:bold;
cursor:pointer;
}}

button:hover {{
background:#6d28d9;
}}

.error {{
background:#451a1a;
padding:10px;
border-radius:8px;
margin-bottom:10px;
color:#ff8b8b;
}}
</style>
</head>
<body>
<div class="login">
<div class="logo">☁ KINGCLOUD</div>
<div class="sub">Minecraft VPS Panel</div>
{msg}
<form method="POST" action="/login">
<input name="username" placeholder="Username" autocomplete="username">
<input name="password" type="password" placeholder="Password" autocomplete="current-password">
<button type="submit">LOGIN</button>
</form>
</div>
</body>
</html>
"""

        raw = page.encode()

        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def login(self):

        length = int(self.headers.get("Content-Length", "0"))

        if length > 10000:
            self.login_page("Invalid request")
            return

        body = self.rfile.read(length).decode()

        data = urllib.parse.parse_qs(body)

        user = data.get("username", [""])[0]
        password = data.get("password", [""])[0]

        if user == USERNAME and secrets.compare_digest(
            password,
            PASSWORD
        ):

            token = secrets.token_urlsafe(32)

            SESSIONS[token] = time.time() + 86400

            self.send_response(302)
            self.send_header("Location", "/")
            self.send_header(
                "Set-Cookie",
                f"kc_session={token}; HttpOnly; SameSite=Strict"
            )
            self.end_headers()

        else:

            self.login_page("Invalid username or password")

    def logout(self):

        self.send_response(302)
        self.send_header("Location", "/login")
        self.send_header(
            "Set-Cookie",
            "kc_session=; Max-Age=0; HttpOnly"
        )
        self.end_headers()

    # ========================================================
    # DASHBOARD
    # ========================================================

    def dashboard(self):

        page = r"""
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>KingCloud Minecraft Panel</title>

<style>

*{
box-sizing:border-box;
}

body{
margin:0;
font-family:Inter,Arial,sans-serif;
background:#08080d;
color:#eee;
}

.header{
height:65px;
background:#101018;
border-bottom:1px solid #252532;
display:flex;
align-items:center;
padding:0 20px;
justify-content:space-between;
position:sticky;
top:0;
z-index:10;
}

.logo{
font-size:21px;
font-weight:800;
color:#a78bfa;
}

.logout{
color:#ff7b7b;
text-decoration:none;
}

.layout{
display:grid;
grid-template-columns:230px 1fr;
min-height:calc(100vh - 65px);
}

.sidebar{
background:#0d0d14;
border-right:1px solid #22222d;
padding:15px;
}

.nav{
width:100%;
padding:12px;
margin-bottom:7px;
border:0;
border-radius:9px;
background:transparent;
color:#aaa;
text-align:left;
cursor:pointer;
font-size:14px;
}

.nav:hover,
.nav.active{
background:#191525;
color:#c4b5fd;
}

.content{
padding:22px;
overflow:auto;
}

.cards{
display:grid;
grid-template-columns:repeat(4,1fr);
gap:15px;
}

.card{
background:#11111a;
border:1px solid #252532;
border-radius:14px;
padding:18px;
}

.card-title{
color:#888;
font-size:13px;
}

.card-value{
font-size:22px;
font-weight:bold;
margin-top:7px;
}

.online{
color:#4ade80;
}

.offline{
color:#f87171;
}

.section{
margin-top:18px;
background:#11111a;
border:1px solid #252532;
border-radius:14px;
padding:18px;
}

h2{
margin-top:0;
}

.actions{
display:flex;
gap:10px;
flex-wrap:wrap;
}

.btn{
border:0;
border-radius:8px;
padding:10px 16px;
background:#252535;
color:white;
cursor:pointer;
}

.btn:hover{
background:#35354a;
}

.green{
background:#166534;
}

.red{
background:#991b1b;
}

.purple{
background:#6d28d9;
}

.console{
height:450px;
background:#050507;
border:1px solid #292934;
border-radius:10px;
padding:14px;
overflow:auto;
font-family:monospace;
font-size:13px;
white-space:pre-wrap;
color:#d4d4d4;
}

.command{
display:flex;
margin-top:10px;
gap:8px;
}

.command input{
flex:1;
background:#050507;
border:1px solid #30303a;
border-radius:8px;
padding:12px;
color:white;
}

.files{
width:100%;
border-collapse:collapse;
}

.files th,
.files td{
padding:11px;
border-bottom:1px solid #252532;
text-align:left;
}

.file{
cursor:pointer;
}

.file:hover{
background:#181821;
}

.editor{
width:100%;
height:500px;
background:#07070b;
color:#ddd;
border:1px solid #30303a;
border-radius:10px;
padding:15px;
font-family:monospace;
resize:vertical;
}

.path{
color:#a78bfa;
margin-bottom:12px;
}

.small{
color:#777;
font-size:12px;
}

.hidden{
display:none;
}

@media(max-width:900px){

.layout{
grid-template-columns:1fr;
}

.sidebar{
display:flex;
overflow:auto;
gap:5px;
}

.nav{
min-width:130px;
}

.cards{
grid-template-columns:repeat(2,1fr);
}

}

</style>
</head>

<body>

<div class="header">

<div class="logo">
☁ KINGCLOUD
</div>

<a class="logout" href="/logout">
Logout
</a>

</div>

<div class="layout">

<div class="sidebar">

<button class="nav active" onclick="showPage('dashboard',this)">
📊 Dashboard
</button>

<button class="nav" onclick="showPage('console',this)">
🖥️ Live Console
</button>

<button class="nav" onclick="showPage('files',this)">
📁 File Manager
</button>

<button class="nav" onclick="showPage('settings',this)">
⚙️ Server Controls
</button>

</div>

<div class="content">

<!-- DASHBOARD -->

<div id="dashboard">

<h2>Server Dashboard</h2>

<div class="cards">

<div class="card">
<div class="card-title">Minecraft</div>
<div id="mcStatus" class="card-value">Checking...</div>
</div>

<div class="card">
<div class="card-title">Pinggy</div>
<div id="pinggyStatus" class="card-value">Checking...</div>
</div>

<div class="card">
<div class="card-title">Port</div>
<div class="card-value">25565</div>
</div>

<div class="card">
<div class="card-title">Panel</div>
<div class="card-value online">8080</div>
</div>

</div>

<div class="section">

<h2>Server Controls</h2>

<div class="actions">

<button class="btn green" onclick="action('start')">
▶ Start
</button>

<button class="btn red" onclick="action('stop')">
■ Stop
</button>

<button class="btn purple" onclick="action('restart')">
↻ Restart
</button>

</div>

</div>

<div class="section">

<h2>Quick Console</h2>

<div id="quickConsole" class="console">
Loading...
</div>

</div>

</div>


<!-- CONSOLE -->

<div id="console" class="hidden">

<h2>Live Console</h2>

<div class="small">
Minecraft server logs
</div>

<br>

<div id="consoleBox" class="console">
Loading...
</div>

<div class="command">

<input
id="commandInput"
placeholder="Minecraft command e.g. say Hello"
/>

<button class="btn purple" onclick="sendCommand()">
SEND
</button>

</div>

<p class="small">
For remote command execution, enable RCON in server.properties.
</p>

</div>


<!-- FILE MANAGER -->

<div id="files" class="hidden">

<h2>File Manager</h2>

<div class="path" id="currentPath">
/opt/minecraft/server
</div>

<div class="actions">

<button class="btn" onclick="goUp()">
⬆ Up
</button>

<button class="btn purple" onclick="newFolder()">
＋ Folder
</button>

<button class="btn" onclick="uploadFile()">
⬆ Upload
</button>

</div>

<br>

<table class="files">

<thead>

<tr>
<th>Name</th>
<th>Type</th>
<th>Size</th>
<th>Actions</th>
</tr>

</thead>

<tbody id="fileList">
</tbody>

</table>

</div>


<!-- SETTINGS -->

<div id="settings" class="hidden">

<h2>Server Controls</h2>

<div class="section">

<h2>Start</h2>

<button class="btn green" onclick="action('start')">
▶ Start Minecraft
</button>

</div>

<div class="section">

<h2>Stop</h2>

<button class="btn red" onclick="action('stop')">
■ Stop Minecraft
</button>

</div>

<div class="section">

<h2>Restart</h2>

<button class="btn purple" onclick="action('restart')">
↻ Restart Minecraft
</button>

</div>

</div>


<!-- EDITOR -->

<div id="editorPage" class="hidden">

<h2>Edit File</h2>

<div class="path" id="editorPath"></div>

<textarea id="editor" class="editor"></textarea>

<br><br>

<button class="btn purple" onclick="saveFile()">
💾 Save
</button>

<button class="btn" onclick="showPage('files')">
Cancel
</button>

</div>

</div>
</div>


<script>

let currentPath = "";
let editingPath = "";

function $(id){
return document.getElementById(id);
}


function showPage(page,button){

[
"dashboard",
"console",
"files",
"settings",
"editorPage"
].forEach(x=>{
$(x).classList.add("hidden");
});

$(page).classList.remove("hidden");

document.querySelectorAll(".nav").forEach(x=>{
x.classList.remove("active");
});

if(button){
button.classList.add("active");
}

if(page==="files"){
loadFiles();
}

if(page==="console"){
loadStatus();
}

}


async function api(url,options={}){

let response=await fetch(url,options);

if(response.status===401){
location="/login";
return;
}

return await response.json();

}


async function loadStatus(){

let data=await api("/api/status");

if(!data)return;

$("mcStatus").textContent=
data.minecraft ? "ONLINE" : "OFFLINE";

$("mcStatus").className=
"card-value "+
(data.minecraft ? "online":"offline");

$("pinggyStatus").textContent=
data.pinggy ? "ONLINE" : "OFFLINE";

$("pinggyStatus").className=
"card-value "+
(data.pinggy ? "online":"offline");

$("consoleBox").textContent=data.logs;
$("quickConsole").textContent=data.logs;

}


async function action(actionName){

let data=await api(
"/api/action",
{
method:"POST",
headers:{
"Content-Type":"application/json"
},
body:JSON.stringify({
action:actionName
})
});

if(data && data.output){
alert(data.output);
}

loadStatus();

}


async function sendCommand(){

let command=$("commandInput").value.trim();

if(!command)return;

let data=await api(
"/api/command",
{
method:"POST",
headers:{
"Content-Type":"application/json"
},
body:JSON.stringify({
command:command
})
});

if(data.error){
alert(data.error);
}

$("commandInput").value="";

loadStatus();

}


function formatSize(bytes){

if(bytes<1024)return bytes+" B";

if(bytes<1024*1024)
return (bytes/1024).toFixed(1)+" KB";

if(bytes<1024*1024*1024)
return (bytes/1024/1024).toFixed(1)+" MB";

return (bytes/1024/1024/1024).toFixed(1)+" GB";

}


async function loadFiles(){

let data=await api(
"/api/files?path="+
encodeURIComponent(currentPath)
);

if(data.error){
alert(data.error);
return;
}

$("currentPath").textContent=
"/opt/minecraft/server"+
(currentPath ? "/"+currentPath:"");

let html="";

for(let f of data.files){

let full=
currentPath ?
currentPath+"/"+f.name :
f.name;

html+="<tr>";

html+=
"<td class='file' onclick=\"openFile('"+
encodeURIComponent(full)+
"','"+f.dir+"')\">"+
(f.dir?"📁 ":"📄 ")+
escapeHtml(f.name)+
"</td>";

html+=
"<td>"+
(f.dir?"Folder":"File")+
"</td>";

html+=
"<td>"+
(f.dir?"-":formatSize(f.size))+
"</td>";

html+=
"<td>";

if(!f.dir){

html+=
"<button class='btn' onclick=\"editFile('"+
encodeURIComponent(full)+
"')\">Edit</button> ";

html+=
"<button class='btn' onclick=\"downloadFile('"+
encodeURIComponent(full)+
"')\">Download</button> ";

}

html+=
"<button class='btn red' onclick=\"deleteFile('"+
encodeURIComponent(full)+
"')\">Delete</button>";

html+="</td>";

html+="</tr>";

}

$("fileList").innerHTML=html;

}


function escapeHtml(text){

return text
.replaceAll("&","&amp;")
.replaceAll("<","&lt;")
.replaceAll(">","&gt;")
.replaceAll('"',"&quot;");

}


function openFile(path,isDir){

path=decodeURIComponent(path);

if(isDir==="true"){
currentPath=path;
loadFiles();
}

}


function goUp(){

if(!currentPath){
return;
}

let parts=currentPath.split("/");

parts.pop();

currentPath=parts.join("/");

loadFiles();

}


async function editFile(encoded){

let path=decodeURIComponent(encoded);

let data=await api(
"/api/read?path="+
encodeURIComponent(path)
);

if(data.error){
alert(data.error);
return;
}

editingPath=path;

$("editorPath").textContent=
"/opt/minecraft/server/"+path;

$("editor").value=data.content;

showPage("editorPage");

}


async function saveFile(){

let data=await api(
"/api/save",
{
method:"POST",
headers:{
"Content-Type":"application/json"
},
body:JSON.stringify({
path:editingPath,
content:$("editor").value
})
});

if(data.ok){
alert("File saved");
showPage("files");
loadFiles();
}else{
alert(data.error||"Save failed");
}

}


async function deleteFile(encoded){

let path=decodeURIComponent(encoded);

if(!confirm(
"Delete "+path+" ?"
)){
return;
}

let data=await api(
"/api/delete",
{
method:"POST",
headers:{
"Content-Type":"application/json"
},
body:JSON.stringify({
path:path
})
});

if(data.ok){
loadFiles();
}else{
alert(data.error||"Delete failed");
}

}


function downloadFile(encoded){

let path=decodeURIComponent(encoded);

window.open(
"/api/download?path="+
encodeURIComponent(path),
"_blank"
);

}


async function newFolder(){

let name=prompt(
"Folder name:"
);

if(!name)return;

let path=
currentPath ?
currentPath+"/"+name :
name;

let data=await api(
"/api/mkdir",
{
method:"POST",
headers:{
"Content-Type":"application/json"
},
body:JSON.stringify({
path:path
})
});

if(data.ok){
loadFiles();
}else{
alert(data.error||"Failed");
}

}


function uploadFile(){

let input=document.createElement("input");

input.type="file";

input.onchange=async()=>{

let file=input.files[0];

if(!file)return;

if(file.size>20*1024*1024){
alert("Maximum upload size is 20 MB");
return;
}

let reader=new FileReader();

reader.onload=async()=>{

let base64=
reader.result.split(",")[1];

let data=await api(
"/api/upload",
{
method:"POST",
headers:{
"Content-Type":"application/json"
},
body:JSON.stringify({
path:currentPath,
filename:file.name,
content:base64
})
});

if(data.ok){
loadFiles();
}else{
alert(data.error||"Upload failed");
}

};

reader.readAsDataURL(file);

};

input.click();

}


setInterval(loadStatus,3000);

loadStatus();

</script>

</body>
</html>
"""

        page = page.replace(
            "PY_PANEL_PLACEHOLDER",
            ""
        )

        raw = page.encode()

        self.send_response(200)
        self.send_header(
            "Content-Type",
            "text/html; charset=utf-8"
        )
        self.send_header(
            "Content-Length",
            str(len(raw))
        )
        self.end_headers()
        self.wfile.write(raw)


def main():

    os.makedirs(BASE, exist_ok=True)

    print("KINGCLOUD PANEL")
    print("Listening on 0.0.0.0:8080")

    server = ThreadingHTTPServer(
        ("0.0.0.0", PORT),
        Handler
    )

    server.serve_forever()


if __name__ == "__main__":
    main()
PYEOF

    # Replace credentials safely
    sed -i "s|PANEL_USERNAME|${PANEL_USER_PY}|g" "$PANEL_DIR/panel.py"
    sed -i "s|PANEL_PASSWORD|${PANEL_PASS_PY}|g" "$PANEL_DIR/panel.py"

    chmod 700 "$PANEL_DIR"
    chmod 700 "$PANEL_DIR/panel.py"

    # --------------------------------------------------------
    # SYSTEMD PANEL
    # --------------------------------------------------------

    cat > "/etc/systemd/system/${PANEL_SERVICE}.service" <<EOF
[Unit]
Description=KINGCLOUD Minecraft Web Panel
After=network.target minecraft.service

[Service]
Type=simple
User=root
WorkingDirectory=$PANEL_DIR

ExecStart=/usr/bin/python3 $PANEL_DIR/panel.py

Restart=always
RestartSec=3

LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "$PANEL_SERVICE" >/dev/null 2>&1
    systemctl restart "$PANEL_SERVICE"

    sleep 2

    if systemctl is-active --quiet "$PANEL_SERVICE"; then
        success "Web panel started"
    else
        error "Web panel failed to start"
        journalctl -u "$PANEL_SERVICE" -n 30 --no-pager
        return 1
    fi
}

# ============================================================
# INSTALL EVERYTHING
# ============================================================

install_all() {

    banner

    echo
    echo -e "${CYAN}${BOLD}"
    echo "        FULL KINGCLOUD INSTALLATION"
    echo -e "${RESET}"

    echo

    mkdir -p "$BASE"

    install_dependencies

    install_java || {
        pause_menu
        return
    }

    echo

    if [ ! -f "$BASE/server.jar" ]; then

        download_paper || {
            pause_menu
            return
        }

    else

        success "Existing server.jar found"

    fi

    create_minecraft_config
    create_minecraft_service
    create_pinggy_service

    echo

    install_panel || {
        pause_menu
        return
    }

    echo

    loading "Finalizing KINGCLOUD installation" 2

    IP=$(curl -4 -fsSL https://api.ipify.org 2>/dev/null || echo "YOUR-VPS-IP")

    echo
    echo -e "${GREEN}"
    echo "╔════════════════════════════════════════════════╗"
    echo "║             INSTALLATION COMPLETE             ║"
    echo "╚════════════════════════════════════════════════╝"
    echo -e "${RESET}"

    echo
    echo -e "${WHITE}Web Panel:${RESET}"
    echo
    echo "  http://$IP:8080"

    echo
    echo -e "${WHITE}Minecraft:${RESET}"
    echo
    echo "  $IP:$MC_PORT"

    echo
    echo -e "${WHITE}Server Folder:${RESET}"
    echo
    echo "  $BASE"

    echo
    echo -e "${WHITE}Panel Folder:${RESET}"
    echo
    echo "  $PANEL_DIR"

    echo
    echo -e "${YELLOW}Login:${RESET}"
    echo
    echo "  Username: $PANEL_USER"
    echo "  Password: ********"

    echo
    echo -e "${GREEN}✓ KINGCLOUD panel is ready.${RESET}"

    pause_menu
}

# ============================================================
# START
# ============================================================

start_server() {

    banner

    info "Starting Minecraft..."

    systemctl start minecraft

    sleep 3

    if systemctl is-active --quiet minecraft; then
        success "Minecraft ONLINE"
    else
        error "Minecraft failed to start"
        journalctl -u minecraft -n 30 --no-pager
    fi

    pause_menu
}

# ============================================================
# STOP
# ============================================================

stop_server() {

    banner

    info "Stopping Minecraft..."

    systemctl stop minecraft

    success "Minecraft stopped"

    pause_menu
}

# ============================================================
# RESTART
# ============================================================

restart_server() {

    banner

    info "Restarting Minecraft..."

    systemctl restart minecraft

    sleep 3

    if systemctl is-active --quiet minecraft; then
        success "Minecraft restarted"
    else
        error "Minecraft restart failed"
    fi

    pause_menu
}

# ============================================================
# STATUS
# ============================================================

status_server() {

    banner

    echo

    systemctl status minecraft --no-pager

    echo

    echo -e "${CYAN}Web Panel:${RESET}"

    systemctl status "$PANEL_SERVICE" --no-pager

    pause_menu
}

# ============================================================
# PINGGY START
# ============================================================

start_pinggy() {

    banner

    if ! systemctl is-active --quiet minecraft; then
        error "Minecraft server is offline"
        echo
        echo "Start Minecraft first."
        pause_menu
        return
    fi

    info "Starting Pinggy..."

    systemctl restart "$PINGGY_SERVICE"

    sleep 5

    if systemctl is-active --quiet "$PINGGY_SERVICE"; then
        success "Pinggy tunnel started"
    else
        error "Pinggy failed"
    fi

    echo
    journalctl -u "$PINGGY_SERVICE" -n 30 --no-pager

    pause_menu
}

# ============================================================
# STOP PINGGY
# ============================================================

stop_pinggy() {

    banner

    info "Stopping Pinggy..."

    systemctl stop "$PINGGY_SERVICE"

    success "Pinggy stopped"

    pause_menu
}

# ============================================================
# PUBLIC IP
# ============================================================

show_ip() {

    banner

    IP=$(curl -4 -fsSL https://api.ipify.org 2>/dev/null || true)

    echo

    if [ -n "$IP" ]; then

        echo -e "${GREEN}VPS IP:${RESET} $IP"

        echo
        echo "Minecraft:"
        echo "$IP:$MC_PORT"

        echo
        echo "Panel:"
        echo "http://$IP:$PANEL_PORT"

    else

        error "Could not detect public IP"

    fi

    pause_menu
}

# ============================================================
# BACKUP
# ============================================================

backup_server() {

    banner

    mkdir -p "$BASE/backups"

    DATE=$(date +"%Y-%m-%d_%H-%M-%S")
    FILE="$BASE/backups/minecraft-$DATE.tar.gz"

    info "Stopping Minecraft..."

    systemctl stop minecraft 2>/dev/null || true

    info "Creating backup..."

    tar \
        --exclude="$BASE/backups" \
        -czf "$FILE" \
        "$BASE"

    systemctl start minecraft 2>/dev/null || true

    echo

    success "Backup created"

    echo
    echo "$FILE"

    pause_menu
}

# ============================================================
# UNINSTALL
# ============================================================

uninstall_all() {

    banner

    echo -e "${RED}${BOLD}"
    echo "WARNING!"
    echo
    echo "This deletes Minecraft + Panel."
    echo "Worlds and plugins will also be deleted."
    echo -e "${RESET}"

    echo

    read -rp "Type DELETE: " CONFIRM

    if [ "$CONFIRM" != "DELETE" ]; then
        info "Cancelled"
        pause_menu
        return
    fi

    systemctl stop minecraft 2>/dev/null || true
    systemctl stop "$PANEL_SERVICE" 2>/dev/null || true
    systemctl stop "$PINGGY_SERVICE" 2>/dev/null || true

    systemctl disable minecraft 2>/dev/null || true
    systemctl disable "$PANEL_SERVICE" 2>/dev/null || true
    systemctl disable "$PINGGY_SERVICE" 2>/dev/null || true

    rm -f /etc/systemd/system/minecraft.service
    rm -f "/etc/systemd/system/${PANEL_SERVICE}.service"
    rm -f "/etc/systemd/system/${PINGGY_SERVICE}.service"

    systemctl daemon-reload

    rm -rf "$BASE"
    rm -rf "$PANEL_DIR"

    success "Minecraft removed"
    success "Panel removed"
    success "Pinggy service removed"

    pause_menu
}

# ============================================================
# MAIN MENU
# ============================================================

while true; do

    banner

    MC="${RED}OFFLINE${RESET}"
    PANEL="${RED}OFFLINE${RESET}"
    PINGGY="${RED}OFFLINE${RESET}"

    if systemctl is-active --quiet minecraft 2>/dev/null; then
        MC="${GREEN}ONLINE${RESET}"
    fi

    if systemctl is-active --quiet "$PANEL_SERVICE" 2>/dev/null; then
        PANEL="${GREEN}ONLINE${RESET}"
    fi

    if systemctl is-active --quiet "$PINGGY_SERVICE" 2>/dev/null; then
        PINGGY="${GREEN}ONLINE${RESET}"
    fi

    echo
    echo -e "Minecraft : $MC"
    echo -e "Panel     : $PANEL"
    echo -e "Pinggy    : $PINGGY"

    echo

    echo -e "${WHITE}╔════════════════════════════════════════════════╗${RESET}"
    echo -e "${WHITE}║                 KINGCLOUD MENU                 ║${RESET}"
    echo -e "${WHITE}╠════════════════════════════════════════════════╣${RESET}"
    echo -e "${WHITE}║ ${GREEN}1.${WHITE} Install Minecraft + Panel                    ║${RESET}"
    echo -e "${WHITE}║ ${GREEN}2.${WHITE} Start Minecraft                              ║${RESET}"
    echo -e "${WHITE}║ ${GREEN}3.${WHITE} Stop Minecraft                               ║${RESET}"
    echo -e "${WHITE}║ ${GREEN}4.${WHITE} Restart Minecraft                            ║${RESET}"
    echo -e "${WHITE}║ ${GREEN}5.${WHITE} Server Status                                ║${RESET}"
    echo -e "${WHITE}║ ${GREEN}6.${WHITE} Start Pinggy                                 ║${RESET}"
    echo -e "${WHITE}║ ${GREEN}7.${WHITE} Stop Pinggy                                  ║${RESET}"
    echo -e "${WHITE}║ ${GREEN}8.${WHITE} VPS IP + Panel URL                           ║${RESET}"
    echo -e "${WHITE}║ ${GREEN}9.${WHITE} Backup Server                                ║${RESET}"
    echo -e "${WHITE}║ ${RED}10.${WHITE} Uninstall                                   ║${RESET}"
    echo -e "${WHITE}║ ${RED}0.${WHITE} Exit                                        ║${RESET}"
    echo -e "${WHITE}╚════════════════════════════════════════════════╝${RESET}"

    echo

    read -rp "Select option: " OPTION

    case "$OPTION" in

        1)
            install_all
            ;;

        2)
            start_server
            ;;

        3)
            stop_server
            ;;

        4)
            restart_server
            ;;

        5)
            status_server
            ;;

        6)
            start_pinggy
            ;;

        7)
            stop_pinggy
            ;;

        8)
            show_ip
            ;;

        9)
            backup_server
            ;;

        10)
            uninstall_all
            ;;

        0)
            clear
            echo -e "${GREEN}KINGCLOUD closed.${RESET}"
            exit 0
            ;;

        *)
            error "Invalid option"
            sleep 1
            ;;

    esac

done
