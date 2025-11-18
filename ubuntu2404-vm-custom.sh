#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# License: MIT
# https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

source /dev/stdin <<<$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/api.func)

function header_info {
  clear
  cat <<"EOF"
   __  ____                __           ___  __ __   ____  __ __     _    ____  ___
  / / / / /_  __  ______  / /___  __   |__ \/ // /  / __ \/ // /    | |  / /  |/  /
 / / / / __ \/ / / / __ \/ __/ / / /   __/ / // /_ / / / / // /_    | | / / /|_/ /
/ /_/ / /_/ / /_/ / / / / /_/ /_/ /   / __/__  __// /_/ /__  __/    | |/ / /  / /
\____/_.___/\__,_/_/ /_/\__/\__,_/   /____/ /_/ (_)____/  /_/       |___/_/  /_/

EOF
}
header_info
echo -e "\n Loading..."
GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
METHOD=""
NSAPP="ubuntu-2404-vm"
var_os="ubuntu"
var_version="2404"

YW=$(echo "\033[33m")
BL=$(echo "\033[36m")
RD=$(echo "\033[01;31m")
BGN=$(echo "\033[4;92m")
GN=$(echo "\033[1;92m")
DGN=$(echo "\033[32m")
CL=$(echo "\033[m")

CL=$(echo "\033[m")
BOLD=$(echo "\033[1m")
BFR="\\r\\033[K"
HOLD=" "
TAB="  "

CM="${TAB}✔️${TAB}${CL}"
CROSS="${TAB}✖️${TAB}${CL}"
INFO="${TAB}💡${TAB}${CL}"
OS="${TAB}🖥️${TAB}${CL}"
CONTAINERTYPE="${TAB}📦${TAB}${CL}"
DISKSIZE="${TAB}💾${TAB}${CL}"
CPUCORE="${TAB}🧠${TAB}${CL}"
RAMSIZE="${TAB}🛠️${TAB}${CL}"
CONTAINERID="${TAB}🆔${TAB}${CL}"
HOSTNAME="${TAB}🏠${TAB}${CL}"
BRIDGE="${TAB}🌉${TAB}${CL}"
GATEWAY="${TAB}🌐${TAB}${CL}"
DEFAULT="${TAB}⚙️${TAB}${CL}"
MACADDRESS="${TAB}🔗${TAB}${CL}"
VLANTAG="${TAB}🏷️${TAB}${CL}"
CREATING="${TAB}🚀${TAB}${CL}"
ADVANCED="${TAB}🧩${TAB}${CL}"

THIN="discard=on,ssd=1,"
set -e
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
trap cleanup EXIT
trap 'post_update_to_api "failed" "INTERRUPTED"' SIGINT
trap 'post_update_to_api "failed" "TERMINATED"' SIGTERM
function error_handler() {
  local exit_code="$?"
  local line_number="$1"
  local command="$2"
  post_update_to_api "failed" "$command"
  local error_message="${RD}[ERROR]${CL} in line ${RD}$line_number${CL}: exit code ${RD}$exit_code${CL}: while executing command ${YW}$command${CL}"
  echo -e "\n$error_message\n"
  cleanup_vmid
}

function get_valid_nextid() {
  local try_id
  try_id=$(pvesh get /cluster/nextid)
  while true; do
    if [ -f "/etc/pve/qemu-server/${try_id}.conf" ] || [ -f "/etc/pve/lxc/${try_id}.conf" ]; then
      try_id=$((try_id + 1))
      continue
    fi
    if lvs --noheadings -o lv_name | grep -qE "(^|[-_])${try_id}($|[-_])"; then
      try_id=$((try_id + 1))
      continue
    fi
    break
  done
  echo "$try_id"
}

function cleanup_vmid() {
  if qm status $VMID &>/dev/null; then
    qm stop $VMID &>/dev/null
    qm destroy $VMID &>/dev/null
  fi
}

function cleanup() {
  popd >/dev/null
  rm -rf $TEMP_DIR
}

TEMP_DIR=$(mktemp -d)
pushd $TEMP_DIR >/dev/null
if whiptail --backtitle "Proxmox VE Helper Scripts" --title "Ubuntu 24.04 VM" --yesno "This will create a New Ubuntu 24.04 VM. Proceed?" 10 58; then
  :
else
  header_info && echo -e "${CROSS}${RD}User exited script${CL}\n" && exit
fi

function msg_info() {
  local msg="$1"
  echo -ne "${TAB}${YW}${HOLD}${msg}${HOLD}"
}

function msg_ok() {
  local msg="$1"
  echo -e "${BFR}${CM}${GN}${msg}${CL}"
}

function msg_error() {
  local msg="$1"
  echo -e "${BFR}${CROSS}${RD}${msg}${CL}"
}

function check_root() {
  if [[ "$(id -u)" -ne 0 || $(ps -o comm= -p $PPID) == "sudo" ]]; then
    clear
    msg_error "Please run this script as root."
    echo -e "\nExiting..."
    sleep 2
    exit
  fi
}

# This function checks the version of Proxmox Virtual Environment (PVE) and exits if the version is not supported.
# Supported: Proxmox VE 8.0.x – 8.9.x and 9.0 (NOT 9.1+)
pve_check() {
  local PVE_VER
  PVE_VER="$(pveversion | awk -F'/' '{print $2}' | awk -F'-' '{print $1}')"

  # Check for Proxmox VE 8.x: allow 8.0–8.9
  if [[ "$PVE_VER" =~ ^8\.([0-9]+) ]]; then
    local MINOR="${BASH_REMATCH[1]}"
    if ((MINOR < 0 || MINOR > 9)); then
      msg_error "This version of Proxmox VE is not supported."
      msg_error "Supported: Proxmox VE version 8.0 – 8.9"
      exit 1
    fi
    return 0
  fi

  # Check for Proxmox VE 9.x: allow ONLY 9.0
  if [[ "$PVE_VER" =~ ^9\.([0-9]+) ]]; then
    local MINOR="${BASH_REMATCH[1]}"
    if ((MINOR != 0)); then
      msg_error "This version of Proxmox VE is not yet supported."
      msg_error "Supported: Proxmox VE version 9.0"
      exit 1
    fi
    return 0
  fi

  # All other unsupported versions
  msg_error "This version of Proxmox VE is not supported."
  msg_error "Supported versions: Proxmox VE 8.0 – 8.x or 9.0"
  exit 1
}

function arch_check() {
  if [ "$(dpkg --print-architecture)" != "amd64" ]; then
    echo -e "\n ${INFO}${YWB}This script will not work with PiMox! \n"
    echo -e "\n ${YWB}Visit https://github.com/asylumexp/Proxmox for ARM64 support. \n"
    echo -e "Exiting..."
    sleep 2
    exit
  fi
}

function ssh_check() {
  if command -v pveversion >/dev/null 2>&1; then
    if [ -n "${SSH_CLIENT:+x}" ]; then
      if whiptail --backtitle "Proxmox VE Helper Scripts" --defaultno --title "SSH DETECTED" --yesno "It's suggested to use the Proxmox shell instead of SSH, since SSH can create issues while gathering variables. Would you like to proceed with using SSH?" 10 62; then
        echo "you've been warned"
      else
        clear
        exit
      fi
    fi
  fi
}

function exit-script() {
  clear
  echo -e "\n${CROSS}${RD}User exited script${CL}\n"
  exit
}

function default_settings() {
  VMID=$(get_valid_nextid)
  FORMAT=",efitype=4m"
  MACHINE=""
  DISK_SIZE="7G"
  DISK_CACHE=""
  HN="ubuntu"
  CPU_TYPE=""
  CORE_COUNT="2"
  RAM_SIZE="2048"
  BRG="vmbr0"
  MAC="$GEN_MAC"
  VLAN=""
  MTU=""
  START_VM="yes"
  METHOD="default"
  echo -e "${CONTAINERID}${BOLD}${DGN}Virtual Machine ID: ${BGN}${VMID}${CL}"
  echo -e "${CONTAINERTYPE}${BOLD}${DGN}Machine Type: ${BGN}i440fx${CL}"
  echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}${DISK_SIZE}${CL}"
  echo -e "${DISKSIZE}${BOLD}${DGN}Disk Cache: ${BGN}None${CL}"
  echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}${HN}${CL}"
  echo -e "${OS}${BOLD}${DGN}CPU Model: ${BGN}KVM64${CL}"
  echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}${CORE_COUNT}${CL}"
  echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}${RAM_SIZE}${CL}"
  echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}${BRG}${CL}"
  echo -e "${MACADDRESS}${BOLD}${DGN}MAC Address: ${BGN}${MAC}${CL}"
  echo -e "${VLANTAG}${BOLD}${DGN}VLAN: ${BGN}Default${CL}"
  echo -e "${DEFAULT}${BOLD}${DGN}Interface MTU Size: ${BGN}Default${CL}"
  echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}yes${CL}"
  echo -e "${CREATING}${BOLD}${DGN}Creating a Ubuntu 24.04 VM using the above default settings${CL}"
}

function advanced_settings() {
  METHOD="advanced"

  # Auto-set all values
  VMID=$(get_valid_nextid)
  FORMAT=",efitype=4m"
  MACHINE=""
  DISK_CACHE=""
  HN="ubuntu-$VMID"
  CPU_TYPE=" -cpu host"
  BRG="vmbr0"
  MAC="$GEN_MAC"
  VLAN=""
  MTU=""
  START_VM="yes"

  # Ask for Disk Size in GB
  if DISK_GB=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Disk Size in GB" 8 58 20 --title "DISK SIZE (GB)" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z "$DISK_GB" ]; then
      DISK_GB="20"
    fi
    DISK_SIZE="${DISK_GB}G"
    echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}$DISK_SIZE${CL}"
  else
    exit-script
  fi

  # Ask for CPU Cores
  if CORE_COUNT=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Allocate CPU Cores" 8 58 4 --title "CPU CORES" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z "$CORE_COUNT" ]; then
      CORE_COUNT="4"
    fi
    echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}$CORE_COUNT${CL}"
  else
    exit-script
  fi

  # Ask for RAM in GB
  if RAM_GB=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Allocate RAM in GB" 8 58 8 --title "RAM (GB)" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z "$RAM_GB" ]; then
      RAM_GB="8"
    fi
    RAM_SIZE=$((RAM_GB * 1024))
    echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}${RAM_GB}GB (${RAM_SIZE} MiB)${CL}"
  else
    exit-script
  fi

  # Ask for Root Login
  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "ROOT LOGIN" --yesno "Enable root login via SSH?" 10 58); then
    ENABLE_ROOT="yes"
    echo -e "${OS}${BOLD}${DGN}Root Login: ${BGN}Enabled${CL}"

    # Ask for root password
    while true; do
      if ROOT_PASS=$(whiptail --backtitle "Proxmox VE Helper Scripts" --passwordbox "Enter root password" 8 58 --title "ROOT PASSWORD" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
        if [ -z "$ROOT_PASS" ]; then
          whiptail --backtitle "Proxmox VE Helper Scripts" --title "ERROR" --msgbox "Password cannot be empty!" 8 58
          continue
        fi

        # Confirm password
        if ROOT_PASS_CONFIRM=$(whiptail --backtitle "Proxmox VE Helper Scripts" --passwordbox "Confirm root password" 8 58 --title "CONFIRM PASSWORD" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
          if [ "$ROOT_PASS" = "$ROOT_PASS_CONFIRM" ]; then
            echo -e "${OS}${BOLD}${DGN}Root Password: ${BGN}Set${CL}"
            break
          else
            whiptail --backtitle "Proxmox VE Helper Scripts" --title "ERROR" --msgbox "Passwords do not match! Try again." 8 58
          fi
        else
          exit-script
        fi
      else
        exit-script
      fi
    done
  else
    ENABLE_ROOT="no"
    ROOT_PASS=""
    echo -e "${OS}${BOLD}${DGN}Root Login: ${BGN}Disabled${CL}"
  fi

  # Display summary
  echo ""
  echo -e "${BOLD}${YW}════════════════════════════════════════════════${CL}"
  echo -e "${BOLD}${GN}        VM Configuration Summary${CL}"
  echo -e "${BOLD}${YW}════════════════════════════════════════════════${CL}"
  echo -e "${CONTAINERID}${BOLD}${DGN}VM ID:           ${BGN}$VMID${CL}"
  echo -e "${HOSTNAME}${BOLD}${DGN}Hostname:        ${BGN}$HN${CL}"
  echo -e "${CONTAINERTYPE}${BOLD}${DGN}Machine Type:    ${BGN}i440fx${CL}"
  echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size:       ${BGN}$DISK_SIZE${CL}"
  echo -e "${DISKSIZE}${BOLD}${DGN}Disk Cache:      ${BGN}None${CL}"
  echo -e "${OS}${BOLD}${DGN}CPU Model:       ${BGN}Host${CL}"
  echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores:       ${BGN}$CORE_COUNT${CL}"
  echo -e "${RAMSIZE}${BOLD}${DGN}RAM:             ${BGN}${RAM_GB}GB (${RAM_SIZE} MiB)${CL}"
  echo -e "${BRIDGE}${BOLD}${DGN}Bridge:          ${BGN}$BRG${CL}"
  echo -e "${MACADDRESS}${BOLD}${DGN}MAC Address:     ${BGN}$MAC${CL}"
  echo -e "${VLANTAG}${BOLD}${DGN}VLAN:            ${BGN}Default${CL}"
  echo -e "${DEFAULT}${BOLD}${DGN}MTU:             ${BGN}Default${CL}"
  echo -e "${GATEWAY}${BOLD}${DGN}Start on Create: ${BGN}yes${CL}"
  if [ "$ENABLE_ROOT" = "yes" ]; then
    echo -e "${OS}${BOLD}${DGN}Cloud-Init:      ${BGN}Enabled (DHCP + Root Login)${CL}"
  else
    echo -e "${OS}${BOLD}${DGN}Cloud-Init:      ${BGN}Enabled (DHCP only)${CL}"
  fi
  echo -e "${BOLD}${YW}════════════════════════════════════════════════${CL}"
  echo ""

  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "CONFIRM VM CREATION" --yesno "Ready to create Ubuntu 24.04 VM with the above settings?" --no-button Do-Over 16 70); then
    echo -e "${CREATING}${BOLD}${DGN}Creating Ubuntu 24.04 VM...${CL}"
  else
    header_info
    echo -e "${ADVANCED}${BOLD}${RD}Interactive VM Setup${CL}"
    advanced_settings
  fi
}

function start_script() {
  header_info
  echo -e "${ADVANCED}${BOLD}${RD}Interactive VM Setup${CL}"
  advanced_settings
}
check_root
arch_check
pve_check
ssh_check
start_script
post_to_api_vm

msg_info "Validating Storage"
while read -r line; do
  TAG=$(echo $line | awk '{print $1}')
  TYPE=$(echo $line | awk '{printf "%-10s", $2}')
  FREE=$(echo $line | numfmt --field 4-6 --from-unit=K --to=iec --format %.2f | awk '{printf( "%9sB", $6)}')
  ITEM="  Type: $TYPE Free: $FREE "
  OFFSET=2
  if [[ $((${#ITEM} + $OFFSET)) -gt ${MSG_MAX_LENGTH:-} ]]; then
    MSG_MAX_LENGTH=$((${#ITEM} + $OFFSET))
  fi
  STORAGE_MENU+=("$TAG" "$ITEM" "OFF")
done < <(pvesm status -content images | awk 'NR>1')
VALID=$(pvesm status -content images | awk 'NR>1')
if [ -z "$VALID" ]; then
  msg_error "Unable to detect a valid storage location."
  exit
elif [ $((${#STORAGE_MENU[@]} / 3)) -eq 1 ]; then
  STORAGE=${STORAGE_MENU[0]}
else
  while [ -z "${STORAGE:+x}" ]; do
    STORAGE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Storage Pools" --radiolist \
      "Which storage pool would you like to use for ${HN}?\nTo make a selection, use the Spacebar.\n" \
      16 $(($MSG_MAX_LENGTH + 23)) 6 \
      "${STORAGE_MENU[@]}" 3>&1 1>&2 2>&3)
  done
fi
msg_ok "Using ${CL}${BL}$STORAGE${CL} ${GN}for Storage Location."
msg_ok "Virtual Machine ID is ${CL}${BL}$VMID${CL}."
msg_info "Retrieving the URL for the Ubuntu 24.04 Disk Image"
URL=https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
sleep 2
msg_ok "${CL}${BL}${URL}${CL}"
curl -f#SL -o "$(basename "$URL")" "$URL"
echo -en "\e[1A\e[0K"
FILE=$(basename $URL)
msg_ok "Downloaded ${CL}${BL}${FILE}${CL}"

STORAGE_TYPE=$(pvesm status -storage $STORAGE | awk 'NR>1 {print $2}')
case $STORAGE_TYPE in
nfs | dir | cifs)
  DISK_EXT=".qcow2"
  DISK_REF="$VMID/"
  DISK_IMPORT="-format qcow2"
  THIN=""
  ;;
btrfs)
  DISK_EXT=".raw"
  DISK_REF="$VMID/"
  DISK_IMPORT="-format raw"
  FORMAT=",efitype=4m"
  THIN=""
  ;;
esac
for i in {0,1}; do
  disk="DISK$i"
  eval DISK${i}=vm-${VMID}-disk-${i}${DISK_EXT:-}
  eval DISK${i}_REF=${STORAGE}:${DISK_REF:-}${!disk}
done

msg_info "Creating a Ubuntu 24.04 VM"
qm create $VMID -agent 1${MACHINE} -tablet 0 -localtime 1 -bios ovmf${CPU_TYPE} -cores $CORE_COUNT -memory $RAM_SIZE \
  -name $HN -tags community-script -net0 virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU -onboot 1 -ostype l26 -scsihw virtio-scsi-pci
pvesm alloc $STORAGE $VMID $DISK0 4M 1>&/dev/null
qm importdisk $VMID ${FILE} $STORAGE ${DISK_IMPORT:-} 1>&/dev/null
qm set $VMID \
  -efidisk0 ${DISK0_REF}${FORMAT} \
  -scsi0 ${DISK1_REF},${DISK_CACHE}${THIN}size=${DISK_SIZE} \
  -ide2 ${STORAGE}:cloudinit \
  -boot order=scsi0 \
  -serial0 socket >/dev/null
DESCRIPTION=$(
  cat <<EOF
<div align='center'>
  <a href='https://Helper-Scripts.com' target='_blank' rel='noopener noreferrer'>
    <img src='https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/images/logo-81x112.png' alt='Logo' style='width:81px;height:112px;'/>
  </a>

  <h2 style='font-size: 24px; margin: 20px 0;'>ubuntu VM</h2>

  <p style='margin: 16px 0;'>
    <a href='https://ko-fi.com/community_scripts' target='_blank' rel='noopener noreferrer'>
      <img src='https://img.shields.io/badge/&#x2615;-Buy us a coffee-blue' alt='spend Coffee' />
    </a>
  </p>
  
  <span style='margin: 0 10px;'>
    <i class="fa fa-github fa-fw" style="color: #f5f5f5;"></i>
    <a href='https://github.com/community-scripts/ProxmoxVE' target='_blank' rel='noopener noreferrer' style='text-decoration: none; color: #00617f;'>GitHub</a>
  </span>
  <span style='margin: 0 10px;'>
    <i class="fa fa-comments fa-fw" style="color: #f5f5f5;"></i>
    <a href='https://github.com/community-scripts/ProxmoxVE/discussions' target='_blank' rel='noopener noreferrer' style='text-decoration: none; color: #00617f;'>Discussions</a>
  </span>
  <span style='margin: 0 10px;'>
    <i class="fa fa-exclamation-circle fa-fw" style="color: #f5f5f5;"></i>
    <a href='https://github.com/community-scripts/ProxmoxVE/issues' target='_blank' rel='noopener noreferrer' style='text-decoration: none; color: #00617f;'>Issues</a>
  </span>
</div>
EOF
)
qm set "$VMID" -description "$DESCRIPTION" >/dev/null
if [ -n "$DISK_SIZE" ]; then
  msg_info "Resizing disk to $DISK_SIZE GB"
  qm resize $VMID scsi0 ${DISK_SIZE} >/dev/null
else
  msg_info "Using default disk size of $DEFAULT_DISK_SIZE GB"
  qm resize $VMID scsi0 ${DEFAULT_DISK_SIZE} >/dev/null
fi

msg_ok "Created a Ubuntu 24.04 VM ${CL}${BL}(${HN})"

# Configure Cloud-Init
msg_info "Configuring Cloud-Init"
qm set $VMID --ipconfig0 ip=dhcp >/dev/null

if [ "$ENABLE_ROOT" = "yes" ]; then
  # Enable root login and set password
  HASHED_PASS=$(openssl passwd -6 "$ROOT_PASS")
  qm set $VMID --ciuser root --cipassword "$ROOT_PASS" >/dev/null
  qm set $VMID --sshkeys <(echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDummy") >/dev/null 2>&1 || true
  msg_ok "Cloud-Init configured ${CL}${BL}(DHCP + Root Login)${CL}"
else
  # DHCP only, no root login
  qm set $VMID --ciuser ubuntu --cipassword "$(openssl rand -base64 32)" >/dev/null
  msg_ok "Cloud-Init configured ${CL}${BL}(DHCP only)${CL}"
fi

if [ "$START_VM" == "yes" ]; then
  msg_info "Starting Ubuntu 24.04 VM"
  qm start $VMID
  msg_ok "Started Ubuntu 24.04 VM"
  echo -e "\n${INFO}${YW}VM is booting and getting IP via DHCP...${CL}"
  if [ "$ENABLE_ROOT" = "yes" ]; then
    echo -e "${INFO}${GN}You can login as 'root' with the password you set${CL}\n"
  else
    echo -e "${INFO}${YW}Root login is disabled. Use ubuntu user or configure SSH keys${CL}\n"
  fi
fi
post_update_to_api "done" "none"
msg_ok "Completed Successfully!\n"