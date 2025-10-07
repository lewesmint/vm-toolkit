#!/bin/bash

# VM Stop Script
# Stops a running VM gracefully

set -e

# Get script directory and load config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/vm-config.sh"
source "$SCRIPT_DIR/vm-registry.sh"
source "$SCRIPT_DIR/vm-common.sh"

show_usage() {
  show_vm_usage "$0" "Stop a running VM gracefully." "  --timeout <seconds>   Shutdown timeout (default: $(get_timeout_sec))
  --force               Force kill without graceful shutdown"
}

# Parse script-specific arguments first
TIMEOUT_SEC=""
FORCE_KILL=false

# Parse script-specific arguments
while [[ $# -gt 0 ]]; do
  case $1 in
  --timeout)
    TIMEOUT_SEC="$2"
    shift 2
    ;;
  --force)
    FORCE_KILL=true
    shift
    ;;
  *)
    # Let common parser handle --name and --help
    break
    ;;
  esac
done

# Parse common arguments and set up VM operation
parse_vm_operation_args "$@"

# Set defaults
TIMEOUT_SEC="${TIMEOUT_SEC:-$(get_timeout_sec)}"

# Check if VM is running (stop is more lenient than other operations)
if ! is_vm_running "$VM_NAME" "$VM_DIR"; then
  warn "VM '$VM_NAME' is not running"
  exit 0
fi

PID=$(get_vm_pid_from_dir "$VM_NAME" "$VM_DIR")

log "Stopping VM: $VM_NAME (PID: $PID)"

if [ "$FORCE_KILL" = true ]; then
  # Force kill
  log "Force killing VM..."
  sudo kill -KILL "$PID"
  rm -f "$VM_DIR/${VM_NAME}.pid"

  # No registry update needed - status computed live

  log "✅ VM '$VM_NAME' force killed"
else
  # Graceful shutdown via QMP if available
  QMP_SOCKET="$VM_DIR/${VM_NAME}.qmp"
  if [ -S "$QMP_SOCKET" ] && command -v socat >/dev/null 2>&1; then
    log "Sending graceful shutdown via QMP..."
    echo '{"execute":"qmp_capabilities"}{"execute":"system_powerdown"}' |
      socat - "UNIX-CONNECT:$QMP_SOCKET" >/dev/null 2>&1 || true
  else
    # Fallback to SIGTERM
    log "Sending SIGTERM..."
    sudo kill -TERM "$PID"
  fi

  # Wait for graceful shutdown
  log "Waiting up to ${TIMEOUT_SEC}s for graceful shutdown..."
  for _ in $(seq 1 "$TIMEOUT_SEC"); do
    if ! sudo kill -0 "$PID" 2>/dev/null; then
      rm -f "$VM_DIR/${VM_NAME}.pid"

      # No registry update needed - status computed live

      log "✅ VM '$VM_NAME' stopped gracefully"
      exit 0
    fi
    sleep 1
  done

  # Timeout reached, force kill
  warn "Graceful shutdown timeout, force killing..."
  sudo kill -KILL "$PID"
  rm -f "$VM_DIR/${VM_NAME}.pid"

  # No registry update needed - status computed live

  log "✅ VM '$VM_NAME' force killed after timeout"
fi
