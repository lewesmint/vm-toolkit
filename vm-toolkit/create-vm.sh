#!/bin/bash

# VM Creation Script
# Creates a new VM with cloud-init configuration

set -e

# If running as root via sudo, switch back to the original user
if [ "$EUID" -eq 0 ] && [ -n "$SUDO_USER" ]; then
  echo "[INFO] Detected sudo usage - switching back to user '$SUDO_USER' for VM creation"
  exec su "$SUDO_USER" -c "$(printf '%q ' "$0" "$@")"
fi

# Get script directory and load config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/vm-config.sh"
source "$SCRIPT_DIR/vm-registry.sh"

show_usage() {
  cat <<EOF
Usage: $0 <vm-name> [options]
   or: $0 --name <vm-name> [options]

Create a new VM with cloud-init configuration.

Required:
  <vm-name>             VM name (first argument)

Options:
  --hostname <name>     VM hostname (default: same as name)
  --username <name>     VM username (default: $(get_username))
  --password <pass>     VM user password (default: <username>-pw)
  --disk <size>         Disk size (default: $(get_disk_size))
  --ssh-key <path>      SSH public key (default: $(get_ssh_key))
  --os <os>             Operating system: ubuntu, debian, fedora, centos, k3s,
                        docker, minikube, rancher, talos (default: $(get_os))
  --version <version>   OS version (default: varies by OS)
  --arch <arch>         Architecture: x86_64, arm64, i386 (default: $(get_arch))
  --packages <list>     Comma-separated package list (default: $(get_packages))
  --run <command>       Command to run on first boot (can be used multiple times)
  --script <path>       Local script to copy and run on first boot
  --fresh               Generate new instance-id for reprovisioning
  --interactive         Prompt for common options interactively
  --debug               Show all command output and verbose logging
  --help                Show this help

Examples:
  $0 myvm
  $0 dev --username developer --password mypass123 --disk 100G
  $0 test --os debian --version 12 --packages "build-essential,docker.io"
  $0 k8s-cluster --os k3s --username admin
  $0 docker-host --os docker --disk 100G
  $0 arm-vm --arch arm64 --os ubuntu --username developer
  $0 debug-vm --debug --os ubuntu
EOF
}

# Parse command line arguments
VM_NAME=""
VM_HOSTNAME=""
VM_USERNAME=""
VM_PASSWORD=""
VM_DISK_SIZE=""
VM_SSH_KEY=""
VM_OS=""
VM_VERSION=""
VM_ARCH=""
VM_PACKAGES=""
VM_RUN_COMMANDS=()
VM_SCRIPTS=()
FRESH_INSTANCE=false
INTERACTIVE_MODE=false
DEBUG_MODE=false

# Debug logging functions
debug() {
  if [ "$DEBUG_MODE" = true ]; then
    echo -e "\033[0;35m[DEBUG]\033[0m $1" >&2
  fi
}

debug_cmd() {
  if [ "$DEBUG_MODE" = true ]; then
    echo -e "\033[0;35m[CMD]\033[0m $*" >&2
    "$@"
  else
    "$@" >/dev/null 2>&1
  fi
}

debug_cmd_output() {
  if [ "$DEBUG_MODE" = true ]; then
    echo -e "\033[0;35m[CMD]\033[0m $*" >&2
    "$@"
  else
    "$@"
  fi
}

# Check if first argument is a VM name (not an option)
if [[ $# -gt 0 && "$1" != --* ]]; then
  VM_NAME="$1"
  shift
fi

while [[ $# -gt 0 ]]; do
  case $1 in
  --name)
    if [ -n "$VM_NAME" ]; then
      error "VM name specified both as positional argument and --name option"
      exit 1
    fi
    VM_NAME="$2"
    shift 2
    ;;
  --hostname)
    VM_HOSTNAME="$2"
    shift 2
    ;;
  --username)
    VM_USERNAME="$2"
    shift 2
    ;;
  --password)
    VM_PASSWORD="$2"
    shift 2
    ;;
  --disk)
    VM_DISK_SIZE="$2"
    shift 2
    ;;
  --ssh-key)
    VM_SSH_KEY="$2"
    shift 2
    ;;
  --os)
    VM_OS="$2"
    shift 2
    ;;
  --version)
    VM_VERSION="$2"
    shift 2
    ;;
  --arch)
    VM_ARCH="$2"
    shift 2
    ;;
  --packages)
    VM_PACKAGES="$2"
    shift 2
    ;;
  --run)
    VM_RUN_COMMANDS+=("$2")
    shift 2
    ;;
  --script)
    if [ ! -f "$2" ]; then
      error "Script file not found: $2"
      exit 1
    fi
    VM_SCRIPTS+=("$2")
    shift 2
    ;;
  --fresh)
    FRESH_INSTANCE=true
    shift
    ;;
  --interactive)
    INTERACTIVE_MODE=true
    shift
    ;;
  --debug)
    DEBUG_MODE=true
    shift
    ;;
  --help)
    show_usage
    exit 0
    ;;
  --*)
    error "Unknown option: $1"
    show_usage
    exit 1
    ;;
  *)
    error "Unknown argument: $1"
    show_usage
    exit 1
    ;;
  esac
done

# Validate required arguments
if [ -z "$VM_NAME" ]; then
  error "VM name is required as first argument"
  show_usage
  exit 1
fi

# Set architecture default early for dependency checking
VM_ARCH="${VM_ARCH:-$(get_arch)}"

# Check dependencies first
check_dependencies "$VM_ARCH"

# Validate VM name for security
validate_vm_name "$VM_NAME"

# Interactive mode - prompt for options
if [ "$INTERACTIVE_MODE" = true ]; then
  echo "🚀 Interactive VM Creation"
  echo "=========================="
  echo

  # Prompt for username
  if [ -z "$VM_USERNAME" ]; then
    read -p "Username [$(get_username)]: " VM_USERNAME
    VM_USERNAME="${VM_USERNAME:-$(get_username)}"
  fi

  # Prompt for OS
  if [ -z "$VM_OS" ]; then
    echo "Available OS options:"
    echo "  1) ubuntu (default) - Ubuntu 24.04 LTS"
    echo "  2) debian - Debian 12"
    echo "  3) fedora - Fedora 39"
    echo "  4) centos - CentOS 9 Stream"
    echo "  5) k3s - Ubuntu with Kubernetes"
    echo "  6) docker - Ubuntu with Docker"
    echo "  7) minikube - Ubuntu with Minikube"
    read -p "Choose OS [1]: " os_choice
    case "${os_choice:-1}" in
      1) VM_OS="ubuntu" ;;
      2) VM_OS="debian" ;;
      3) VM_OS="fedora" ;;
      4) VM_OS="centos" ;;
      5) VM_OS="k3s" ;;
      6) VM_OS="docker" ;;
      7) VM_OS="minikube" ;;
      *) VM_OS="ubuntu" ;;
    esac
  fi

  # Prompt for disk size
  if [ -z "$VM_DISK_SIZE" ]; then
    read -p "Disk size [$(get_disk_size)]: " VM_DISK_SIZE
    VM_DISK_SIZE="${VM_DISK_SIZE:-$(get_disk_size)}"
  fi

  # Prompt for packages (if not a specialized OS)
  if [ -z "$VM_PACKAGES" ] && [[ "$VM_OS" =~ ^(ubuntu|debian|fedora|centos)$ ]]; then
    echo "Common package suggestions:"
    echo "  - Development: git,vim,build-essential,curl,wget"
    echo "  - Docker: docker.io,docker-compose"
    echo "  - Web: nginx,postgresql,redis"
    read -p "Additional packages (comma-separated) [none]: " VM_PACKAGES
  fi

  # Prompt for startup commands
  if [ ${#VM_RUN_COMMANDS[@]} -eq 0 ]; then
    echo "Startup commands (run on first boot):"
    echo "  Examples: 'systemctl enable myservice', 'docker run -d nginx'"
    while true; do
      read -p "Add startup command (or press Enter to skip): " run_cmd
      if [ -z "$run_cmd" ]; then
        break
      fi
      VM_RUN_COMMANDS+=("$run_cmd")
    done
  fi

  echo
  echo "📋 Configuration Summary:"
  echo "  VM Name: $VM_NAME"
  echo "  Username: ${VM_USERNAME:-$(get_username)}"
  echo "  OS: ${VM_OS:-$(get_os)}"
  echo "  Disk: ${VM_DISK_SIZE:-$(get_disk_size)}"
  echo "  Packages: ${VM_PACKAGES:-none}"
  if [ ${#VM_RUN_COMMANDS[@]} -gt 0 ]; then
    echo "  Startup commands:"
    for cmd in "${VM_RUN_COMMANDS[@]}"; do
      echo "    - $cmd"
    done
  fi
  if [ ${#VM_SCRIPTS[@]} -gt 0 ]; then
    echo "  Startup scripts:"
    for script in "${VM_SCRIPTS[@]}"; do
      echo "    - $(basename "$script")"
    done
  fi
  echo
  read -p "Proceed with creation? [Y/n]: " confirm
  if [[ "$confirm" =~ ^[Nn] ]]; then
    echo "VM creation cancelled."
    exit 0
  fi
  echo
fi

# Set defaults for optional arguments
VM_HOSTNAME="${VM_HOSTNAME:-$VM_NAME}"
VM_USERNAME="${VM_USERNAME:-$(get_username)}"
VM_PASSWORD="${VM_PASSWORD:-$VM_USERNAME-pw}"
VM_DISK_SIZE="${VM_DISK_SIZE:-$(get_disk_size)}"
VM_ARCH="${VM_ARCH:-$(get_arch)}"
VM_SSH_KEY="${VM_SSH_KEY:-$(get_ssh_key)}"
VM_OS="${VM_OS:-$(get_os)}"
VM_PACKAGES="${VM_PACKAGES:-$(get_packages)}"

# Set OS-specific version defaults
case "$VM_OS" in
"ubuntu")
  VM_VERSION="${VM_VERSION:-$(get_ubuntu_version)}"
  ;;
"debian")
  VM_VERSION="${VM_VERSION:-$(get_debian_version)}"
  ;;
"fedora")
  VM_VERSION="${VM_VERSION:-$(get_fedora_version)}"
  ;;
"centos")
  VM_VERSION="${VM_VERSION:-$(get_centos_version)}"
  ;;
"k3s")
  VM_VERSION="${VM_VERSION:-$(get_k3s_version)}"
  VM_PACKAGES="${VM_PACKAGES:-openssh-server,qemu-guest-agent,curl,wget,vim,\\
docker.io}"
  ;;
"docker")
  VM_VERSION="${VM_VERSION:-$(get_docker_version)}"
  VM_PACKAGES="${VM_PACKAGES:-openssh-server,qemu-guest-agent,curl,wget,vim,\\
docker.io,docker-compose}"
  ;;
"minikube")
  VM_VERSION="${VM_VERSION:-latest}"
  VM_PACKAGES="${VM_PACKAGES:-openssh-server,qemu-guest-agent,curl,wget,vim,docker.io}"
  ;;
"rancher")
  VM_VERSION="${VM_VERSION:-$(get_rancher_version)}"
  VM_PACKAGES="${VM_PACKAGES:-openssh-server}"
  ;;
"talos")
  VM_VERSION="${VM_VERSION:-$(get_talos_version)}"
  VM_PACKAGES="${VM_PACKAGES:-}" # Talos is immutable
  ;;
*)
  error "Unsupported OS: $VM_OS"
  error "Supported: ubuntu, debian, fedora, centos, k3s, docker, \\
minikube, rancher, talos"
  exit 1
  ;;
esac

# Enable debug mode settings
if [ "$DEBUG_MODE" = true ]; then
  debug "Debug mode enabled - showing all command output"
  set -x # Show all commands
fi

# Validate SSH key exists
if [ ! -f "$VM_SSH_KEY" ]; then
  error "SSH key not found: $VM_SSH_KEY"
  error "Generate one with: ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519"
  exit 1
fi

# Check if VM already exists using secure path function
VM_DIR=$(get_vm_dir "$VM_NAME")
if [ -d "$VM_DIR" ]; then
  error "VM '$VM_NAME' already exists"
  exit 1
fi

log "Creating VM: $VM_NAME"
log "Configuration:"
log "  - Hostname: $VM_HOSTNAME"
log "  - Username: $VM_USERNAME"
log "  - Disk size: $VM_DISK_SIZE"
log "  - OS: $VM_OS $VM_VERSION"
log "  - SSH key: $VM_SSH_KEY"
debug "  - Debug mode: $DEBUG_MODE"
debug "  - Fresh instance: $FRESH_INSTANCE"
debug "  - Packages: $VM_PACKAGES"

# Ensure VM base directory exists
ensure_vm_base_dir

# Create VM directory (VM_DIR already set securely above)
debug "Creating VM directory: $VM_DIR"
debug_cmd mkdir -p "$VM_DIR/cloud-init"
debug "Changing to VM directory"
cd "$VM_DIR"

# Handle cloud image download or custom build
CLOUD_IMAGE_FILE="$(get_cloud_image_filename "$VM_OS" "$VM_VERSION" "$VM_ARCH")"
CLOUD_IMAGE_URL="$(get_cloud_image_url "$VM_OS" "$VM_VERSION" "$VM_ARCH")"
CACHED_IMAGE="$CLOUD_IMAGE_CACHE/$CLOUD_IMAGE_FILE"

if [[ "$CLOUD_IMAGE_URL" == custom-build:* ]]; then
  # Custom build from Ubuntu base for k3s, docker, minikube
  BASE_OS="ubuntu"
  BASE_VERSION="$(get_ubuntu_version)"
  BASE_IMAGE_FILE="$(get_cloud_image_filename "$BASE_OS" "$BASE_VERSION" "$VM_ARCH")"
  BASE_IMAGE_URL="$(get_cloud_image_url "$BASE_OS" "$BASE_VERSION" "$VM_ARCH")"
  BASE_CACHED_IMAGE="$CLOUD_IMAGE_CACHE/$BASE_IMAGE_FILE"

  # Download Ubuntu base if needed
  if [ ! -f "$BASE_CACHED_IMAGE" ]; then
    step "Downloading Ubuntu base image for $VM_OS..."
    debug "Base image URL: $BASE_IMAGE_URL"
    debug_cmd mkdir -p "$CLOUD_IMAGE_CACHE"
    debug_cmd_output curl -L -o "$BASE_CACHED_IMAGE.tmp" "$BASE_IMAGE_URL"
    debug_cmd mv "$BASE_CACHED_IMAGE.tmp" "$BASE_CACHED_IMAGE"
    log "Downloaded base: $BASE_CACHED_IMAGE"
  else
    debug "Using existing base image: $BASE_CACHED_IMAGE"
  fi

  # Use Ubuntu base as our "cloud image"
  CACHED_IMAGE="$BASE_CACHED_IMAGE"
  log "Using Ubuntu base for $VM_OS build: $CACHED_IMAGE"

elif [ ! -f "$CACHED_IMAGE" ]; then
  step "Downloading $VM_OS $VM_VERSION cloud image..."
  debug "Cloud image URL: $CLOUD_IMAGE_URL"
  debug_cmd mkdir -p "$CLOUD_IMAGE_CACHE"

  # Use secure temp file for download
  temp_file=$(create_secure_temp "vm-image")
  debug_cmd_output curl -L -o "$temp_file" "$CLOUD_IMAGE_URL"
  debug_cmd mv "$temp_file" "$CACHED_IMAGE"
  log "Downloaded: $CACHED_IMAGE"
else
  log "Using cached cloud image: $CACHED_IMAGE"
  debug "Cached image path: $CACHED_IMAGE"
fi

# Copy cloud image as base
debug "Copying cloud image as base"
debug_cmd cp "$CACHED_IMAGE" "${VM_NAME}-base.img"

# Create VM disk as overlay
step "Creating VM disk..."
debug "Creating QCOW2 overlay disk: ${VM_NAME}.qcow2 (size: $VM_DISK_SIZE)"
debug_cmd_output qemu-img create -f qcow2 -F qcow2 -b "${VM_NAME}-base.img" "${VM_NAME}.qcow2" "$VM_DISK_SIZE"

# Generate instance ID
if [ "$FRESH_INSTANCE" = true ] || [ ! -f "cloud-init/instance-id" ]; then
  INSTANCE_ID="iid-${VM_NAME}-$(date +%s)"
  debug "Generated new instance ID: $INSTANCE_ID"
  echo "$INSTANCE_ID" >"cloud-init/instance-id"
else
  INSTANCE_ID=$(cat "cloud-init/instance-id")
  debug "Using existing instance ID: $INSTANCE_ID"
fi

# Read SSH public key with security validation
debug "Reading SSH public key from: $VM_SSH_KEY"
if [ ! -f "$VM_SSH_KEY" ]; then
  error "SSH public key file not found: $VM_SSH_KEY"
  exit 1
fi

# Check SSH key file permissions for security
key_perms=$(stat -f "%A" "$VM_SSH_KEY" 2>/dev/null || stat -c "%a" "$VM_SSH_KEY" 2>/dev/null)
if [ -n "$key_perms" ] && [ "$key_perms" -gt 644 ]; then
  warn "SSH key file has overly permissive permissions: $key_perms"
  warn "Consider: chmod 644 $VM_SSH_KEY"
fi

SSH_PUBLIC_KEY=$(cat "$VM_SSH_KEY")
debug "SSH public key: ${SSH_PUBLIC_KEY:0:50}..."

# Create cloud-init user-data with OS-specific configurations
step "Creating cloud-init configuration..."

# Base cloud-init config
cat >"cloud-init/user-data" <<EOF
#cloud-config
hostname: $VM_HOSTNAME
users:
  - name: $VM_USERNAME
    shell: $(get_shell)
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - $SSH_PUBLIC_KEY
    lock_passwd: false
ssh_pwauth: true
chpasswd:
  list: |
    $VM_USERNAME:$VM_PASSWORD
  expire: false
EOF

# Skip package installation during cloud-init for faster boot
# Packages can be installed manually after VM is running:
# ssh user@vm 'sudo apt update && sudo apt install -y package1 package2'
if false && [ -n "$VM_PACKAGES" ]; then
  cat >>"cloud-init/user-data" <<EOF
packages:
$(echo "$VM_PACKAGES" | tr ',' '\n' | sed 's/^/  - /')
EOF
fi

# Add OS-specific commands only for special OS types (not basic ubuntu)
case "$VM_OS" in
"ubuntu")
  # No runcmd needed for basic ubuntu - SSH is enabled by default in cloud images
  ;;
"debian")
  # No runcmd needed for basic debian - SSH is enabled by default in cloud images
  ;;
"fedora"|"centos")
  # No runcmd needed for basic fedora/centos - SSH is enabled by default in cloud images
  ;;
"k3s")
  # Add runcmd section for special OS types
  echo "runcmd:" >>"cloud-init/user-data"
  echo "  - systemctl enable ssh" >>"cloud-init/user-data"
  echo "  - systemctl start ssh" >>"cloud-init/user-data"
  cat >>"cloud-init/user-data" <<EOF
  - curl -sfL https://get.k3s.io | sh -
  - systemctl enable k3s
  - mkdir -p /home/$VM_USERNAME/.kube
  - cp /etc/rancher/k3s/k3s.yaml /home/$VM_USERNAME/.kube/config
  - chown $VM_USERNAME:$VM_USERNAME /home/$VM_USERNAME/.kube/config
  - echo "export KUBECONFIG=/home/$VM_USERNAME/.kube/config" >> /home/$VM_USERNAME/.bashrc
EOF
  ;;
"docker")
  # Add runcmd section for special OS types
  echo "runcmd:" >>"cloud-init/user-data"
  echo "  - systemctl enable ssh" >>"cloud-init/user-data"
  echo "  - systemctl start ssh" >>"cloud-init/user-data"
  cat >>"cloud-init/user-data" <<EOF
  - systemctl enable docker
  - systemctl start docker
  - usermod -aG docker $VM_USERNAME
  - curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-\$(uname -s)-\$(uname -m)" -o /usr/local/bin/docker-compose
  - chmod +x /usr/local/bin/docker-compose
EOF
  ;;
"minikube")
  # Add runcmd section for special OS types
  echo "runcmd:" >>"cloud-init/user-data"
  echo "  - systemctl enable ssh" >>"cloud-init/user-data"
  echo "  - systemctl start ssh" >>"cloud-init/user-data"
  cat >>"cloud-init/user-data" <<EOF
  - systemctl enable docker
  - systemctl start docker
  - usermod -aG docker $VM_USERNAME
  - curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
  - install minikube-linux-amd64 /usr/local/bin/minikube
  - curl -LO "https://dl.k8s.io/release/\$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  - install kubectl /usr/local/bin/kubectl
EOF
  ;;
esac

# Copy and add custom scripts
for script in "${VM_SCRIPTS[@]}"; do
  script_name=$(basename "$script")
  # Convert relative path to absolute path from original working directory
  if [[ "$script" != /* ]]; then
    script="$VM_BASE_DIR/$script"
  fi
  debug "Copying script: $script -> cloud-init/$script_name"
  cp "$script" "cloud-init/$script_name"
  chmod +x "cloud-init/$script_name"
  echo "  - /var/lib/cloud/instance/scripts/$script_name" >>"cloud-init/user-data"
done

# Add custom run commands
for cmd in "${VM_RUN_COMMANDS[@]}"; do
  debug "Adding run command: $cmd"
  echo "  - $cmd" >>"cloud-init/user-data"
done

# Add final message based on OS
case "$VM_OS" in
"k3s")
  echo "final_message: \"K3s cluster ready! SSH: ssh $VM_USERNAME@\$(hostname -I | cut -d' ' -f1) | kubectl get nodes\"" >>"cloud-init/user-data"
  ;;
"docker")
  echo "final_message: \"Docker host ready! SSH: ssh $VM_USERNAME@\$(hostname -I | cut -d' ' -f1) | docker version\"" >>"cloud-init/user-data"
  ;;
"minikube")
  echo "final_message: \"Minikube ready! SSH: ssh $VM_USERNAME@\$(hostname -I | cut -d' ' -f1) | Run: minikube start --driver=docker\"" >>"cloud-init/user-data"
  ;;
*)
  echo "final_message: \"$VM_HOSTNAME VM is ready! SSH: ssh $VM_USERNAME@\$(hostname -I | cut -d' ' -f1)\"" >>"cloud-init/user-data"
  ;;
esac

# Create cloud-init meta-data
cat >"cloud-init/meta-data" <<EOF
instance-id: $INSTANCE_ID
local-hostname: $VM_HOSTNAME
EOF

# Create cloud-init ISO
step "Creating cloud-init ISO..."
debug "Creating ISO with cloud-init data"
debug_cmd_output mkisofs -output "${VM_NAME}-seed.iso" -volid cidata -joliet -rock cloud-init/user-data cloud-init/meta-data

# Generate MAC address
VM_MAC=$(generate_mac "$VM_NAME")
debug "Generated MAC address: $VM_MAC"
echo "$VM_MAC" >"${VM_NAME}.mac"

# Register VM in registry
debug "Registering VM in registry"
# Get current memory and CPU defaults for registry
VM_MEMORY_MB=$(get_mem_mb)
VM_VCPUS_COUNT=$(get_vcpus)
register_vm "$VM_NAME" "$(pwd)" "$VM_HOSTNAME" "$VM_USERNAME" "$VM_DISK_SIZE" "$VM_OS-$VM_VERSION" "$VM_MAC" "$INSTANCE_ID" "$VM_ARCH" "$VM_MEMORY_MB" "$VM_VCPUS_COUNT"

log "✅ VM '$VM_NAME' created successfully!"
log ""
log "VM Details:"
log "  - Directory: $(pwd)"
log "  - Disk: ${VM_NAME}.qcow2 ($VM_DISK_SIZE)"
log "  - MAC: $VM_MAC"
log "  - Instance ID: $INSTANCE_ID"
log ""
log "Next steps:"
log "  - Start VM: vm start $VM_NAME"
log "  - Check status: vm status $VM_NAME"
