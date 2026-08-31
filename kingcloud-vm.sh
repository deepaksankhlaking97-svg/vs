cat > kingcloud-vm.sh <<'BASH'
#!/usr/bin/env bash

# ==========================================================
#              KINGCLOUD VM MANAGER
#          SELF-HEALING / AUTO BUG FIX
# ==========================================================

set -Eeuo pipefail

# ==========================================================
# AUTO CRLF FIX
# ==========================================================

SELF="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"

if LC_ALL=C grep -q $'\r' "$SELF" 2>/dev/null; then
    echo "🔧 Windows CRLF detected."
    echo "🔧 Fixing script automatically..."

    TMP="${SELF}.lf"

    LC_ALL=C sed 's/\r$//' "$SELF" > "$TMP"
    chmod +x "$TMP"

    echo "✅ Script fixed."
    echo "🚀 Restarting..."

    exec bash "$TMP" "$@"
fi

# ==========================================================
# COLORS
# ==========================================================

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
MAGENTA='\033[1;35m'
RESET='\033[0m'

# ==========================================================
# PATHS
# ==========================================================

BASE="/var/lib/kingcloud"
VM_DIR="$BASE/vms"
IMAGE_DIR="$BASE/images"
CLOUD_DIR="$BASE/cloud-init"
LOG_DIR="/var/log/kingcloud"

UBUNTU_URL="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
UBUNTU_IMAGE="$IMAGE_DIR/ubuntu-22.04.qcow2"

mkdir -p "$VM_DIR" "$IMAGE_DIR" "$CLOUD_DIR" "$LOG_DIR"

# ==========================================================
# ROOT CHECK
# ==========================================================

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}❌ Run this script as root.${RESET}"
    exit 1
fi

# ==========================================================
# LOGGING
# ==========================================================

log() {
    printf '[%s] %s\n' "$(date '+%F %T')" "$*" >> "$LOG_DIR/manager.log"
}

die() {
    echo -e "${RED}❌ $*${RESET}"
    log "ERROR: $*"
    exit 1
}

# ==========================================================
# ERROR HANDLER
# ==========================================================

error_handler() {
    local line="$1"
    local code="$2"

    echo
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${RED}❌ Unexpected error${RESET}"
    echo -e "${YELLOW}Line:${RESET} $line"
    echo -e "${YELLOW}Exit code:${RESET} $code"
    echo -e "${YELLOW}Log:${RESET} $LOG_DIR/manager.log"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

    log "ERROR line=$line exit=$code"

    echo
    echo -e "${YELLOW}🔧 Running automatic repair...${RESET}"
    repair_system || true

    echo
    echo -e "${YELLOW}Press ENTER to return to menu.${RESET}"
    read -r || true
}

trap 'error_handler "$LINENO" "$?"' ERR

# ==========================================================
# BANNER
# ==========================================================

banner() {
    clear

    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║                                                          ║"
    echo "║                 👑 KINGCLOUD VM MANAGER                 ║"
    echo "║                                                          ║"
    echo "║              SELF-HEALING VM CONTROL PANEL              ║"
    echo "║                                                          ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
}

# ==========================================================
# COMMAND CHECK
# ==========================================================

has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

# ==========================================================
# PACKAGE INSTALL
# ==========================================================

install_packages() {

    export DEBIAN_FRONTEND=noninteractive

    echo -e "${YELLOW}📦 Installing required packages...${RESET}"

    apt-get update -y \
        >> "$LOG_DIR/apt.log" 2>&1

    local packages=(
        qemu-kvm
        qemu-utils
        libvirt-daemon-system
        libvirt-clients
        virtinst
        cloud-image-utils
        wget
        curl
        ca-certificates
        openssl
        jq
    )

    for package in "${packages[@]}"; do

        if dpkg-query -W -f='${Status}' "$package" 2>/dev/null |
            grep -q "install ok installed"; then

            echo -e "${GREEN}✔ $package${RESET}"

        else

            echo -e "${YELLOW}⬇ Installing $package...${RESET}"

            apt-get install -y "$package" \
                >> "$LOG_DIR/apt.log" 2>&1

            echo -e "${GREEN}✔ $package installed${RESET}"

        fi

    done
}

# ==========================================================
# SERVICE FIX
# ==========================================================

fix_services() {

    echo -e "${YELLOW}⚙️ Checking virtualization services...${RESET}"

    if has_cmd systemctl; then

        systemctl enable libvirtd \
            >> "$LOG_DIR/services.log" 2>&1 || true

        systemctl start libvirtd \
            >> "$LOG_DIR/services.log" 2>&1 || true

        systemctl enable virtlogd \
            >> "$LOG_DIR/services.log" 2>&1 || true

        systemctl start virtlogd \
            >> "$LOG_DIR/services.log" 2>&1 || true

    fi

    if has_cmd virsh; then

        virsh net-info default >/dev/null 2>&1 || {
            echo -e "${YELLOW}🌐 Fixing libvirt default network...${RESET}"

            virsh net-define /usr/share/libvirt/networks/default.xml \
                >> "$LOG_DIR/network.log" 2>&1 || true

            virsh net-autostart default \
                >> "$LOG_DIR/network.log" 2>&1 || true

            virsh net-start default \
                >> "$LOG_DIR/network.log" 2>&1 || true
        }

    fi
}

# ==========================================================
# SYSTEM REPAIR
# ==========================================================

repair_system() {

    echo -e "${CYAN}🛠 KINGCLOUD AUTO REPAIR${RESET}"
    echo

    mkdir -p "$VM_DIR" "$IMAGE_DIR" "$CLOUD_DIR" "$LOG_DIR"

    if ! has_cmd virsh ||
       ! has_cmd virt-install ||
       ! has_cmd cloud-localds; then

        install_packages
    fi

    fix_services

    if has_cmd virsh; then

        virsh version \
            >> "$LOG_DIR/manager.log" 2>&1 || true

    fi

    echo
    echo -e "${GREEN}✔ Automatic repair completed.${RESET}"

    log "AUTO REPAIR completed"
}

# ==========================================================
# UBUNTU IMAGE
# ==========================================================

download_image() {

    if [[ -f "$UBUNTU_IMAGE" ]]; then

        if qemu-img check "$UBUNTU_IMAGE" >/dev/null 2>&1; then
            echo -e "${GREEN}✔ Ubuntu 22.04 image ready.${RESET}"
            return
        fi

        echo -e "${YELLOW}⚠ Image appears invalid. Re-downloading...${RESET}"
        rm -f "$UBUNTU_IMAGE"
    fi

    echo
    echo -e "${CYAN}"
    echo "📥 Downloading Ubuntu 22.04 Cloud Image"
    echo -e "${RESET}"

    wget \
        -c \
        --progress=bar:force \
        -O "$UBUNTU_IMAGE.tmp" \
        "$UBUNTU_URL" \
        2>&1 | tee "$LOG_DIR/ubuntu-download.log"

    mv "$UBUNTU_IMAGE.tmp" "$UBUNTU_IMAGE"

    qemu-img info "$UBUNTU_IMAGE" \
        >> "$LOG_DIR/image.log" 2>&1

    echo
    echo -e "${GREEN}✔ Ubuntu image installed.${RESET}"
}

# ==========================================================
# FIRST-TIME SETUP
# ==========================================================

first_setup() {

    banner

    echo -e "${YELLOW}🔍 Checking KINGCLOUD environment...${RESET}"
    echo

    repair_system
    download_image

    echo
    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║              ✔ KINGCLOUD READY                          ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${RESET}"

    sleep 2
}

# ==========================================================
# VALIDATE INTEGER
# ==========================================================

ask_number() {

    local prompt="$1"
    local minimum="$2"
    local value

    while true; do

        read -rp "$prompt" value

        if [[ "$value" =~ ^[0-9]+$ ]] &&
           (( value >= minimum )); then

            echo "$value"
            return

        fi

        echo -e "${RED}❌ Invalid value. Minimum: $minimum${RESET}" >&2
    done
}

# ==========================================================
# VM NAME
# ==========================================================

ask_vm_name() {

    local name

    while true; do

        read -rp "🔹 VM Name: " name

        name="${name// /-}"

        if [[ ! "$name" =~ ^[a-zA-Z0-9_.-]+$ ]]; then
            echo -e "${RED}❌ Use only letters, numbers, -, _, .${RESET}"
            continue
        fi

        if virsh dominfo "$name" >/dev/null 2>&1; then
            echo -e "${RED}❌ VM already exists.${RESET}"
            continue
        fi

        echo "$name"
        return

    done
}

# ==========================================================
# CREATE VM
# ==========================================================

create_vm() {

    banner

    echo -e "${CYAN}"
    echo "⚙️  CONFIGURE YOUR VIRTUAL MACHINE SPECIFICATIONS"
    echo "=========================================================="
    echo -e "${RESET}"

    local VM_NAME
    local RAM_GB
    local CPU
    local DISK_GB
    local USERNAME
    local PASSWORD

    VM_NAME="$(ask_vm_name)"

    RAM_GB="$(ask_number \
        '🔹 Enter RAM Size in GB (e.g., 2, 4, 8, 16): ' 1)"

    CPU="$(ask_number \
        '🔹 Enter CPU Cores (e.g., 1, 2, 4, 8): ' 1)"

    DISK_GB="$(ask_number \
        '🔹 Enter Disk Space to ADD in GB (e.g., 10, 20, 50): ' 5)"

    read -rp \
        "🔹 Create Username (Default: root): " USERNAME

    USERNAME="${USERNAME:-root}"

    read -rsp \
        "🔹 Create Password (Default: root): " PASSWORD

    echo

    PASSWORD="${PASSWORD:-root}"

    echo
    echo -e "${CYAN}"
    echo "=========================================================="
    echo " VM NAME : $VM_NAME"
    echo " RAM     : ${RAM_GB} GB"
    echo " CPU     : ${CPU} CORE"
    echo " DISK    : ${DISK_GB} GB"
    echo " USER    : $USERNAME"
    echo "=========================================================="
    echo -e "${RESET}"

    read -rp "Continue? [y/N]: " confirm

    [[ "$confirm" =~ ^[Yy]$ ]] || return

    # ---------- AUTO REPAIR BEFORE CREATE ----------

    repair_system
    download_image

    local VM_DISK="$VM_DIR/$VM_NAME.qcow2"
    local CI_DIR="$CLOUD_DIR/$VM_NAME"
    local CLOUD_ISO="$CI_DIR/cloud-init.iso"

    mkdir -p "$CI_DIR"

    echo
    echo -e "${YELLOW}💾 Creating VM disk...${RESET}"

    cp --reflink=auto \
        "$UBUNTU_IMAGE" \
        "$VM_DISK"

    qemu-img resize \
        "$VM_DISK" \
        "${DISK_GB}G"

    echo -e "${GREEN}✔ Disk created.${RESET}"

    # ---------- CLOUD INIT ----------

    local HASH

    HASH="$(openssl passwd -6 "$PASSWORD")"

    cat > "$CI_DIR/user-data" <<EOF
#cloud-config

hostname: $VM_NAME

users:
  - name: $USERNAME
    groups:
      - sudo
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    passwd: $HASH

ssh_pwauth: true

chpasswd:
  expire: false

package_update: true

packages:
  - openssh-server

runcmd:
  - systemctl enable ssh
  - systemctl restart ssh
EOF

    cat > "$CI_DIR/meta-data" <<EOF
instance-id: $VM_NAME
local-hostname: $VM_NAME
EOF

    cat > "$CI_DIR/network-config" <<EOF
version: 2

ethernets:
  ens3:
    dhcp4: true
EOF

    cloud-localds \
        --network-config="$CI_DIR/network-config" \
        "$CLOUD_ISO" \
        "$CI_DIR/user-data" \
        "$CI_DIR/meta-data"

    echo -e "${GREEN}✔ Cloud-init ready.${RESET}"

    # ---------- CREATE VM ----------

    local MEMORY_MB=$((RAM_GB * 1024))

    echo
    echo -e "${YELLOW}🚀 Creating VM in background...${RESET}"

    (
        virt-install \
            --connect qemu:///system \
            --name "$VM_NAME" \
            --memory "$MEMORY_MB" \
            --vcpus "$CPU" \
            --cpu host \
            --disk "path=$VM_DISK,format=qcow2,bus=virtio" \
            --disk "path=$CLOUD_ISO,device=cdrom" \
            --os-variant ubuntu22.04 \
            --network network=default,model=virtio \
            --graphics none \
            --console pty,target_type=serial \
            --import \
            --noautoconsole

    ) > "$LOG_DIR/$VM_NAME-create.log" 2>&1 &

    local PID=$!

    local chars='|/-\'
    local i=0

    while kill -0 "$PID" 2>/dev/null; do

        printf "\r${CYAN}🚀 Installing VM ${chars:i++%4:1}${RESET}"

        sleep .2

    done

    if wait "$PID"; then

        echo
        echo -e "${GREEN}✔ VM created successfully.${RESET}"

    else

        echo
        echo -e "${RED}❌ VM creation failed.${RESET}"
        echo "Log: $LOG_DIR/$VM_NAME-create.log"

        repair_system

        return
    fi

    echo
    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║                 VM CREATED SUCCESSFULLY                 ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${RESET}"

    echo "Name     : $VM_NAME"
    echo "RAM      : ${RAM_GB}GB"
    echo "CPU      : $CPU"
    echo "Disk     : ${DISK_GB}GB"
    echo "Username : $USERNAME"
    echo "Password : $PASSWORD"

    echo
    echo -e "${YELLOW}💡 Start it from option 5.${RESET}"

    read -rp "Press ENTER..." _
}

# ==========================================================
# GET VM LIST
# ==========================================================

get_vms() {

    mapfile -t VMS < <(
        virsh list --all --name 2>/dev/null |
        sed '/^$/d'
    )
}

# ==========================================================
# LIST VMS
# ==========================================================

list_vms() {

    get_vms

    echo
    echo -e "${CYAN}"
    echo "================ KINGCLOUD VMS ================="
    echo -e "${RESET}"

    if (( ${#VMS[@]} == 0 )); then
        echo -e "${YELLOW}No VMs found.${RESET}"
        return
    fi

    local n=1

    for VM in "${VMS[@]}"; do

        local state

        state="$(virsh domstate "$VM" 2>/dev/null || echo unknown)"

        if [[ "$state" == "running" ]]; then
            echo -e "${GREEN}[$n]${RESET} $VM → ${GREEN}RUNNING${RESET}"
        else
            echo -e "${YELLOW}[$n]${RESET} $VM → ${RED}${state^^}${RESET}"
        fi

        ((n++))

    done
}

# ==========================================================
# SELECT VM
# ==========================================================

select_vm() {

    get_vms

    if (( ${#VMS[@]} == 0 )); then
        echo -e "${YELLOW}No VMs available.${RESET}"
        return 1
    fi

    list_vms

    local n

    echo
    read -rp "Select VM number: " n

    if ! [[ "$n" =~ ^[0-9]+$ ]] ||
       (( n < 1 || n > ${#VMS[@]} )); then

        echo -e "${RED}❌ Invalid selection.${RESET}"
        return 1
    fi

    SELECTED_VM="${VMS[$((n-1))]}"
}

# ==========================================================
# START VM
# ==========================================================

start_vm() {

    banner

    select_vm || {
        read -rp "Press ENTER..." _
        return
    }

    local state

    state="$(virsh domstate "$SELECTED_VM")"

    if [[ "$state" == "running" ]]; then

        echo -e "${YELLOW}⚠ $SELECTED_VM already running.${RESET}"

    else

        virsh start "$SELECTED_VM"

        echo -e "${GREEN}✔ $SELECTED_VM started.${RESET}"

    fi

    sleep 2

    echo
    echo -e "${CYAN}🌐 IP Address:${RESET}"

    virsh domifaddr "$SELECTED_VM" 2>/dev/null || \
        echo "IP not available yet."

    echo
    read -rp "Open console? [y/N]: " console

    if [[ "$console" =~ ^[Yy]$ ]]; then
        virsh console "$SELECTED_VM"
    fi
}

# ==========================================================
# RESTART ALL
# ==========================================================

restart_all() {

    banner

    get_vms

    if (( ${#VMS[@]} == 0 )); then
        echo -e "${YELLOW}No VMs found.${RESET}"
        read -rp "Press ENTER..." _
        return
    fi

    echo -e "${YELLOW}🔄 Restarting running VMs...${RESET}"

    for VM in "${VMS[@]}"; do

        local state

        state="$(virsh domstate "$VM" 2>/dev/null || true)"

        if [[ "$state" == "running" ]]; then

            echo "↻ $VM"

            virsh reboot "$VM" >/dev/null 2>&1 || {

                virsh destroy "$VM" >/dev/null 2>&1 || true
                virsh start "$VM" >/dev/null 2>&1 || true

            }

        fi

    done

    echo -e "${GREEN}✔ Restart operation complete.${RESET}"

    read -rp "Press ENTER..." _
}

# ==========================================================
# STOP ALL
# ==========================================================

stop_all() {

    banner

    get_vms

    if (( ${#VMS[@]} == 0 )); then
        echo -e "${YELLOW}No VMs found.${RESET}"
        read -rp "Press ENTER..." _
        return
    fi

    echo -e "${YELLOW}⏹ Stopping all running VMs...${RESET}"

    for VM in "${VMS[@]}"; do

        local state

        state="$(virsh domstate "$VM" 2>/dev/null || true)"

        if [[ "$state" == "running" ]]; then

            echo "⏹ $VM"

            virsh shutdown "$VM" >/dev/null 2>&1 || true

        fi

    done

    echo -e "${GREEN}✔ Stop commands sent.${RESET}"

    read -rp "Press ENTER..." _
}

# ==========================================================
# DELETE VM
# ==========================================================

delete_vm() {

    banner

    select_vm || {
        read -rp "Press ENTER..." _
        return
    }

    echo
    echo -e "${RED}⚠ WARNING${RESET}"
    echo -e "${RED}This permanently deletes: $SELECTED_VM${RESET}"
    echo

    read -rp "Type DELETE to confirm: " confirm

    [[ "$confirm" == "DELETE" ]] || {
        echo -e "${YELLOW}Cancelled.${RESET}"
        sleep 1
        return
    }

    echo -e "${YELLOW}🗑 Deleting $SELECTED_VM...${RESET}"

    virsh destroy "$SELECTED_VM" >/dev/null 2>&1 || true

    virsh undefine "$SELECTED_VM" --nvram >/dev/null 2>&1 || \
    virsh undefine "$SELECTED_VM" >/dev/null 2>&1 || true

    rm -f "$VM_DIR/$SELECTED_VM.qcow2"
    rm -rf "$CLOUD_DIR/$SELECTED_VM"

    echo -e "${GREEN}✔ VM deleted.${RESET}"

    read -rp "Press ENTER..." _
}

# ==========================================================
# VM INFORMATION
# ==========================================================

vm_info() {

    banner

    select_vm || {
        read -rp "Press ENTER..." _
        return
    }

    echo

    virsh dominfo "$SELECTED_VM"

    echo
    echo -e "${CYAN}🌐 Network:${RESET}"

    virsh domifaddr "$SELECTED_VM" 2>/dev/null || true

    echo
    read -rp "Press ENTER..." _
}

# ==========================================================
# LOG VIEWER
# ==========================================================

logs() {

    banner

    echo -e "${CYAN}📋 KINGCLOUD LOGS${RESET}"
    echo

    ls -lah "$LOG_DIR"

    echo
    echo "Latest manager log:"
    echo "------------------------------------------------"

    tail -n 40 "$LOG_DIR/manager.log" 2>/dev/null || true

    echo
    read -rp "Press ENTER..." _
}

# ==========================================================
# KVM CHECK
# ==========================================================

kvm_check() {

    banner

    echo -e "${CYAN}🔍 VIRTUALIZATION CHECK${RESET}"
    echo

    if [[ -e /dev/kvm ]]; then
        echo -e "${GREEN}✔ /dev/kvm available${RESET}"
    else
        echo -e "${RED}❌ /dev/kvm unavailable${RESET}"
        echo
        echo "This host may not expose hardware virtualization."
    fi

    echo

    if has_cmd virsh; then
        virsh version
    else
        echo -e "${RED}virsh not installed.${RESET}"
    fi

    echo

    read -rp "Press ENTER..." _
}

# ==========================================================
# MAIN MENU
# ==========================================================

menu() {

    while true; do

        banner

        echo -e "${WHITE}"
        echo "┌──────────────────────────────────────────────────────────┐"
        echo "│                    KINGCLOUD MENU                        │"
        echo "├──────────────────────────────────────────────────────────┤"
        echo "│  1  ➜  Install / Create New VM                         │"
        echo "│  2  ➜  Restart ALL VMs                                │"
        echo "│  3  ➜  Stop ALL VMs                                   │"
        echo "│  4  ➜  Delete VM                                      │"
        echo "│  5  ➜  Start VM / Open Console                        │"
        echo "│  6  ➜  List All VMs                                   │"
        echo "│  7  ➜  VM Information / IP                            │"
        echo "│  8  ➜  View Logs                                      │"
        echo "│  9  ➜  KVM / System Check                             │"
        echo "│ 10  ➜  AUTO REPAIR                                    │"
        echo "│  0  ➜  Exit                                            │"
        echo "└──────────────────────────────────────────────────────────┘"
        echo -e "${RESET}"

        echo
        read -rp "👑 KINGCLOUD > " OPTION

        case "$OPTION" in

            1) create_vm ;;
            2) restart_all ;;
            3) stop_all ;;
            4) delete_vm ;;
            5) start_vm ;;

            6)
                banner
                list_vms
                read -rp "Press ENTER..." _
                ;;

            7) vm_info ;;
            8) logs ;;
            9) kvm_check ;;

            10)
                banner
                repair_system
                read -rp "Press ENTER..." _
                ;;

            0)
                clear
                echo -e "${GREEN}👑 KINGCLOUD VM MANAGER CLOSED.${RESET}"
                exit 0
                ;;

            *)
                echo -e "${RED}❌ Invalid option.${RESET}"
                sleep 1
                ;;

        esac

    done
}

# ==========================================================
# BOOT
# ==========================================================

first_setup
menu

BASH

chmod +x kingcloud-vm.sh
bash kingcloud-vm.sh
