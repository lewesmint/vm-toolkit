#!/bin/bash

# VM List Script - Fast listing without sync
# Part of VM Toolkit

set -e

# If running as root via sudo, switch back to the original user
if [ "$EUID" -eq 0 ] && [ -n "$SUDO_USER" ]; then
  echo "[INFO] Detected sudo usage - switching back to user '$SUDO_USER' for VM listing"
  exec su "$SUDO_USER" -c "$(printf '%q ' "$0" "$@")"
fi

# Get script directory and load config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/vm-config.sh"
source "$SCRIPT_DIR/vm-registry.sh"

# Fast list - read from registry only (no live/status probing)
list_vms_fast() {
  if [ ! -f "$REGISTRY_FILE" ]; then
    echo "No VMs found (registry file doesn't exist)"
    return
  fi

  local vm_count
  vm_count=$(jq -r '.vms | length' "$REGISTRY_FILE" 2>/dev/null || echo "0")
  
  if [ "$vm_count" -eq 0 ]; then
    echo "No VMs found"
    return
  fi

  echo "📋 VM List"
  echo "=========="
  printf "%-15s %-6s %-8s %-14s %-6s %-8s %-8s\n" "VM NAME" "STATUS" "ARCH" "OS" "VCPUS" "MEM" "DISK"
  printf "%-15s %-6s %-8s %-14s %-6s %-8s %-8s\n" "-------" "------" "----" "--" "-----" "----" "----"

  # Names only from registry; compute a minimal ON/OFF by checking PID
  jq -r '.vms | keys[]' "$REGISTRY_FILE" 2>/dev/null | sort | while read -r name; do
    # Resolve directory from registry, fallback to default path
    dir=$(jq -r --arg n "$name" '.vms[$n].directory // empty' "$REGISTRY_FILE" 2>/dev/null || echo "")
    if [ -z "$dir" ] || [ "$dir" = "null" ]; then
      dir="$(get_vm_dir "$name")"
    fi
    # Static fields from registry
    arch=$(jq -r --arg n "$name" '.vms[$n].architecture // ""' "$REGISTRY_FILE" 2>/dev/null || echo "")
  vcpus=$(jq -r --arg n "$name" '.vms[$n].vcpus // empty' "$REGISTRY_FILE" 2>/dev/null || echo "")
    mem_mb=$(jq -r --arg n "$name" '.vms[$n].memory_mb // empty' "$REGISTRY_FILE" 2>/dev/null || echo "")
  disk_sz=$(jq -r --arg n "$name" '.vms[$n].disk_size // ""' "$REGISTRY_FILE" 2>/dev/null || echo "")
  os_ver=$(jq -r --arg n "$name" '.vms[$n].os_version // ""' "$REGISTRY_FILE" 2>/dev/null || echo "")
    pid_file="$dir/${name}.pid"
    status="off"
    if [ -f "$pid_file" ]; then
      pid=$(cat "$pid_file" 2>/dev/null || true)
      if [ -n "$pid" ] && ps -p "$pid" >/dev/null 2>&1; then
        status="on"
      else
        # stale pid file
        status="off"
      fi
    fi
    # Format memory as GB (rounded), fallback to '-' when empty
    if [ -n "$mem_mb" ] && [[ "$mem_mb" =~ ^[0-9]+$ ]]; then
      mem_gb=$(awk "BEGIN {printf \"%.0f\", $mem_mb/1024}")
      mem_disp="${mem_gb}GB"
    else
      mem_disp="-"
    fi
    if [ -z "$vcpus" ]; then vcpus="-"; fi
    if [ -z "$arch" ]; then arch="-"; fi
    if [ -z "$disk_sz" ]; then disk_sz="-"; fi
    if [ -z "$os_ver" ]; then os_ver="-"; fi
    printf "%-15s %-6s %-8s %-14s %-6s %-8s %-8s\n" "$name" "$status" "$arch" "$os_ver" "$vcpus" "$mem_disp" "$disk_sz"
  done

  echo ""
  echo "💡 Tip: Use 'vm status' for details (IP, uptime, SSH)"
  echo "     Use 'vm status <vm-name>' for detailed info about a specific VM"
}

# Parse arguments
SHOW_HELP=false

while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      SHOW_HELP=true
      shift
      ;;
    *)
      error "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Show help if requested
if [ "$SHOW_HELP" = true ]; then
  cat << EOF
Usage: vm list [OPTIONS]

Fast listing of all VMs from registry (no live status checking)

OPTIONS:
  -h, --help    Show this help message

EXAMPLES:
  vm list                    # Quick list of all VMs
  vm status                  # Detailed status with live checking
  vm status myvm             # Detailed info for specific VM

EOF
  exit 0
fi

# Execute fast list
list_vms_fast
