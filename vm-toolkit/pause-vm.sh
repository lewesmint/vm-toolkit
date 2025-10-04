#!/bin/bash

# VM Pause Script
# Pauses a running VM (suspends to memory)

set -e

# Get script directory and load config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/vm-config.sh"
source "$SCRIPT_DIR/vm-registry.sh"
source "$SCRIPT_DIR/vm-common.sh"

show_usage() {
  show_vm_usage "$0" "Pause a running VM (suspend to memory)." ""
}

# Parse arguments and set up VM operation
parse_vm_operation_args "$@"

# Ensure VM is in running state (not paused or stopped)
ensure_vm_state_running "$VM_NAME" "$VM_DIR"
PID=$(get_vm_pid "$VM_NAME" "$VM_DIR")

log "Pausing VM: $VM_NAME (PID: $PID)"

# Pause via QMP if available
log "Sending pause command via QMP..."
if qmp_stop "$VM_DIR" "$VM_NAME"; then
  # No registry update needed - status computed live

  log "✅ VM '$VM_NAME' paused successfully"
  log ""
  log "Next steps:"
  log "  - Resume VM: vm resume $VM_NAME"
  log "  - Check status: vm status $VM_NAME"
else
  error "Failed to pause VM '$VM_NAME'"
  exit 1
fi
