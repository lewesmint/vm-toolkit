#!/bin/bash

# VM Resume Script
# Resumes a paused VM

set -e

# Get script directory and load config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/vm-config.sh"
source "$SCRIPT_DIR/vm-registry.sh"
source "$SCRIPT_DIR/vm-common.sh"

show_usage() {
  show_vm_usage "$0" "Resume a paused VM." ""
}

# Parse arguments and set up VM operation
parse_vm_operation_args "$@"

# Ensure VM is in paused state
ensure_vm_state_paused "$VM_NAME" "$VM_DIR"
PID=$(get_vm_pid "$VM_NAME" "$VM_DIR")

log "Resuming VM: $VM_NAME (PID: $PID)"

# Resume via QMP if available
log "Sending resume command via QMP..."
if qmp_cont "$VM_DIR" "$VM_NAME"; then
  # No registry update needed - status computed live

  log "✅ VM '$VM_NAME' resumed successfully"
  log ""
  log "Next steps:"
  log "  - Check status: vm status $VM_NAME"
  log "  - Pause VM: vm pause $VM_NAME"
else
  error "Failed to resume VM '$VM_NAME'"
  exit 1
fi
