#!/bin/bash

# VM Toolkit - Console VM
# Connect to a running VM's console via QMP

set -e

# Get script directory and load config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/vm-config.sh"
source "$SCRIPT_DIR/vm-common.sh"
source "$SCRIPT_DIR/vm-registry.sh"

show_usage() {
  cat <<EOF
Usage: $0 [vm-name] [options]

Connect to a running VM's console.

Options:
  vm-name               VM name (positional argument)
  --name <name>         VM name (alternative syntax)
  --help                Show this help

Examples:
  $0 alpha
  $0 --name alpha
EOF
}

# Parse arguments
VM_NAME=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --name)
      VM_NAME="$2"
      shift 2
      ;;
    --help)
      show_usage
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      show_usage
      exit 1
      ;;
    *)
      if [ -z "$VM_NAME" ]; then
        VM_NAME="$1"
      else
        echo "Multiple VM names specified" >&2
        show_usage
        exit 1
      fi
      shift
      ;;
  esac
done

# Validate VM name
if [ -z "$VM_NAME" ]; then
  error "VM name is required"
  show_usage
  exit 1
fi

# Check if VM exists
VM_DIR=$(ensure_vm_exists "$VM_NAME")

# Check if VM is running
VM_STATUS=$(get_vm_status "$VM_NAME")
if [ "$VM_STATUS" != "running" ] && [ "$VM_STATUS" != "initializing" ] && [ "$VM_STATUS" != "booting" ]; then
  error "VM '$VM_NAME' is not running (status: $VM_STATUS)"
  exit 1
fi

# VM_DIR already set by ensure_vm_exists
QMP_SOCKET="$VM_DIR/${VM_NAME}.qmp"

# Check if QMP socket exists
if [ ! -S "$QMP_SOCKET" ]; then
  error "QMP socket not found: $QMP_SOCKET"
  error "VM may not be running or was started without QMP support"
  exit 1
fi

# Check if socat is available
if ! command -v socat >/dev/null 2>&1; then
  error "socat is required for console access"
  error "Install with: brew install socat"
  exit 1
fi

log "🖥️  Connecting to VM '$VM_NAME' console..."
log "📋 Console log: $(pwd)/$VM_NAME/console.log"
log ""
log "💡 Tips:"
log "   - This connects to the VM's serial console"
log "   - To exit: Ctrl+C"
log "   - To view console history: tail -f $(pwd)/$VM_NAME/console.log"
log ""
log "🔌 Connecting..."

# Connect to QMP and switch to monitor mode
# This allows interactive console access
echo '{"execute":"qmp_capabilities"}{"execute":"human-monitor-command","arguments":{"command-line":"info status"}}' | socat - "UNIX-CONNECT:$QMP_SOCKET"

log ""
log "Note: For full interactive console, restart VM with: vm start $VM_NAME --console"
