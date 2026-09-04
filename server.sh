#!/usr/bin/env bash
set -Eeuo pipefail

# ==========================================
# KINGCLOUD PANEL - FULL INSTALLER & MANAGER
# ==========================================

C_RESET="\e[0m"
C_BOLD="\e[1m"
C_RED="\e[31m"
C_GREEN="\e[32m"
C_YELLOW="\e[33m"
C_CYAN="\e[36m"
C_BRIGHT_CYAN="\e[96m"
C_BRIGHT_GREEN="\e[92m"
C_BRIGHT_RED="\e[91m"
C_BRIGHT_YELLOW="\e[93m"
C_BRIGHT_WHITE="\e[97m"

hide_cursor() { echo -ne "\e[?25l"; }
show_cursor() { echo -ne "\e[?25h"; }
trap 'show_cursor; echo -ne "${C_RESET}"; exit' INT TERM EXIT
clear_screen() { echo -ne "\e[2J\e[H"; }

run_with_spinner() {
    local cmd="$1" msg="$2"
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    echo -ne "${C_BRIGHT_CYAN}  ${msg} ${C_RESET}"
    eval "$cmd" > /dev/null 2>&1 &
    local pid=$!
    while kill -0 $pid 2>/dev/null; do
        local temp=${spinstr#?}
        printf "\r${C_BRIGHT_CYAN}  [%s] %s ${C_RESET}" "$spinstr" "$msg"
        spinstr=$temp${spinstr%"$temp"}
        sleep 0.08
    done
    wait $pid
    if [ $? -eq 0 ]; then printf "\r${C_BRIGHT_GREEN}  [✓] %s ${C_RESET}\n" "$msg"
    else printf "\r${C_BRIGHT_RED}  [✗] %s ${C_RESET}\n" "$msg"; fi
}

print_step() { echo -e "${C_BRIGHT_YELLOW}  ──[ ${C_BRIGHT_WHITE}${1}/${2}${C_BRIGHT_YELLOW} ] ${C_BOLD}${C_WHITE}${3}${C_RESET}"; }
print_success() { echo -e "  ${C_BRIGHT_GREEN}✓ ${1}${C_RESET}"; }
print_error() { echo -e "  ${C_BRIGHT_RED}✗ ${1}${C_RESET}"; }
print_info() { echo -e "  ${C_BRIGHT_CYAN}ℹ ${1}${C_RESET}"; }

clear_screen
echo -e "${C_BRIGHT_CYAN}"
cat << "EOF"
  _  __     _ _   _  __ _ _      _     _       ____ _                _           
 | |/ /   _| | | | |/ /(_) | ___| |__ | |     / ___| |__   ___  __ _| | __ _ _ __ 
 | ' / | | | | | | ' / | | |/ _ \ '_ \| |    | |   | '_ \ / _ \/ _` | |/ _` | '__|
 | . \ |_| | | | | . \ | | |  __/ |_) | | ___| |___| | | |  __/ (_| | | (_| | |   
 |_|\_\__,_|_|_| |_|\_\|_|_|\___|_.__/|_|(_)  \____|_| |_|\___|\__,_|_|\__,_|_|   
EOF
echo -e "${C_RESET}"
echo -e "${C_BRIGHT_CYAN}  ═══════════════════════════════════════════════════════════════════${C_RESET}"
echo -e "${C_BOLD}${C_WHITE}               KINGCLOUD PANEL - FULL INSTALLATION                ${C_RESET}"
echo -e "${C_BRIGHT_CYAN}  ═══════════════════════════════════════════════════════════════════${C_RESET}"
echo

if [ "$(id -u)" != "0" ]; then
    print_error "This script must be run as root."
    exit 1
fi

echo -ne "  ${C_BRIGHT_YELLOW}Enter Admin Username [admin]: ${C_RESET}"
read -r ADMIN_USER
ADMIN_USER=${ADMIN_USER:-admin}

echo -ne "  ${C_BRIGHT_YELLOW}Enter Admin Password: ${C_RESET}"
read -s ADMIN_PASS
echo
if [ -z "$ADMIN_PASS" ]; then print_error "Password cannot be empty."; exit 1; fi

echo -ne "  ${C_BRIGHT_YELLOW}Enter Panel Port [399]: ${C_RESET}"
read -r PANEL_PORT
PANEL_PORT=${PANEL_PORT:-399}

echo
print_step 1 5 "Installing System Dependencies"
run_with_spinner "apt update -qq" "Updating package lists"
run_with_spinner "apt install -y -qq python3 python3-flask sqlite3" "Installing Python & SQLite"

print_step 2 5 "Setting up Directories"
run_with_spinner "mkdir -p /opt/kingcloud-panel /opt/minecraft/servers" "Creating directories"

print_step 3 5 "Generating Panel Application"
cat << 'PYEOF' > /opt/kingcloud-panel/app.py
from flask import Flask, request, jsonify, session
import sqlite3, os, hashlib, secrets, subprocess, json, shutil, socket, struct
from functools import wraps

app = Flask(__name__)
app.secret_key = secrets.token_hex(32)
DB = '/opt/kingcloud-panel/panel.db'
BASE = '/opt/minecraft/servers'
PORT = REPLACE_PORT

def get_db():
    conn = sqlite3.connect(DB)
    conn.row_factory = sqlite3.Row
    return conn

def hash_pw(pw): return hashlib.sha256(pw.encode()).hexdigest()

def login_required(f):
    @wraps(f)
    def wrap(*args, **kwargs):
        if 'user_id' not in session: return jsonify({'error': 'Unauthorized'}), 401
        return f(*args, **kwargs)
    return wrap

def admin_required(f):
    @wraps(f)
    def wrap(*args, **kwargs):
        if 'user_id' not in session: return jsonify({'error': 'Unauthorized'}), 401
        conn = get_db()
        user = conn.execute('SELECT * FROM users WHERE id=?', (session['user_id'],)).fetchone()
        conn.close()
        if not user or user['role'] != 'admin': return jsonify({'error': 'Forbidden'}), 403
        return f(*args, **kwargs)
    return wrap

def check_server_access(sid):
    conn = get_db()
    user = conn.execute('SELECT * FROM users WHERE id=?', (session['user_id'],)).fetchone()
    server = conn.execute('SELECT * FROM servers WHERE id=?', (sid,)).fetchone()
    conn.close()
    if not server: return False, None
    if user['role'] != 'admin' and server['owner_id'] != user['id']: return False, None
    if server['suspended'] and user['role'] != 'admin': return False, None
    return True, server

def safe_path(base, path):
    abs_base = os.path.abspath(base)
    abs_path = os.path.abspath(os.path.join(base, path))
    return abs_path.startswith(abs_base)

def rcon_exec(host, port, pwd, cmd):
    try:
        s = socket.create_connection((host, port), timeout=5)
        def pkt(req, typ, text):
            body = struct.pack("<ii", req, typ) + text.encode() + b"\x00\x00"
            return struct.pack("<i", len(body)) + body
        def recv():
            raw = s.recv(4)
            if len(raw) != 4: raise Exception("Closed")
            size = struct.unpack("<i", raw)[0]
            data = b""
            while len(data) < size:
                part = s.recv(size - len(data))
                if not part: raise Exception("Closed")
                data += part
            return struct.unpack("<ii", data[:8]), data[8:-2].decode("utf-8", "replace")
        
        s.sendall(pkt(1, 3, pwd))
        (req, _), _ = recv()
        if req == -1: s.close(); return "Auth Failed"
        
        s.sendall(pkt(2, 2, cmd))
        out = []
        s.settimeout(1)
        while True:
            try:
                _, text = recv()
                if text: out.append(text)
            except: break
        s.close()
        return "".join(out).strip()
    except Exception as e:
        return f"RCON Error: {str(e)}"

HTML = """<!DOCTYPE html>
<html><head><title>KingCloud Panel</title>
<style>
* { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: 'Segoe UI', system-ui, sans-serif; background: #0f172a; color: #e2e8f0; height: 100vh; }
.layout { display: flex; height: 100vh; }
.sidebar { width: 250px; background: #1e293b; padding: 20px; display: flex; flex-direction: column; border-right: 1px solid #334155; }
.sidebar h2 { color: #38bdf8; margin-bottom: 30px; font-size: 20px; }
.nav-item { padding: 12px 15px; margin-bottom: 5px; border-radius: 8px; cursor: pointer; transition: 0.2s; color: #94a3b8; }
.nav-item:hover, .nav-item.active { background: #334155; color: #f8fafc; }
.content { flex: 1; padding: 30px; overflow-y: auto; }
.card { background: #1e293b; padding: 25px; border-radius: 12px; margin-bottom: 20px; border: 1px solid #334155; }
.btn { padding: 10px 20px; border: none; border-radius: 8px; cursor: pointer; font-weight: 600; transition: 0.2s; }
.btn-primary { background: #38bdf8; color: #0f172a; }
.btn-primary:hover { background: #0ea5e9; }
.btn-danger { background: #f87171; color: #0f172a; }
.btn-danger:hover { background: #ef4444; }
.btn-success { background: #4ade80; color: #0f172a; }
.btn-sm { padding: 6px 12px; font-size: 14px; }
input, select { padding: 10px; border-radius: 8px; border: 1px solid #334155; background: #0f172a; color: #f8fafc; width: 100%; margin-bottom: 15px; }
table { width: 100%; border-collapse: collapse; }
th, td { padding: 12px; text-align: left; border-bottom: 1px solid #334155; }
th { color: #94a3b8; font-weight: 600; }
.console-out { background: #020617; padding: 15px; border-radius: 8px; height: 300px; overflow-y: auto; font-family: monospace; color: #a3e635; white-space: pre-wrap; margin-bottom: 15px; border: 1px solid #334155; }
.file-item { padding: 10px; border-bottom: 1px solid #334155; cursor: pointer; display: flex; justify-content: space-between; }
.file-item:hover { background: #334155; }
.modal { position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.7); display: flex; align-items: center; justify-content: center; z-index: 100; }
.modal-content { background: #1e293b; padding: 30px; border-radius: 12px; width: 400px; border: 1px solid #334155; }
.tabs { display: flex; gap: 10px; margin-bottom: 20px; border-bottom: 1px solid #334155; padding-bottom: 10px; }
.tab { padding: 8px 16px; cursor: pointer; border-radius: 6px; color: #94a3b8; }
.tab.active { background: #334155; color: #f8fafc; }
.status-badge { padding: 4px 10px; border-radius: 20px; font-size: 12px; font-weight: bold; }
.status-running { background: #4ade80; color: #0f172a; }
.status-stopped { background: #f87171; color: #0f172a; }
.status-suspended { background: #fbbf24; color: #0f172a; }
</style>
</head><body>
<div id="app"></div>
<script>
const state = { user: null, view: 'login', adminTab: 'dashboard', serverId: null, serverTab: 'console', filesPath: '' };

async function api(url, opts = {}) {
    opts.headers = { 'Content-Type': 'application/json', ...opts.headers };
    if (opts.body && typeof opts.body === 'object') opts.body = JSON.stringify(opts.body);
    const res = await fetch(url, opts);
    if (res.status === 401) { state.user = null; state.view = 'login'; render(); throw new Error('Unauthorized'); }
    return res.json();
}

function render() {
    const app = document.getElementById('app');
    if (!state.user) { app.innerHTML = renderLogin(); attachEvents(); return; }
    
    let sidebar = `<div class="sidebar"><h2>⚡ KingCloud</h2>`;
    if (state.user.role === 'admin') {
        sidebar += `
            <div class="nav-item ${state.view==='dashboard'?'active':''}" onclick="nav('dashboard')">Dashboard</div>
            <div class="nav-item ${state.view==='users'?'active':''}" onclick="nav('users')">Users</div>
            <div class="nav-item ${state.view==='servers'?'active':''}" onclick="nav('servers')">Servers</div>
            <div class="nav-item ${state.view==='settings'?'active':''}" onclick="nav('settings')">Settings</div>
        `;
    } else {
        sidebar += `<div class="nav-item ${state.view==='dashboard'?'active':''}" onclick="nav('dashboard')">My Servers</div>`;
    }
    sidebar += `<div class="nav-item" onclick="logout()" style="margin-top:auto; color:#f87171;">Logout</div></div>`;
    
    let content = '';
    if (state.view === 'server') content = renderServerDetail();
    else if (state.user.role === 'admin') content = renderAdminContent();
    else content = renderUserContent();
    
    app.innerHTML = `<div class="layout">${sidebar}<main class="content">${content}</main></div>`;
    attachEvents();
}

function renderLogin() {
    return `<div style="display:flex;align-items:center;justify-content:center;height:100vh;">
        <div class="card" style="width:400px;">
            <h2 style="text-align:center;color:#38bdf8;margin-bottom:20px;">⚡ KingCloud Login</h2>
            <input type="text" id="login-user" placeholder="Username">
            <input type="password" id="login-pass" placeholder="Password">
            <button class="btn btn-primary" style="width:100%;" onclick="doLogin()">Login</button>
            <p id="login-err" style="color:#f87171;text-align:center;margin-top:10px;"></p>
        </div>
    </div>`;
}

function renderAdminContent() {
    if (state.view === 'users') {
        return `<div class="card"><h2>Users Management</h2><br>
            <button class="btn btn-primary" onclick="showCreateUser()">Create User</button><br><br>
            <table><tr><th>Username</th><th>Role</th><th>Status</th></tr><tbody id="users-tbl"></tbody></table></div>`;
    }
    if (state.view === 'servers') {
        return `<div class="card"><h2>Servers Management</h2><br>
            <button class="btn btn-primary" onclick="showCreateServer()">Create Server</button><br><br>
            <table><tr><th>Name</th><th>Owner</th><th>Port</th><th>RAM</th><th>Status</th><th>Actions</th></tr><tbody id="servers-tbl"></tbody></table></div>`;
    }
    if (state.view === 'settings') {
        return `<div class="card"><h2>Settings</h2><br>
            <p>Panel Version: 1.0.0</p>
            <p>Database: SQLite</p>
            <p>Servers Base: /opt/minecraft/servers</p>
            <br><button class="btn btn-primary" onclick="alert('Settings saved!')">Save Settings</button>
        </div>`;
    }
    return `<div class="card"><h2>Admin Dashboard</h2><br><p>Welcome to KingCloud Panel.</p></div>`;
}

function renderUserContent() {
    return `<div class="card"><h2>My Servers</h2><br>
        <table><tr><th>Name</th><th>Port</th><th>RAM</th><th>Status</th><th>Actions</th></tr><tbody id="my-servers-tbl"></tbody></table></div>`;
}

function renderServerDetail() {
    return `<div class="card">
        <h2 id="srv-name">Server</h2>
        <div class="tabs">
            <div class="tab ${state.serverTab==='console'?'active':''}" onclick="srvTab('console')">Console</div>
            <div class="tab ${state.serverTab==='files'?'active':''}" onclick="srvTab('files')">File Manager</div>
            <div class="tab ${state.serverTab==='status'?'active':''}" onclick="srvTab('status')">Status</div>
        </div>
        <div id="srv-content"></div>
    </div>`;
}

async function doLogin() {
    const u = document.getElementById('login-user').value;
    const p = document.getElementById('login-pass').value;
    try {
        const res = await api('/api/login', { method: 'POST', body: { username: u, password: p } });
        if (res.error) { document.getElementById('login-err').innerText = res.error; return; }
        state.user = res;
        state.view = 'dashboard';
        render();
    } catch(e) { document.getElementById('login-err').innerText = 'Login failed'; }
}

async function logout() { await api('/api/logout', { method: 'POST' }); state.user = null; state.view = 'login'; render(); }

function nav(v) { state.view = v; render(); }
function srvTab(t) { state.serverTab = t; render(); }

async function loadUsers() {
    const users = await api('/api/admin/users');
    const tbl = document.getElementById('users-tbl');
    if(!tbl) return;
    tbl.innerHTML = users.map(u => `<tr><td>${u.username}</td><td>${u.role}</td><td>${u.suspended?'Suspended':'Active'}</td></tr>`).join('');
}

async function loadServers() {
    const servers = await api('/api/admin/servers');
    const tbl = document.getElementById('servers-tbl');
    if(!tbl) return;
    tbl.innerHTML = servers.map(s => `<tr>
        <td><a href="#" onclick="openServer(${s.id})" style="color:#38bdf8;">${s.name}</a></td>
        <td>${s.owner_name}</td><td>${s.port}</td><td>${s.ram}GB</td>
        <td><span class="status-badge status-${s.suspended?'suspended':(s.status==='running'?'running':'stopped')}">${s.suspended?'Suspended':s.status}</span></td>
        <td>
            <button class="btn btn-sm ${s.suspended?'btn-success':'btn-danger'}" onclick="toggleSuspend(${s.id})">${s.suspended?'Unsuspend':'Suspend'}</button>
            <button class="btn btn-sm btn-danger" onclick="deleteServer(${s.id})">Delete</button>
        </td></tr>`).join('');
}

async function loadMyServers() {
    const servers = await api('/api/user/servers');
    const tbl = document.getElementById('my-servers-tbl');
    if(!tbl) return;
    tbl.innerHTML = servers.map(s => `<tr>
        <td><a href="#" onclick="openServer(${s.id})" style="color:#38bdf8;">${s.name}</a></td>
        <td>${s.port}</td><td>${s.ram}GB</td>
        <td><span class="status-badge status-${s.suspended?'suspended':(s.status==='running'?'running':'stopped')}">${s.suspended?'Suspended':s.status}</span></td>
        <td><button class="btn btn-sm btn-primary" onclick="openServer(${s.id})">Manage</button></td>
    </tr>`).join('');
}

async function openServer(id) { state.serverId = id; state.view = 'server'; state.serverTab = 'console'; render(); }

async function loadServerDetail() {
    const srv = await api(`/api/servers/${state.serverId}/status`);
    document.getElementById('srv-name').innerText = srv.name;
    const content = document.getElementById('srv-content');
    
    if (state.serverTab === 'console') {
        content.innerHTML = `<div class="console-out" id="console-out">Waiting for commands...</div>
            <div style="display:flex;gap:10px;">
                <input type="text" id="cmd-input" placeholder="Enter command..." style="margin:0;">
                <button class="btn btn-primary" onclick="sendCmd()">Send</button>
            </div>`;
    } else if (state.serverTab === 'files') {
        content.innerHTML = `<div id="files-list"></div>`;
        loadFiles('');
    } else if (state.serverTab === 'status') {
        content.innerHTML = `<p>Status: <span class="status-badge status-${srv.suspended?'suspended':(srv.status==='running'?'running':'stopped')}">${srv.suspended?'Suspended':srv.status}</span></p><br>
            <button class="btn btn-success" onclick="ctrlServer('start')">Start</button>
            <button class="btn btn-danger" onclick="ctrlServer('stop')">Stop</button>`;
    }
}

async function sendCmd() {
    const cmd = document.getElementById('cmd-input').value;
    if (!cmd) return;
    const out = document.getElementById('console-out');
    out.innerText += `\n> ${cmd}\n`;
    const res = await api(`/api/servers/${state.serverId}/console`, { method: 'POST', body: { cmd } });
    out.innerText += res.result + '\n';
    document.getElementById('cmd-input').value = '';
    out.scrollTop = out.scrollHeight;
}

async function ctrlServer(action) {
    await api(`/api/servers/${state.serverId}/${action}`, { method: 'POST' });
    loadServerDetail();
}

async function loadFiles(path) {
    state.filesPath = path;
    const files = await api(`/api/servers/${state.serverId}/files?path=${encodeURIComponent(path)}`);
    const list = document.getElementById('files-list');
    let html = path ? `<div class="file-item" onclick="loadFiles('${path.split('/').slice(0,-1).join('/')}')">.. (Back)</div>` : '';
    html += files.map(f => `<div class="file-item" onclick="${f.type==='dir'?`loadFiles('${path?path+'/':''}${f.name}')`:`editFile('${path?path+'/':''}${f.name}')`}">
        <span>${f.type==='dir'?'📁':'📄'} ${f.name}</span><span>${f.type==='file'?formatSize(f.size):''}</span></div>`).join('');
    list.innerHTML = html;
}

function formatSize(b) { if(b<1024) return b+'B'; if(b<1048576) return (b/1024).toFixed(1)+'KB'; return (b/1048576).toFixed(1)+'MB'; }

async function editFile(path) {
    const res = await api(`/api/servers/${state.serverId}/files/read?path=${encodeURIComponent(path)}`);
    const modal = document.createElement('div');
    modal.className = 'modal';
    modal.innerHTML = `<div class="modal-content" style="width:80%;height:80%;display:flex;flex-direction:column;">
        <h3 style="margin-bottom:15px;">${path}</h3>
        <textarea id="file-content" style="flex:1;background:#0f172a;color:#f8fafc;border:1px solid #334155;padding:10px;border-radius:8px;font-family:monospace;">${res.content}</textarea>
        <div style="margin-top:15px;display:flex;gap:10px;justify-content:flex-end;">
            <button class="btn btn-danger" onclick="this.closest('.modal').remove()">Cancel</button>
            <button class="btn btn-primary" onclick="saveFile('${path}')">Save</button>
        </div></div>`;
    document.body.appendChild(modal);
}

async function saveFile(path) {
    const content = document.getElementById('file-content').value;
    await api(`/api/servers/${state.serverId}/files/write?path=${encodeURIComponent(path)}`, { method: 'POST', body: { content } });
    document.querySelector('.modal').remove();
    loadFiles(state.filesPath);
}

function showCreateUser() {
    const modal = document.createElement('div');
    modal.className = 'modal';
    modal.innerHTML = `<div class="modal-content"><h3>Create User</h3><br>
        <input type="text" id="new-user" placeholder="Username">
        <input type="password" id="new-pass" placeholder="Password">
        <select id="new-role"><option value="user">User</option><option value="admin">Admin</option></select>
        <div style="display:flex;gap:10px;justify-content:flex-end;">
            <button class="btn btn-danger" onclick="this.closest('.modal').remove()">Cancel</button>
            <button class="btn btn-primary" onclick="createUser()">Create</button>
        </div></div>`;
    document.body.appendChild(modal);
}

async function createUser() {
    await api('/api/admin/users', { method: 'POST', body: {
        username: document.getElementById('new-user').value,
        password: document.getElementById('new-pass').value,
        role: document.getElementById('new-role').value
    }});
    document.querySelector('.modal').remove();
    loadUsers();
}

function showCreateServer() {
    const modal = document.createElement('div');
    modal.className = 'modal';
    modal.innerHTML = `<div class="modal-content"><h3>Create Server</h3><br>
        <input type="text" id="srv-name-input" placeholder="Server Name">
        <select id="srv-owner"></select>
        <input type="number" id="srv-ram" placeholder="RAM (GB)" value="2">
        <div style="display:flex;gap:10px;justify-content:flex-end;">
            <button class="btn btn-danger" onclick="this.closest('.modal').remove()">Cancel</button>
            <button class="btn btn-primary" onclick="createServer()">Create</button>
        </div></div>`;
    document.body.appendChild(modal);
    api('/api/admin/users').then(users => {
        document.getElementById('srv-owner').innerHTML = users.map(u => `<option value="${u.id}">${u.username}</option>`).join('');
    });
}

async function createServer() {
    await api('/api/admin/servers', { method: 'POST', body: {
        name: document.getElementById('srv-name-input').value,
        owner_id: parseInt(document.getElementById('srv-owner').value),
        ram: parseInt(document.getElementById('srv-ram').value)
    }});
    document.querySelector('.modal').remove();
    loadServers();
}

async function toggleSuspend(id) { await api(`/api/admin/servers/${id}/suspend`, { method: 'POST' }); loadServers(); }
async function deleteServer(id) { if(confirm('Delete this server?')) { await api(`/api/admin/servers/${id}`, { method: 'DELETE' }); loadServers(); } }

function attachEvents() {
    if (state.view === 'users') loadUsers();
    if (state.view === 'servers') loadServers();
    if (state.view === 'dashboard' && state.user.role !== 'admin') loadMyServers();
    if (state.view === 'server') loadServerDetail();
    
    const cmdInput = document.getElementById('cmd-input');
    if (cmdInput) cmdInput.addEventListener('keypress', e => { if (e.key === 'Enter') sendCmd(); });
}

api('/api/me').then(u => { if(u.username) { state.user = u; state.view = 'dashboard'; } render(); }).catch(() => render());
</script>
</body></html>"""

@app.route('/')
def index(): return HTML

@app.route('/api/login', methods=['POST'])
def login():
    data = request.json
    conn = get_db()
    user = conn.execute('SELECT * FROM users WHERE username=? AND password_hash=?', (data['username'], hash_pw(data['password']))).fetchone()
    conn.close()
    if not user: return jsonify({'error': 'Invalid credentials'}), 401
    session['user_id'] = user['id']
    return jsonify({'id': user['id'], 'username': user['username'], 'role': user['role']})

@app.route('/api/logout', methods=['POST'])
def logout(): session.clear(); return jsonify({'ok': True})

@app.route('/api/me')
def me():
    if 'user_id' not in session: return jsonify({'error': 'Unauthorized'}), 401
    conn = get_db()
    user = conn.execute('SELECT * FROM users WHERE id=?', (session['user_id'],)).fetchone()
    conn.close()
    return jsonify({'id': user['id'], 'username': user['username'], 'role': user['role']})

@app.route('/api/admin/users', methods=['GET', 'POST'])
@admin_required
def admin_users():
    conn = get_db()
    if request.method == 'POST':
        data = request.json
        conn.execute('INSERT INTO users (username, password_hash, role) VALUES (?, ?, ?)', 
                     (data['username'], hash_pw(data['password']), data.get('role', 'user')))
        conn.commit()
        conn.close()
        return jsonify({'ok': True})
    users = conn.execute('SELECT id, username, role, suspended FROM users').fetchall()
    conn.close()
    return jsonify([dict(u) for u in users])

@app.route('/api/admin/servers', methods=['GET', 'POST'])
@admin_required
def admin_servers():
    conn = get_db()
    if request.method == 'POST':
        data = request.json
        port = 25565
        while conn.execute('SELECT id FROM servers WHERE port=?', (port,)).fetchone(): port += 1
        rcon_port = port + 1000
        
        sid = secrets.token_hex(4)
        path = os.path.join(BASE, sid)
        os.makedirs(path, exist_ok=True)
        
        rcon_pass = secrets.token_urlsafe(16)
        with open(os.path.join(path, 'server.properties'), 'w') as f:
            f.write(f"server-port={port}\nenable-rcon=true\nrcon.port={rcon_port}\nrcon.password={rcon_pass}\n")
            
        service = f"""[Unit]\nDescription=MC Server {sid}\nAfter=network.target\n[Service]\nUser=root\nWorkingDirectory={path}\nExecStart=/usr/bin/java -Xmx{data['ram']}G -Xms{data['ram']}G -jar server.jar nogui\nRestart=on-failure\n[Install]\nWantedBy=multi-user.target\n"""
        with open(f"/etc/systemd/system/mc-server-{sid}.service", 'w') as f: f.write(service)
        subprocess.run(['systemctl', 'daemon-reload'])
        
        conn.execute('INSERT INTO servers (id, name, owner_id, port, rcon_port, ram, path) VALUES (?, ?, ?, ?, ?, ?, ?)',
                     (sid, data['name'], data['owner_id'], port, rcon_port, data['ram'], path))
        conn.commit()
        conn.close()
        return jsonify({'ok': True})
    
    servers = conn.execute('SELECT s.*, u.username as owner_name FROM servers s JOIN users u ON s.owner_id = u.id').fetchall()
    conn.close()
    res = []
    for s in servers:
        d = dict(s)
        d['status'] = 'running' if subprocess.run(['systemctl', 'is-active', f"mc-server-{s['id']}"], capture_output=True).returncode == 0 else 'stopped'
        res.append(d)
    return jsonify(res)

@app.route('/api/admin/servers/<sid>/suspend', methods=['POST'])
@admin_required
def suspend_server(sid):
    conn = get_db()
    s = conn.execute('SELECT * FROM servers WHERE id=?', (sid,)).fetchone()
    new_status = 0 if s['suspended'] else 1
    conn.execute('UPDATE servers SET suspended=? WHERE id=?', (new_status, sid))
    conn.commit()
    conn.close()
    if new_status == 1: subprocess.run(['systemctl', 'stop', f"mc-server-{sid}"])
    return jsonify({'ok': True})

@app.route('/api/admin/servers/<sid>', methods=['DELETE'])
@admin_required
def delete_server(sid):
    conn = get_db()
    s = conn.execute('SELECT * FROM servers WHERE id=?', (sid,)).fetchone()
    subprocess.run(['systemctl', 'stop', f"mc-server-{sid}"])
    subprocess.run(['systemctl', 'disable', f"mc-server-{sid}"])
    try: os.remove(f"/etc/systemd/system/mc-server-{sid}.service")
    except: pass
    subprocess.run(['systemctl', 'daemon-reload'])
    shutil.rmtree(s['path'], ignore_errors=True)
    conn.execute('DELETE FROM servers WHERE id=?', (sid,))
    conn.commit()
    conn.close()
    return jsonify({'ok': True})

@app.route('/api/user/servers')
@login_required
def user_servers():
    conn = get_db()
    user = conn.execute('SELECT * FROM users WHERE id=?', (session['user_id'],)).fetchone()
    if user['role'] == 'admin':
        servers = conn.execute('SELECT * FROM servers').fetchall()
    else:
        servers = conn.execute('SELECT * FROM servers WHERE owner_id=?', (session['user_id'],)).fetchall()
    conn.close()
    res = []
    for s in servers:
        d = dict(s)
        d['status'] = 'running' if subprocess.run(['systemctl', 'is-active', f"mc-server-{s['id']}"], capture_output=True).returncode == 0 else 'stopped'
        res.append(d)
    return jsonify(res)

@app.route('/api/servers/<sid>/status')
@login_required
def server_status(sid):
    ok, s = check_server_access(sid)
    if not ok: return jsonify({'error': 'Forbidden'}), 403
    d = dict(s)
    d['status'] = 'running' if subprocess.run(['systemctl', 'is-active', f"mc-server-{s['id']}"], capture_output=True).returncode == 0 else 'stopped'
    return jsonify(d)

@app.route('/api/servers/<sid>/start', methods=['POST'])
@login_required
def start_server(sid):
    ok, s = check_server_access(sid)
    if not ok: return jsonify({'error': 'Forbidden'}), 403
    subprocess.run(['systemctl', 'start', f"mc-server-{s['id']}"])
    return jsonify({'ok': True})

@app.route('/api/servers/<sid>/stop', methods=['POST'])
@login_required
def stop_server(sid):
    ok, s = check_server_access(sid)
    if not ok: return jsonify({'error': 'Forbidden'}), 403
    subprocess.run(['systemctl', 'stop', f"mc-server-{s['id']}"])
    return jsonify({'ok': True})

@app.route('/api/servers/<sid>/console', methods=['POST'])
@login_required
def server_console(sid):
    ok, s = check_server_access(sid)
    if not ok: return jsonify({'error': 'Forbidden'}), 403
    cmd = request.json.get('cmd', '')
    props = os.path.join(s['path'], 'server.properties')
    rcon_pass = ''
    if os.path.exists(props):
        with open(props) as f:
            for line in f:
                if line.startswith('rcon.password='): rcon_pass = line.split('=', 1)[1].strip()
    res = rcon_exec('127.0.0.1', s['rcon_port'], rcon_pass, cmd)
    return jsonify({'result': res})

@app.route('/api/servers/<sid>/files')
@login_required
def server_files(sid):
    ok, s = check_server_access(sid)
    if not ok: return jsonify({'error': 'Forbidden'}), 403
    path = request.args.get('path', '')
    full = os.path.join(s['path'], path)
    if not safe_path(s['path'], full): return jsonify({'error': 'Invalid path'}), 400
    items = []
    for f in os.listdir(full):
        fp = os.path.join(full, f)
        items.append({'name': f, 'type': 'dir' if os.path.isdir(fp) else 'file', 'size': os.path.getsize(fp) if os.path.isfile(fp) else 0})
    return jsonify(items)

@app.route('/api/servers/<sid>/files/read')
@login_required
def server_files_read(sid):
    ok, s = check_server_access(sid)
    if not ok: return jsonify({'error': 'Forbidden'}), 403
    path = request.args.get('path', '')
    full = os.path.join(s['path'], path)
    if not safe_path(s['path'], full): return jsonify({'error': 'Invalid path'}), 400
    with open(full, 'r', errors='ignore') as f: return jsonify({'content': f.read()})

@app.route('/api/servers/<sid>/files/write', methods=['POST'])
@login_required
def server_files_write(sid):
    ok, s = check_server_access(sid)
    if not ok: return jsonify({'error': 'Forbidden'}), 403
    path = request.args.get('path', '')
    full = os.path.join(s['path'], path)
    if not safe_path(s['path'], full): return jsonify({'error': 'Invalid path'}), 400
    with open(full, 'w') as f: f.write(request.json['content'])
    return jsonify({'ok': True})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=PORT, debug=False)
PYEOF

sed -i "s/REPLACE_PORT/$PANEL_PORT/g" /opt/kingcloud-panel/app.py
print_success "Panel application generated"

print_step 4 5 "Initializing Database"
python3 << PYINIT
import sqlite3, hashlib
conn = sqlite3.connect('/opt/kingcloud-panel/panel.db')
conn.execute('CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, username TEXT UNIQUE, password_hash TEXT, role TEXT, suspended INTEGER DEFAULT 0)')
conn.execute('CREATE TABLE IF NOT EXISTS servers (id TEXT PRIMARY KEY, name TEXT, owner_id INTEGER, port INTEGER, rcon_port INTEGER, ram INTEGER, path TEXT, suspended INTEGER DEFAULT 0)')
pw = hashlib.sha256('$ADMIN_PASS'.encode()).hexdigest()
try:
    conn.execute("INSERT INTO users (username, password_hash, role) VALUES (?, ?, 'admin')", ('$ADMIN_USER', pw))
    conn.commit()
except Exception as e:
    pass
conn.close()
PYINIT
print_success "Database initialized with admin user"

print_step 5 5 "Starting Panel Service"
cat << EOF > /etc/systemd/system/kingcloud-panel.service
[Unit]
Description=KingCloud Panel
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/kingcloud-panel
ExecStart=/usr/bin/python3 /opt/kingcloud-panel/app.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

run_with_spinner "systemctl daemon-reload" "Reloading systemd"
run_with_spinner "systemctl enable --now kingcloud-panel" "Starting panel service"

echo
echo -e "${C_BRIGHT_GREEN}  ═══════════════════════════════════════════════════════════════════${C_RESET}"
print_success "Installation Complete!"
echo
print_info "Panel URL:  ${C_BRIGHT_WHITE}http://<your-ip>:$PANEL_PORT${C_RESET}"
print_info "Username:   ${C_BRIGHT_WHITE}$ADMIN_USER${C_RESET}"
print_info "Password:   ${C_BRIGHT_WHITE}$ADMIN_PASS${C_RESET}"
echo
print_info "To manage the panel service:"
echo -e "    ${C_BRIGHT_CYAN}systemctl status kingcloud-panel${C_RESET}"
echo -e "    ${C_BRIGHT_CYAN}systemctl restart kingcloud-panel${C_RESET}"
echo -e "${C_BRIGHT_GREEN}  ═══════════════════════════════════════════════════════════════════${C_RESET}"
