#!/bin/bash

# VM Start Script
# Starts a VM with bridge networking

set -e

# Get script directory and load config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/vm-config.sh"
source "$SCRIPT_DIR/vm-registry.sh"
source "$SCRIPT_DIR/vm-common.sh"

show_usage() {
  show_vm_usage "$0" "Start an existing VM with bridge networking." "  --bridge <interface>  Bridge interface (default: $(get_bridge_if))
  --mem <mb>            Memory in MB (default: $(get_mem_mb))
  --vcpus <count>       vCPU count (default: $(get_vcpus))
  --console             Show console output (default: background)"
}

# Parse script-specific arguments first
VM_BRIDGE_IF=""
VM_MEM_MB=""
VM_VCPUS=""
SHOW_CONSOLE=false

# Parse script-specific arguments
REMAINING_ARGS=()
while [[ $# -gt 0 ]]; do
  case $1 in
  --bridge)
    VM_BRIDGE_IF="$2"
    shift 2
    ;;
  --mem)
    VM_MEM_MB="$2"
    shift 2
    ;;
  --vcpus)
    VM_VCPUS="$2"
    shift 2
    ;;
  --console)
    SHOW_CONSOLE=true
    shift
    ;;
  *)
    # Collect remaining arguments for common parser
    REMAINING_ARGS+=("$1")
    shift
    ;;
  esac
done

# Parse common arguments and set up VM operation
parse_vm_operation_args "${REMAINING_ARGS[@]}"

# Check if running as root (required for vmnet)
check_root

# Set defaults
VM_BRIDGE_IF="${VM_BRIDGE_IF:-$(get_bridge_if)}"
VM_MEM_MB="${VM_MEM_MB:-$(get_mem_mb)}"
VM_VCPUS="${VM_VCPUS:-$(get_vcpus)}"

# Check if VM exists (VM_DIR already set securely above)
# Ensure VM is not already running
ensure_vm_stopped "$VM_NAME" "$VM_DIR"

# Get VM MAC address
if [ ! -f "$VM_DIR/${VM_NAME}.mac" ]; then
  error "VM MAC address file not found: $VM_DIR/${VM_NAME}.mac"
  exit 1
fi
VM_MAC=$(cat "$VM_DIR/${VM_NAME}.mac")

# Get VM architecture from registry
VM_ARCH=$(get_vm_architecture "$VM_NAME")

log "Starting VM: $VM_NAME"
log "Configuration:"
log "  - Architecture: $VM_ARCH"
log "  - Memory: ${VM_MEM_MB}MB"
log "  - vCPUs: $VM_VCPUS"
log "  - MAC: $VM_MAC"
log "  - Bridge: $VM_BRIDGE_IF"

# Change to VM directory
cd "$VM_DIR"

# Prepare QEMU command with architecture-specific settings
QEMU_BINARY=$(get_qemu_binary "$VM_ARCH")
MACHINE_TYPE=$(get_machine_type "$VM_ARCH")
ACCELERATION=$(get_acceleration "$VM_ARCH")
CPU_TYPE=$(get_cpu_type "$VM_ARCH")

QEMU_CMD=(
  "$QEMU_BINARY"
  -machine "${MACHINE_TYPE},${ACCELERATION}"
  -cpu "$CPU_TYPE"
  -smp "$VM_VCPUS"
  -m "$VM_MEM_MB"
  -drive "if=virtio,file=${VM_NAME}.qcow2,discard=unmap,detect-zeroes=on"
  -drive "if=virtio,format=raw,media=cdrom,file=${VM_NAME}-seed.iso"
  -netdev "vmnet-bridged,id=net0,ifname=$VM_BRIDGE_IF"
  -device "virtio-net-pci,netdev=net0,mac=$VM_MAC"
)

if [ "$SHOW_CONSOLE" = true ]; then
  # Interactive mode with console (like the working version)
  QEMU_CMD+=(-display none -serial mon:stdio)

  log "📺 Console mode enabled - output will be shown below"
  log "🔌 To exit QEMU console: Ctrl-a then x"
  log ""

  export IFACE="$VM_BRIDGE_IF"
  # Set environment variables to avoid macOS Objective-C fork issues
  export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES
  # Use direct execution instead of exec to avoid macOS fork issues
  "${QEMU_CMD[@]}"
else
  # Background mode
  QEMU_CMD+=(-pidfile "${VM_NAME}.pid" -qmp "unix:${VM_NAME}.qmp,server,nowait" -display none -serial file:console.log -daemonize)

  log "📋 VM will start in background"
  log "📄 Console output: $VM_NAME/console.log"
  log ""

  export IFACE="$VM_BRIDGE_IF"
  export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES
  "${QEMU_CMD[@]}"

  # Wait a moment for PID file to be created
  sleep 2

  if [ -f "${VM_NAME}.pid" ]; then
    # Fix ownership if running as root via sudo
    if [ "$EUID" -eq 0 ] && [ -n "$SUDO_USER" ]; then
      chown "$SUDO_USER:$(id -gn "$SUDO_USER")" "${VM_NAME}.pid" "${VM_NAME}.qmp" console.log 2>/dev/null || true
    fi

    PID=$(cat "${VM_NAME}.pid")

    # Update registry with running status
    update_vm_status "$VM_NAME" "running" "$PID" ""

    log "✅ VM '$VM_NAME' started successfully (PID: $PID)"
    log ""
    log "Next steps:"
    log "  - Check status: vm status $VM_NAME"
    log "  - View console: tail -f $VM_NAME/console.log"
    log "  - Stop VM: vm stop $VM_NAME"
  else
    error "Failed to start VM '$VM_NAME'"
    exit 1
  fi
fi
