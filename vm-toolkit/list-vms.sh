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

# Fast list - just read from registry without syncing
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

  echo "📋 VM List (fast view - use 'vm status' for detailed info)"
  echo "========================================================"
  printf "%-15s %-10s %-15s\n" "VM NAME" "STATUS" "DIRECTORY"
  printf "%-15s %-10s %-15s\n" "-------" "------" "---------"
  
  jq -r '.vms | to_entries[] | "\(.key) \(.value.status) \(.value.directory)"' "$REGISTRY_FILE" 2>/dev/null | \
  while read -r name status directory; do
    printf "%-15s %-10s %-15s\n" "$name" "$status" "$(basename "$directory")"
  done
  
  echo ""
  echo "💡 Tip: Use 'vm status' for live status with IP addresses and uptime"
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
