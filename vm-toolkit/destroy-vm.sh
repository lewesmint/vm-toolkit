#!/bin/bash

# VM Destroy Script
# Completely removes a VM and all its data

set -e

# If running as root via sudo, switch back to the original user
if [ "$EUID" -eq 0 ] && [ -n "$SUDO_USER" ]; then
  echo "[INFO] Detected sudo usage - switching back to user '$SUDO_USER' for VM destruction"
  exec su "$SUDO_USER" -c "$(printf '%q ' "$0" "$@")"
fi

# Get script directory and load config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/vm-config.sh"
source "$SCRIPT_DIR/vm-registry.sh"
source "$SCRIPT_DIR/vm-common.sh"

show_usage() {
  show_vm_usage "$0" "Completely destroy a VM and all its data." "  --force               Skip confirmation prompt"
}

# Parse script-specific arguments first
FORCE_DESTROY=false
REMAINING_ARGS=()

# Parse all arguments, extracting --force and keeping the rest
while [[ $# -gt 0 ]]; do
  case $1 in
  --force)
    FORCE_DESTROY=true
    shift
    ;;
  *)
    # Keep this argument for common parser
    REMAINING_ARGS+=("$1")
    shift
    ;;
  esac
done

# Parse common arguments and set up VM operation
parse_vm_operation_args "${REMAINING_ARGS[@]}"

# Check if VM exists
if [ ! -d "$VM_BASE_DIR/$VM_NAME" ]; then
  error "VM '$VM_NAME' not found"
  exit 1
fi

# Check if VM is running and stop it
VM_DIR="$VM_BASE_DIR/$VM_NAME"
if [ -f "$VM_DIR/${VM_NAME}.pid" ]; then
  PID=$(cat "$VM_DIR/${VM_NAME}.pid")
  if kill -0 "$PID" 2>/dev/null; then
    warn "VM '$VM_NAME' is running. Stopping it first..."
    "$SCRIPT_DIR/stop-vm.sh" --name "$VM_NAME" --force
    sleep 2
  fi
fi

# Get VM info for confirmation
DISK_SIZE="unknown"
if [ -f "$VM_DIR/${VM_NAME}.qcow2" ]; then
  DISK_SIZE=$(qemu-img info "$VM_DIR/${VM_NAME}.qcow2" | grep "virtual size" | cut -d'(' -f2 | cut -d' ' -f1 || echo "unknown")
fi

# Confirmation prompt
if [ "$FORCE_DESTROY" = false ]; then
  echo "⚠️  WARNING: This will permanently destroy VM '$VM_NAME' and ALL its data!"
  echo ""
  echo "VM Details:"
  echo "  - Name: $VM_NAME"
  echo "  - Directory: $VM_DIR"
  echo "  - Disk size: $DISK_SIZE"
  echo ""
  echo "Files to be deleted:"
  find "$VM_DIR" -type f | sed 's/^/  - /'
  echo ""
  read -r -p "Are you absolutely sure? Type 'yes' to confirm: " confirm

  if [ "$confirm" != "yes" ]; then
    log "Destruction cancelled"
    exit 0
  fi
fi

log "Destroying VM: $VM_NAME"

# Remove from registry first
unregister_vm "$VM_NAME"

# Remove all VM files
log "Removing VM directory: $VM_DIR"
rm -rf "$VM_DIR"

log "✅ VM '$VM_NAME' destroyed successfully"
log "All data has been permanently deleted"
