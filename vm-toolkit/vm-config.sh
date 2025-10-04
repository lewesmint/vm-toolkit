#!/bin/bash

# VM Toolkit Configuration
# This file contains default settings for all VM operations

# User and authentication defaults
# Use SUDO_USER if running with sudo, otherwise current USER
DEFAULT_USERNAME="${SUDO_USER:-${USER:-ubuntu}}"
DEFAULT_SSH_KEY="${HOME}/.ssh/id_ed25519.pub"
DEFAULT_SHELL="/bin/bash"
DEFAULT_SUDO_GROUPS="sudo,kvm,libvirt"

# VM resource defaults
DEFAULT_DISK_SIZE="40G"
DEFAULT_MEM_MB="4096"
DEFAULT_VCPUS="4"

# Network defaults
DEFAULT_BRIDGE_IF="en0" # macOS Wi-Fi interface

# Architecture defaults
DEFAULT_ARCH="x86_64"

# QEMU defaults (architecture-specific)
DEFAULT_MACHINE="accel=tcg"
DEFAULT_CPU="max"

# OS and cloud image defaults
DEFAULT_OS="ubuntu"
DEFAULT_UBUNTU_VERSION="noble" # 24.04 LTS
DEFAULT_DEBIAN_VERSION="12"    # Bookworm
DEFAULT_FEDORA_VERSION="39"    # Latest stable
DEFAULT_CENTOS_VERSION="9-stream"

# Cloud computing distributions
DEFAULT_K3S_VERSION="latest"      # Lightweight Kubernetes
DEFAULT_DOCKER_VERSION="latest"   # Docker pre-installed
# DEFAULT_MINIKUBE_VERSION="latest" # Single-node Kubernetes (unused)
DEFAULT_RANCHER_VERSION="latest"  # Rancher OS
DEFAULT_TALOS_VERSION="latest"    # Immutable Kubernetes OS

DEFAULT_PACKAGES="openssh-server,qemu-guest-agent,curl,wget,vim"

# Operational defaults
DEFAULT_TIMEOUT_SEC="30"

# Load user configuration first to get paths
USER_CONFIG="${HOME}/.vm-toolkit-config"
if [ -f "$USER_CONFIG" ]; then
  # shellcheck disable=SC1090
  source "$USER_CONFIG"
fi

# Paths - Use configuration or fallback to defaults
# Default to vm-toolkit-data in home directory for new installations
VM_PROJECT_DIR="${VM_PROJECT_DIR:-${HOME}/vm-toolkit-data}"
VM_BASE_DIR="${VM_BASE_DIR:-${VM_PROJECT_DIR}/vms}"
export CLOUD_IMAGE_CACHE="${CLOUD_IMAGE_CACHE:-${VM_PROJECT_DIR}/.cache}"

# Ensure VM base directory exists
ensure_vm_base_dir() {
  if [ ! -d "$VM_BASE_DIR" ]; then
    mkdir -p "$VM_BASE_DIR"
    log "Created VM directory: $VM_BASE_DIR"
  fi
}

# Cloud image URLs
UBUNTU_CLOUD_BASE_URL="https://cloud-images.ubuntu.com"
DEBIAN_CLOUD_BASE_URL="https://cloud.debian.org/images/cloud"
FEDORA_CLOUD_BASE_URL="https://download.fedoraproject.org/pub/fedora/linux/releases"
CENTOS_CLOUD_BASE_URL="https://cloud.centos.org/centos"

# Cloud computing distribution URLs
# K3S_CLOUD_BASE_URL="https://github.com/k3s-io/k3s/releases" (unused)
# DOCKER_CLOUD_BASE_URL="https://download.docker.com/linux/static/stable/x86_64" (unused)
RANCHER_CLOUD_BASE_URL="https://releases.rancher.com/os"
TALOS_CLOUD_BASE_URL="https://github.com/siderolabs/talos/releases"

# QEMU MAC address prefix (QEMU's OUI)
MAC_PREFIX="52:54:00"

# User configuration already loaded above for paths

# Function to get configuration value with precedence:
# 1. Environment variable (VM_*)
# 2. User config file
# 3. Default value
get_config() {
  local var_name="$1"
  local default_value="$2"

  # Check environment variable first (VM_* prefix)
  local env_var="VM_${var_name}"
  if [ -n "${!env_var}" ]; then
    echo "${!env_var}"
    return
  fi

  # Check if variable is set in user config
  local config_var="${var_name}"
  if [ -n "${!config_var}" ]; then
    echo "${!config_var}"
    return
  fi

  # Fall back to default
  echo "$default_value"
}

# Helper functions for getting specific config values
get_username() { get_config "USERNAME" "$DEFAULT_USERNAME"; }
get_ssh_key() { get_config "SSH_KEY" "$DEFAULT_SSH_KEY"; }
get_shell() {
  # Always use /bin/bash for VMs (ignore host SHELL environment variable)
  echo "/bin/bash"
}
get_sudo_groups() { get_config "SUDO_GROUPS" "$DEFAULT_SUDO_GROUPS"; }
get_disk_size() { get_config "DISK_SIZE" "$DEFAULT_DISK_SIZE"; }
get_mem_mb() { get_config "MEM_MB" "$DEFAULT_MEM_MB"; }
get_vcpus() { get_config "VCPUS" "$DEFAULT_VCPUS"; }
get_bridge_if() { get_config "BRIDGE_IF" "$DEFAULT_BRIDGE_IF"; }
get_machine() { get_config "MACHINE" "$DEFAULT_MACHINE"; }
get_cpu() { get_config "CPU" "$DEFAULT_CPU"; }
get_os() { get_config "OS" "$DEFAULT_OS"; }
get_ubuntu_version() { get_config "UBUNTU_VERSION" "$DEFAULT_UBUNTU_VERSION"; }
get_debian_version() { get_config "DEBIAN_VERSION" "$DEFAULT_DEBIAN_VERSION"; }
get_fedora_version() { get_config "FEDORA_VERSION" "$DEFAULT_FEDORA_VERSION"; }
get_centos_version() { get_config "CENTOS_VERSION" "$DEFAULT_CENTOS_VERSION"; }
get_k3s_version() { get_config "K3S_VERSION" "$DEFAULT_K3S_VERSION"; }
get_docker_version() { get_config "DOCKER_VERSION" "$DEFAULT_DOCKER_VERSION"; }
get_rancher_version() { get_config "RANCHER_VERSION" "$DEFAULT_RANCHER_VERSION"; }
get_talos_version() { get_config "TALOS_VERSION" "$DEFAULT_TALOS_VERSION"; }
get_packages() { get_config "PACKAGES" "$DEFAULT_PACKAGES"; }
get_timeout_sec() { get_config "TIMEOUT_SEC" "$DEFAULT_TIMEOUT_SEC"; }
get_arch() { get_config "ARCH" "$DEFAULT_ARCH"; }

# Architecture-specific configuration functions
get_qemu_binary() {
  local arch="${1:-$(get_arch)}"
  case "$arch" in
    "x86_64"|"amd64")
      echo "qemu-system-x86_64"
      ;;
    "arm64"|"aarch64")
      echo "qemu-system-aarch64"
      ;;
    "i386"|"x86")
      echo "qemu-system-i386"
      ;;
    *)
      error "Unsupported architecture: $arch"
      error "Supported: x86_64, arm64, i386"
      return 1
      ;;
  esac
}

get_machine_type() {
  local arch="${1:-$(get_arch)}"
  case "$arch" in
    "x86_64"|"amd64"|"i386"|"x86")
      echo "pc"
      ;;
    "arm64"|"aarch64")
      echo "virt"
      ;;
    *)
      error "Unsupported architecture: $arch"
      return 1
      ;;
  esac
}

get_acceleration() {
  local arch="${1:-$(get_arch)}"
  local host_arch
  host_arch=$(uname -m)

  case "$arch" in
    "arm64"|"aarch64")
      # Use HVF acceleration on macOS if host is ARM64
      if [[ "$OSTYPE" == "darwin"* ]] && [[ "$host_arch" == "arm64" ]]; then
        echo "accel=hvf"
      else
        echo "accel=tcg"
      fi
      ;;
    "x86_64"|"amd64")
      # Use HVF acceleration on macOS if host is x86_64
      if [[ "$OSTYPE" == "darwin"* ]] && [[ "$host_arch" == "x86_64" ]]; then
        echo "accel=hvf"
      else
        echo "accel=tcg"
      fi
      ;;
    "i386"|"x86")
      # 32-bit x86 typically uses TCG
      echo "accel=tcg"
      ;;
    *)
      echo "accel=tcg"
      ;;
  esac
}

get_cpu_type() {
  local arch="${1:-$(get_arch)}"
  local host_arch
  host_arch=$(uname -m)

  case "$arch" in
    "arm64"|"aarch64")
      # Use host CPU if running on ARM64 with HVF, otherwise cortex-a72
      if [[ "$OSTYPE" == "darwin"* ]] && [[ "$host_arch" == "arm64" ]]; then
        echo "host"
      else
        echo "cortex-a72"
      fi
      ;;
    "x86_64"|"amd64")
      # Use host CPU if running on x86_64 with HVF, otherwise max
      if [[ "$OSTYPE" == "darwin"* ]] && [[ "$host_arch" == "x86_64" ]]; then
        echo "host"
      else
        echo "max"
      fi
      ;;
    "i386"|"x86")
      echo "pentium3"
      ;;
    *)
      echo "max"
      ;;
  esac
}

# Generate unique MAC address based on VM name
generate_mac() {
  local vm_name="$1"
  local hash
  hash=$(echo -n "$vm_name" | shasum -a 256 | cut -c1-6)
  echo "${MAC_PREFIX}:${hash:0:2}:${hash:2:2}:${hash:4:2}"
}

# Get cloud image filename based on OS and architecture
get_cloud_image_filename() {
  local os="${1:-$(get_os)}"
  local version="${2:-}"
  local arch="${3:-$(get_arch)}"

  # Normalize architecture names for cloud images
  local cloud_arch
  case "$arch" in
    "x86_64"|"amd64")
      cloud_arch="amd64"
      ;;
    "arm64"|"aarch64")
      cloud_arch="arm64"
      ;;
    "i386"|"x86")
      cloud_arch="i386"
      ;;
    *)
      error "Unsupported architecture for cloud images: $arch"
      return 1
      ;;
  esac

  case "$os" in
  "ubuntu")
    version="${version:-$(get_ubuntu_version)}"
    echo "${version}-server-cloudimg-${cloud_arch}.img"
    ;;
  "debian")
    version="${version:-$(get_debian_version)}"
    echo "debian-${version}-generic-${cloud_arch}.qcow2"
    ;;
  "fedora")
    version="${version:-$(get_fedora_version)}"
    # Fedora uses different naming for ARM64
    if [ "$cloud_arch" = "arm64" ]; then
      echo "Fedora-Cloud-Base-${version}-1.5.aarch64.qcow2"
    else
      echo "Fedora-Cloud-Base-${version}-1.5.x86_64.qcow2"
    fi
    ;;
  "centos")
    version="${version:-$(get_centos_version)}"
    # CentOS uses different naming for ARM64
    if [ "$cloud_arch" = "arm64" ]; then
      echo "CentOS-Stream-GenericCloud-${version}-latest.aarch64.qcow2"
    else
      echo "CentOS-Stream-GenericCloud-${version}-latest.x86_64.qcow2"
    fi
    ;;
  "k3s")
    # K3s on Ubuntu base
    echo "k3s-ubuntu-$(get_ubuntu_version)-${cloud_arch}.qcow2"
    ;;
  "docker")
    # Docker on Ubuntu base
    echo "docker-ubuntu-$(get_ubuntu_version)-${cloud_arch}.qcow2"
    ;;
  "minikube")
    # Minikube on Ubuntu base
    echo "minikube-ubuntu-$(get_ubuntu_version)-${cloud_arch}.qcow2"
    ;;
  "rancher")
    version="${version:-$(get_rancher_version)}"
    echo "rancheros-${version}-${cloud_arch}.qcow2"
    ;;
  "talos")
    version="${version:-$(get_talos_version)}"
    echo "talos-${version}-${cloud_arch}.qcow2"
    ;;
  *)
    error "Unsupported OS: $os"
    error "Supported: ubuntu, debian, fedora, centos, k3s, docker, minikube, rancher, talos"
    return 1
    ;;
  esac
}

# Get cloud image URL based on OS and architecture
get_cloud_image_url() {
  local os="${1:-$(get_os)}"
  local version="${2:-}"
  local arch="${3:-$(get_arch)}"
  local filename
  filename=$(get_cloud_image_filename "$os" "$version" "$arch")

  # Normalize architecture names for URLs
  local url_arch
  case "$arch" in
    "x86_64"|"amd64")
      url_arch="x86_64"
      ;;
    "arm64"|"aarch64")
      url_arch="aarch64"
      ;;
    "i386"|"x86")
      url_arch="i386"
      ;;
    *)
      error "Unsupported architecture for cloud images: $arch"
      return 1
      ;;
  esac

  case "$os" in
  "ubuntu")
    version="${version:-$(get_ubuntu_version)}"
    echo "${UBUNTU_CLOUD_BASE_URL}/${version}/current/${filename}"
    ;;
  "debian")
    version="${version:-$(get_debian_version)}"
    echo "${DEBIAN_CLOUD_BASE_URL}/${version}/latest/${filename}"
    ;;
  "fedora")
    version="${version:-$(get_fedora_version)}"
    echo "${FEDORA_CLOUD_BASE_URL}/${version}/Cloud/${url_arch}/images/${filename}"
    ;;
  "centos")
    version="${version:-$(get_centos_version)}"
    echo "${CENTOS_CLOUD_BASE_URL}/${version}/${url_arch}/images/${filename}"
    ;;
  "k3s" | "docker" | "minikube")
    # These will be custom-built from Ubuntu base
    echo "custom-build:${os}:${arch}"
    ;;
  "rancher")
    version="${version:-$(get_rancher_version)}"
    echo "${RANCHER_CLOUD_BASE_URL}/${version}/${filename}"
    ;;
  "talos")
    version="${version:-$(get_talos_version)}"
    echo "${TALOS_CLOUD_BASE_URL}/download/${version}/${filename}"
    ;;
  *)
    error "Unsupported OS: $os"
    error "Supported: ubuntu, debian, fedora, centos, k3s, docker, minikube, rancher, talos"
    return 1
    ;;
  esac
}

# Check if running as root (required for vmnet)
check_root() {
  if [ "$EUID" -ne 0 ]; then
    error "This command requires root privileges for vmnet access"
    error "Please run with sudo: sudo $0 $*"
    exit 1
  fi
}

# Logging functions
log() { echo -e "\033[0;32m[INFO]\033[0m $1" >&2; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $1" >&2; }
error() { echo -e "\033[0;31m[ERROR]\033[0m $1" >&2; }
step() { echo -e "\033[0;34m[STEP]\033[0m $1" >&2; }

# Security functions
validate_vm_name() {
  local name="$1"
  if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    error "Invalid VM name: $name (use only letters, numbers, hyphens, underscores)"
    exit 1
  fi
  if [ ${#name} -gt 50 ]; then
    error "VM name too long: $name (max 50 characters)"
    exit 1
  fi
  if [ ${#name} -lt 1 ]; then
    error "VM name cannot be empty"
    exit 1
  fi
}

get_vm_dir() {
  local vm_name="$1"
  validate_vm_name "$vm_name"

  # Ensure VM base directory exists
  ensure_vm_base_dir

  # Ensure path stays within base directory
  local canonical_base
  canonical_base=$(cd "$VM_BASE_DIR" && pwd) || {
    error "Cannot access VM base directory: $VM_BASE_DIR"
    exit 1
  }
  local canonical_dir="$canonical_base/$vm_name"

  # Verify the path doesn't escape base directory
  if [[ "$canonical_dir" != "$canonical_base"/* ]]; then
    error "Invalid VM path: $vm_name"
    exit 1
  fi

  echo "$canonical_dir"
}

# Dependency checking
check_dependencies() {
  local missing=()
  local warnings=()
  local arch="${1:-$(get_arch)}"

  # Required tools - check for architecture-specific QEMU binary
  local qemu_binary
  qemu_binary=$(get_qemu_binary "$arch")
  command -v "$qemu_binary" >/dev/null || missing+=("qemu")
  command -v mkisofs >/dev/null || missing+=("cdrtools")
  command -v curl >/dev/null || missing+=("curl")

  # Optional but recommended
  command -v socat >/dev/null || warnings+=("socat (for QMP operations)")
  command -v jq >/dev/null || warnings+=("jq (for registry operations)")

  if [ ${#missing[@]} -gt 0 ]; then
    error "Missing required dependencies: ${missing[*]}"
    error "Install with: brew install ${missing[*]}"
    if [[ "${missing[*]}" == *"qemu"* ]]; then
      error "Note: QEMU binary '$qemu_binary' not found for architecture '$arch'"
      error "Make sure QEMU is installed with support for $arch"
    fi
    exit 1
  fi

  if [ ${#warnings[@]} -gt 0 ]; then
    warn "Missing optional dependencies: ${warnings[*]}"
    warn "Install with: brew install socat jq"
  fi
}

# Secure temp file creation
create_secure_temp() {
  local prefix="$1"
  local temp_file
  temp_file=$(mktemp "${TMPDIR:-/tmp}/${prefix}.XXXXXX") || {
    error "Failed to create temporary file"
    exit 1
  }
  chmod 600 "$temp_file"
  echo "$temp_file"
}
