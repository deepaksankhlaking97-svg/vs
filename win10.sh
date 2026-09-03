#!/usr/bin/env bash
# =====================================================================
#  KINGCLOUD — Cloud-PC / Code-Server Control Center
#  Docker • Multi Server • Windows Cloud-PC Management
# =====================================================================

set -uo pipefail

# ---------- colors ----------
PURPLE='\033[38;5;141m'
CYAN='\033[38;5;51m'
GREEN='\033[38;5;46m'
YELLOW='\033[38;5;220m'
RED='\033[38;5;203m'
GRAY='\033[38;5;245m'
BOLD='\033[1m'
NC='\033[0m'

# ---------- paths / config ----------
KC_HOME="$HOME/.kingcloud"
KC_LOGS="$KC_HOME/logs"
KC_PORTS="$KC_HOME/ports.txt"
LABEL="kingcloud=true"
DEFAULT_IMAGE="sankhlaking97/win10-ultra-lite"

mkdir -p "$KC_LOGS"
touch "$KC_PORTS"

# ---------- helpers ----------
need_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    echo -e "${RED}Docker nahi mila! Pehle Docker install karo.${NC}"
    exit 1
  fi
}

pause() { read -rp "$(echo -e "${GRAY}Enter dabao jari rakhne ke liye...${NC}")"; }

sanitize_name() {
  echo "$1" | tr -cd 'a-zA-Z0-9_.-' | tr 'A-Z' 'a-z'
}

port_free() {
  local p="$1"
  ! ss -tuln 2>/dev/null | grep -q ":$p " && ! docker ps -a --format '{{.Ports}}' | grep -q ":$p->"
}

next_free_port() {
  local start="$1"
  local p="$start"
  while ! port_free "$p"; do
    p=$((p + 1))
  done
  echo "$p"
}

count_status() {
  RUNNING=$(docker ps --filter "label=$LABEL" --format '{{.ID}}' | wc -l | tr -d ' ')
  TOTAL=$(docker ps -a --filter "label=$LABEL" --format '{{.ID}}' | wc -l | tr -d ' ')
  SUSPENDED=$(docker ps -a --filter "label=$LABEL" --filter "status=paused" --format '{{.ID}}' | wc -l | tr -d ' ')
}

banner() {
  clear
  echo -e "${PURPLE}${BOLD}"
  cat <<'EOF'
  ┌──────────────────────────────────────────────┐
  │   _  __ ___ _   _  ____                       │
  │  | |/ /|_ _| \ | |/ ___|                      │
  │  | ' /  | ||  \| | |  _                       │
  │  | . \  | || |\  | |_| |                      │
  │  |_|\_\|___|_| \_|\____|                      │
  └──────────────────────────────────────────────┘
EOF
  echo -e "${NC}"
  echo -e "        ${CYAN}CODE-SERVER / CLOUD-PC CONTROL CENTER${NC}"
  echo -e "              ${BOLD}${PURPLE}K I N G C L O U D${NC}"
  echo
  echo -e "${GRAY}Docker • Multi Server • Windows Cloud-PC Management${NC}"
  echo
  count_status
  echo -e "${GREEN}●${NC} Running    : ${RUNNING}"
  echo -e "${PURPLE}●${NC} Total      : ${TOTAL}"
  echo -e "${YELLOW}●${NC} Suspended  : ${SUSPENDED}"
  echo
  echo -e "${GRAY}------------------------------------------------${NC}"
  echo -e " ${GREEN}[1]${NC} 🚀 Install Cloud-PC / Code-Server"
  echo -e " ${CYAN}[2]${NC} 📋 List Servers"
  echo -e " ${CYAN}[3]${NC} 🔄 Restart All"
  echo -e " ${RED}[4]${NC} ⏹  Stop All"
  echo -e " ${GREEN}[5]${NC} ▶  Start All"
  echo -e " ${YELLOW}[6]${NC} ✨ Coming Soon"
  echo -e " ${RED}[7]${NC} 🗑  Delete Server"
  echo -e " ${YELLOW}[8]${NC} 🔒 Suspend Server"
  echo -e " ${YELLOW}[9]${NC} 🔓 Unsuspend Server"
  echo -e " ${CYAN}[10]${NC} ℹ  About & Features"
  echo
  echo -e "${GRAY}------------------------------------------------${NC}"
  echo -e " ${RED}[0]${NC} 🚪 Exit"
  echo
}

pick_container() {
  # prints a numbered list, returns chosen container name in $CHOSEN
  mapfile -t NAMES < <(docker ps -a --filter "label=$LABEL" --format '{{.Names}}')
  if [ "${#NAMES[@]}" -eq 0 ]; then
    echo -e "${RED}Koi server nahi mila.${NC}"
    CHOSEN=""
    return
  fi
  local i=1
  for n in "${NAMES[@]}"; do
    echo -e "  ${CYAN}[$i]${NC} $n"
    i=$((i + 1))
  done
  read -rp "Number chuno: " idx
  if [[ "$idx" =~ ^[0-9]+$ ]] && [ "$idx" -ge 1 ] && [ "$idx" -le "${#NAMES[@]}" ]; then
    CHOSEN="${NAMES[$((idx - 1))]}"
  else
    echo -e "${RED}Galat option.${NC}"
    CHOSEN=""
  fi
}

# ---------- [1] INSTALL ----------
install_server() {
  echo -e "${PURPLE}${BOLD}== Naya Cloud-PC Install ==${NC}"
  echo

  read -rp "Windows / PC ka naam [WinPC]: " win_name
  win_name=${win_name:-WinPC}

  read -rp "Container ka naam [auto]: " cname
  if [ -z "$cname" ]; then
    cname="kc-$(sanitize_name "$win_name")-$RANDOM"
  else
    cname=$(sanitize_name "$cname")
  fi

  if docker ps -a --format '{{.Names}}' | grep -qx "$cname"; then
    echo -e "${RED}Ye naam pehle se hai. Doosra naam try karo.${NC}"
    pause
    return
  fi

  read -rp "Windows/User ka username [admin]: " win_user
  win_user=${win_user:-admin}

  while true; do
    read -rsp "Password set karo: " win_pass
    echo
    read -rsp "Password dobara likho: " win_pass2
    echo
    if [ "$win_pass" == "$win_pass2" ] && [ -n "$win_pass" ]; then
      break
    fi
    echo -e "${RED}Password match nahi hua ya khaali hai, phir se try karo.${NC}"
  done

  read -rp "Web/VNC port (default 6080, forward karna hai) [6080]: " web_port
  web_port=${web_port:-6080}
  if ! port_free "$web_port"; then
    new_port=$(next_free_port "$web_port")
    echo -e "${YELLOW}Port $web_port busy hai, iske jagah $new_port use ho raha hai.${NC}"
    web_port="$new_port"
  fi

  rdp_port=$(next_free_port 3389)
  vnc_port=$(next_free_port 5900)

  read -rp "RAM kitna dena hai MB me [4096]: " ram
  ram=${ram:-4096}

  read -rp "CPU kitne core dene hain [2]: " cpu
  cpu=${cpu:-2}

  read -rp "Disk size [64G]: " disk
  disk=${disk:-64G}

  read -rp "Docker image [${DEFAULT_IMAGE}]: " image
  image=${image:-$DEFAULT_IMAGE}

  echo
  echo -e "${CYAN}---- Summary ----${NC}"
  echo -e "Naam        : $win_name  (container: $cname)"
  echo -e "User        : $win_user"
  echo -e "Web/VNC Port: $web_port"
  echo -e "RDP Port    : $rdp_port"
  echo -e "VNC Port    : $vnc_port"
  echo -e "RAM         : ${ram}MB"
  echo -e "CPU         : ${cpu} core"
  echo -e "Disk        : $disk"
  echo -e "Image       : $image"
  echo
  read -rp "Confirm install? (y/n) [y]: " ok
  ok=${ok:-y}
  if [[ "$ok" != "y" && "$ok" != "Y" ]]; then
    echo -e "${YELLOW}Cancel kar diya.${NC}"
    pause
    return
  fi

  logfile="$KC_LOGS/${cname}.log"

  echo -e "${GREEN}Background me install shuru ho raha hai...${NC}"

  (
    docker run -d \
      --name "$cname" \
      --restart unless-stopped \
      --device /dev/kvm:/dev/kvm \
      --cap-add NET_ADMIN \
      --label "$LABEL" \
      --label "kingcloud.display_name=$win_name" \
      --label "kingcloud.user=$win_user" \
      -p "${web_port}:6080" \
      -p "${vnc_port}:5900" \
      -p "${rdp_port}:3389" \
      -e VNC_PASSWORD="$win_pass" \
      -e USERNAME="$win_user" \
      -e PASSWORD="$win_pass" \
      -e RAM="${ram}" \
      -e CPU="${cpu}" \
      -e DISK="${disk}" \
      -v "${cname}_data:/data" \
      -v "${cname}_iso:/iso" \
      "$image" >"$logfile" 2>&1
  ) &
  bgpid=$!

  spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  i=0
  while kill -0 "$bgpid" 2>/dev/null; do
    i=$(((i + 1) % ${#spin}))
    printf "\r${CYAN}%s Installing '%s' ...${NC}" "${spin:$i:1}" "$win_name"
    sleep 0.15
  done
  wait "$bgpid"
  status=$?
  echo

  if [ "$status" -eq 0 ] && docker ps -a --format '{{.Names}}' | grep -qx "$cname"; then
    echo -e "${GREEN}'$win_name' ($cname) install ho gaya aur background me chal raha hai!${NC}"
    echo -e "Access URL   : http://<server-ip>:${web_port}"
    echo -e "RDP Port     : ${rdp_port}"
    echo -e "VNC Port     : ${vnc_port}"
    echo -e "Live logs    : docker logs -f $cname"
    echo -e "${GRAY}(Windows khud install hote rehna, iske andar time lagega — logs se progress dekho)${NC}"
  else
    echo -e "${RED}Install fail ho gaya. Log dekho: $logfile${NC}"
  fi
  pause
}

# ---------- [2] LIST ----------
list_servers() {
  echo -e "${CYAN}${BOLD}== Servers ==${NC}"
  printf "%-20s %-10s %-22s %-8s\n" "NAME" "STATUS" "DISPLAY-NAME" "USER"
  docker ps -a --filter "label=$LABEL" --format '{{.Names}}' | while read -r n; do
    st=$(docker inspect -f '{{.State.Status}}' "$n")
    dn=$(docker inspect -f '{{ index .Config.Labels "kingcloud.display_name" }}' "$n")
    us=$(docker inspect -f '{{ index .Config.Labels "kingcloud.user" }}' "$n")
    printf "%-20s %-10s %-22s %-8s\n" "$n" "$st" "$dn" "$us"
  done
  echo
  pause
}

# ---------- [3][4][5] BULK ----------
restart_all() {
  docker ps -a --filter "label=$LABEL" --format '{{.Names}}' | xargs -r -I{} docker restart {}
  echo -e "${GREEN}Sab servers restart ho gaye.${NC}"
  pause
}
stop_all() {
  docker ps --filter "label=$LABEL" --format '{{.Names}}' | xargs -r -I{} docker stop {}
  echo -e "${RED}Sab servers stop ho gaye.${NC}"
  pause
}
start_all() {
  docker ps -a --filter "label=$LABEL" --format '{{.Names}}' | xargs -r -I{} docker start {}
  echo -e "${GREEN}Sab servers start ho gaye.${NC}"
  pause
}

# ---------- [7] DELETE ----------
delete_server() {
  pick_container
  [ -z "${CHOSEN:-}" ] && { pause; return; }
  read -rp "Pakka delete karna hai '$CHOSEN'? (y/n) [n]: " c
  if [[ "$c" == "y" || "$c" == "Y" ]]; then
    docker rm -f "$CHOSEN" >/dev/null
    echo -e "${RED}'$CHOSEN' delete ho gaya.${NC}"
  fi
  pause
}

# ---------- [8] SUSPEND ----------
suspend_server() {
  pick_container
  [ -z "${CHOSEN:-}" ] && { pause; return; }
  docker pause "$CHOSEN" >/dev/null 2>&1 && echo -e "${YELLOW}'$CHOSEN' suspend ho gaya.${NC}"
  pause
}

# ---------- [9] UNSUSPEND ----------
unsuspend_server() {
  pick_container
  [ -z "${CHOSEN:-}" ] && { pause; return; }
  docker unpause "$CHOSEN" >/dev/null 2>&1 && echo -e "${GREEN}'$CHOSEN' unsuspend ho gaya.${NC}"
  pause
}

# ---------- [10] ABOUT ----------
about() {
  echo -e "${CYAN}${BOLD}== KingCloud About & Features ==${NC}"
  cat <<EOF
- Ek click me Windows Cloud-PC install (background me chalega)
- Har server ke liye alag naam, user, password
- Web/VNC port khud select ya default 6080
- RDP + VNC port auto assign (conflict-free)
- RAM / CPU / Disk default ke saath, chahe to badlo
- List / Restart / Stop / Start / Delete / Suspend / Unsuspend
- Data & ISO alag volume me save (data loss nahi hoga restart pe)
EOF
  pause
}

# ---------- MAIN ----------
need_docker
while true; do
  banner
  read -rp "Select option: " choice
  case "$choice" in
    1) install_server ;;
    2) list_servers ;;
    3) restart_all ;;
    4) stop_all ;;
    5) start_all ;;
    6) echo -e "${YELLOW}Ye feature jald aa raha hai!${NC}"; pause ;;
    7) delete_server ;;
    8) suspend_server ;;
    9) unsuspend_server ;;
    10) about ;;
    0) echo -e "${PURPLE}Bye! KingCloud band ho raha hai...${NC}"; exit 0 ;;
    *) echo -e "${RED}Galat option, phir se try karo.${NC}"; sleep 1 ;;
  esac
done
