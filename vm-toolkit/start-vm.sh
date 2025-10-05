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
  --vcpus <count>       vCPU count (default: auto-detected, $(get_vcpus) cores)
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

# Parse common arguments but handle missing VMs specially for start command
# First, extract VM name without validating existence
VM_NAME=""
SHOW_HELP=false

# Check if first argument is a VM name (not an option)
if [[ ${#REMAINING_ARGS[@]} -gt 0 && "${REMAINING_ARGS[0]}" != --* ]]; then
  VM_NAME="${REMAINING_ARGS[0]}"
  REMAINING_ARGS=("${REMAINING_ARGS[@]:1}")  # Remove first element
fi

# Parse remaining arguments for --name option
while [[ ${#REMAINING_ARGS[@]} -gt 0 ]]; do
  case "${REMAINING_ARGS[0]}" in
  --name)
    if [[ ${#REMAINING_ARGS[@]} -lt 2 ]]; then
      error "Option --name requires a value"
      show_usage
      exit 1
    fi
    if [[ -n "$VM_NAME" ]]; then
      error "VM name specified multiple times"
      show_usage
      exit 1
    fi
    VM_NAME="${REMAINING_ARGS[1]}"
    REMAINING_ARGS=("${REMAINING_ARGS[@]:2}")  # Remove two elements
    ;;
  --help|-h)
    SHOW_HELP=true
    break
    ;;
  *)
    error "Unknown option: ${REMAINING_ARGS[0]}"
    show_usage
    exit 1
    ;;
  esac
done

if [[ "$SHOW_HELP" == true ]]; then
  show_usage
  exit 0
fi

if [[ -z "$VM_NAME" ]]; then
  error "VM name is required"
  show_usage
  exit 1
fi

# Check if VM exists, if not prompt to create it
VM_DIR=$(get_vm_dir "$VM_NAME")
if [ ! -d "$VM_DIR" ]; then
  prompt_create_vm "$VM_NAME"
  # After creation, VM_DIR should exist
  VM_DIR=$(get_vm_dir "$VM_NAME")
fi



# Ensure we have sudo credentials for QEMU vmnet operations
ensure_sudo

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
  -smp "cores=$VM_VCPUS,threads=1,sockets=1"
  -m "$VM_MEM_MB"
  -drive "if=virtio,file=${VM_NAME}.qcow2,discard=unmap,detect-zeroes=on,cache=writeback"
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
  # Run QEMU with sudo for vmnet access, preserving environment
  export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES
  sudo -E "${QEMU_CMD[@]}"
else
  # Background mode
  QEMU_CMD+=(-pidfile "${VM_NAME}.pid" -qmp "unix:${VM_NAME}.qmp,server,nowait" -display none -serial file:console.log -daemonize)

  log "📋 VM will start in background"
  log "📄 Console output: $(pwd)/console.log"
  log ""

  export IFACE="$VM_BRIDGE_IF"
  export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES
  # Run QEMU with sudo for vmnet access, preserving environment
  sudo -E "${QEMU_CMD[@]}"

  # Wait a moment for PID file to be created
  sleep 2

  if [ -f "${VM_NAME}.pid" ]; then
    # Fix ownership of files created by sudo QEMU process
    # Since QEMU ran with sudo, these files will be owned by root
    current_user=$(whoami)
    current_group=$(id -gn)
    sudo chown "$current_user:$current_group" "${VM_NAME}.pid" "${VM_NAME}.qmp" console.log 2>/dev/null || true

    PID=$(cat "${VM_NAME}.pid")

    # No registry update needed - status computed live

    log "✅ VM '$VM_NAME' started successfully (PID: $PID)"
    log ""
    log "Next steps:"
    log "  - Check status: vm status $VM_NAME"
    log "  - View console: tail -f $(pwd)/console.log"
    log "  - Interactive console: vm console $VM_NAME"
    log "  - Stop VM: vm stop $VM_NAME"
  else
    error "Failed to start VM '$VM_NAME'"
    exit 1
  fi
fi
