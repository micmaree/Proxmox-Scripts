#!/usr/bin/env bash

# Custom Ubuntu 24.04 VM Creator - Modified for interactive setup
# Based on: https://github.com/community-scripts/ProxmoxVE

YW=$(echo "\033[33m")
BL=$(echo "\033[36m")
RD=$(echo "\033[01;31m")
BGN=$(echo "\033[4;92m")
GN=$(echo "\033[1;92m")
DGN=$(echo "\033[32m")
CL=$(echo "\033[m")
BOLD=$(echo "\033[1m")

function header_info {
  clear
  cat <<"EOF"
   _____           _                   _    ____  __   __   _    ____  ___
  / ____|         | |                 | |  | |  \/  | | |  | |  |  _ \|__ \
 | |    _   _ ___| |_ ___  _ __ ___  | |  | | \  / | | |  | |  | |_) |  ) |
 | |   | | | / __| __/ _ \| '_ ` _ \ | |  | | |\/| | | |  | |  |  _ <  / /
 | |___| |_| \__ \ || (_) | | | | | || |__| | |  | | |_|  |_|  | |_) |/ /_
  \_____\__,_|___/\__\___/|_| |_| |_(_)____/|_|  |_| (_)  (_)  |____/|____|

                    CUSTOM UBUNTU 24.04 VM CREATOR
EOF
}

function msg_info() {
  echo -e "${BL}[INFO]${CL} $1"
}

function msg_ok() {
  echo -e "${GN}[OK]${CL} $1"
}

function msg_error() {
  echo -e "${RD}[ERROR]${CL} $1"
}

function check_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    msg_error "Please run this script as root."
    exit 1
  fi
}

function get_valid_nextid() {
  local try_id
  try_id=$(pvesh get /cluster/nextid)
  while true; do
    if [ -f "/etc/pve/qemu-server/${try_id}.conf" ] || [ -f "/etc/pve/lxc/${try_id}.conf" ]; then
      try_id=$((try_id + 1))
      continue
    fi
    break
  done
  echo "$try_id"
}

function interactive_setup() {
  header_info
  echo ""

  # VM ID
  DEFAULT_VMID=$(get_valid_nextid)
  read -p "${YW}Enter VM ID${CL} [${GN}$DEFAULT_VMID${CL}]: " VMID
  VMID=${VMID:-$DEFAULT_VMID}
  msg_ok "VM ID: $VMID"

  # Hostname
  read -p "${YW}Enter Hostname${CL} [${GN}ubuntu${CL}]: " HN
  HN=${HN:-ubuntu}
  msg_ok "Hostname: $HN"

  # Disk Size
  read -p "${YW}Enter Disk Size in GB${CL} [${GN}20${CL}]: " DISK_SIZE_INPUT
  DISK_SIZE_INPUT=${DISK_SIZE_INPUT:-20}
  DISK_SIZE="${DISK_SIZE_INPUT}G"
  msg_ok "Disk Size: $DISK_SIZE"

  # CPU Cores
  read -p "${YW}Enter CPU Cores${CL} [${GN}4${CL}]: " CORE_COUNT
  CORE_COUNT=${CORE_COUNT:-4}
  msg_ok "CPU Cores: $CORE_COUNT"

  # RAM Size
  read -p "${YW}Enter RAM in GB${CL} [${GN}8${CL}]: " RAM_INPUT
  RAM_INPUT=${RAM_INPUT:-8}
  RAM_SIZE=$((RAM_INPUT * 1024))
  msg_ok "RAM: ${RAM_INPUT}GB ($RAM_SIZE MiB)"

  # CPU Type
  read -p "${YW}Use Host CPU type?${CL} [${GN}y${CL}/n]: " USE_HOST_CPU
  if [[ "$USE_HOST_CPU" =~ ^[Yy]$ ]] || [ -z "$USE_HOST_CPU" ]; then
    CPU_TYPE=" -cpu host"
    msg_ok "CPU Type: Host"
  else
    CPU_TYPE=""
    msg_ok "CPU Type: KVM64"
  fi

  # Network Bridge
  read -p "${YW}Enter Network Bridge${CL} [${GN}vmbr0${CL}]: " BRG
  BRG=${BRG:-vmbr0}
  msg_ok "Bridge: $BRG"

  # MAC Address
  GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
  read -p "${YW}Enter MAC Address${CL} [${GN}$GEN_MAC${CL}]: " MAC
  MAC=${MAC:-$GEN_MAC}
  msg_ok "MAC Address: $MAC"

  # VLAN
  read -p "${YW}Enter VLAN Tag (leave empty for none)${CL}: " VLAN1
  if [ -z "$VLAN1" ]; then
    VLAN=""
    msg_ok "VLAN: Default"
  else
    VLAN=",tag=$VLAN1"
    msg_ok "VLAN: $VLAN1"
  fi

  # Storage
  msg_info "Scanning available storage..."
  mapfile -t STORAGE_LIST < <(pvesm status -content images | awk 'NR>1 {print $1}')

  if [ ${#STORAGE_LIST[@]} -eq 0 ]; then
    msg_error "No storage available!"
    exit 1
  elif [ ${#STORAGE_LIST[@]} -eq 1 ]; then
    STORAGE=${STORAGE_LIST[0]}
    msg_ok "Storage: $STORAGE (only one available)"
  else
    echo ""
    echo "${YW}Available storage pools:${CL}"
    for i in "${!STORAGE_LIST[@]}"; do
      echo "  $((i+1))) ${STORAGE_LIST[$i]}"
    done
    read -p "${YW}Select storage (1-${#STORAGE_LIST[@]})${CL} [${GN}1${CL}]: " STORAGE_NUM
    STORAGE_NUM=${STORAGE_NUM:-1}
    STORAGE=${STORAGE_LIST[$((STORAGE_NUM-1))]}
    msg_ok "Storage: $STORAGE"
  fi

  # Start VM after creation
  read -p "${YW}Start VM after creation?${CL} [${GN}y${CL}/n]: " START_VM_INPUT
  if [[ "$START_VM_INPUT" =~ ^[Nn]$ ]]; then
    START_VM="no"
    msg_ok "Start VM: No"
  else
    START_VM="yes"
    msg_ok "Start VM: Yes"
  fi

  echo ""
  echo "${BGN}========================================${CL}"
  echo "${BOLD}VM Configuration Summary:${CL}"
  echo "  VM ID:      $VMID"
  echo "  Hostname:   $HN"
  echo "  Disk Size:  $DISK_SIZE"
  echo "  CPU Cores:  $CORE_COUNT"
  echo "  RAM:        ${RAM_INPUT}GB ($RAM_SIZE MiB)"
  echo "  Bridge:     $BRG"
  echo "  Storage:    $STORAGE"
  echo "  Start VM:   $START_VM"
  echo "${BGN}========================================${CL}"
  echo ""

  read -p "${YW}Proceed with VM creation?${CL} [${GN}y${CL}/n]: " CONFIRM
  if [[ ! "$CONFIRM" =~ ^[Yy]$ ]] && [ -n "$CONFIRM" ]; then
    msg_error "VM creation cancelled."
    exit 0
  fi
}

function create_vm() {
  msg_info "Downloading Ubuntu 24.04 Cloud Image..."
  URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  FILE="noble-server-cloudimg-amd64.img"

  if [ ! -f "$FILE" ]; then
    curl -f#SL -o "$FILE" "$URL"
    msg_ok "Downloaded $FILE"
  else
    msg_ok "Using existing $FILE"
  fi

  # Detect storage type
  STORAGE_TYPE=$(pvesm status -storage $STORAGE | awk 'NR>1 {print $2}')
  case $STORAGE_TYPE in
    nfs|dir|cifs)
      DISK_EXT=".qcow2"
      DISK_REF="$VMID/"
      DISK_IMPORT="-format qcow2"
      THIN=""
      FORMAT=",efitype=4m"
      ;;
    btrfs)
      DISK_EXT=".raw"
      DISK_REF="$VMID/"
      DISK_IMPORT="-format raw"
      THIN=""
      FORMAT=",efitype=4m"
      ;;
    *)
      DISK_EXT=""
      DISK_REF=""
      DISK_IMPORT=""
      THIN="discard=on,ssd=1,"
      FORMAT=",efitype=4m"
      ;;
  esac

  DISK0="vm-${VMID}-disk-0${DISK_EXT}"
  DISK1="vm-${VMID}-disk-1${DISK_EXT}"
  DISK0_REF="${STORAGE}:${DISK_REF}${DISK0}"
  DISK1_REF="${STORAGE}:${DISK_REF}${DISK1}"

  msg_info "Creating VM $VMID..."
  qm create $VMID \
    -agent 1 \
    -tablet 0 \
    -localtime 1 \
    -bios ovmf${CPU_TYPE} \
    -cores $CORE_COUNT \
    -memory $RAM_SIZE \
    -name $HN \
    -net0 virtio,bridge=$BRG,macaddr=$MAC$VLAN \
    -onboot 1 \
    -ostype l26 \
    -scsihw virtio-scsi-pci

  msg_ok "VM $VMID created"

  msg_info "Allocating EFI disk..."
  pvesm alloc $STORAGE $VMID $DISK0 4M 1>&/dev/null
  msg_ok "EFI disk allocated"

  msg_info "Importing disk image (this may take a while)..."
  qm importdisk $VMID ${FILE} $STORAGE ${DISK_IMPORT} 1>&/dev/null
  msg_ok "Disk imported"

  msg_info "Configuring VM disks..."
  qm set $VMID \
    -efidisk0 ${DISK0_REF}${FORMAT} \
    -scsi0 ${DISK1_REF},${THIN}size=${DISK_SIZE} \
    -ide2 ${STORAGE}:cloudinit \
    -boot order=scsi0 \
    -serial0 socket >/dev/null

  msg_ok "VM configured"

  if [ "$START_VM" == "yes" ]; then
    msg_info "Starting VM $VMID..."
    qm start $VMID
    msg_ok "VM $VMID started"
  fi

  echo ""
  echo "${GN}========================================${CL}"
  echo "${BOLD}${GN}VM Created Successfully!${CL}"
  echo "${GN}========================================${CL}"
  echo ""
  echo "${YW}IMPORTANT:${CL} Configure Cloud-Init before first use:"
  echo "  1. Go to Proxmox GUI → VM $VMID → Cloud-Init"
  echo "  2. Set user, password, SSH keys, network config"
  echo "  3. Regenerate image"
  echo ""
  echo "Access VM console: ${BL}qm terminal $VMID${CL}"
  echo ""
}

# Main execution
check_root
interactive_setup
create_vm
