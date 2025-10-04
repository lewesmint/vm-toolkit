#!/bin/bash

# VM Toolkit Common Functions
# Single source of truth for shared functionality

# Common argument parsing patterns
parse_common_args() {
    local vm_name=""
    local show_help=false
    local remaining_args=()

    while [[ $# -gt 0 ]]; do
        case $1 in
            --name)
                vm_name="$2"
                shift 2
                ;;
            --help)
                show_help=true
                shift
                ;;
            *)
                remaining_args+=("$1")
                shift
                ;;
        esac
    done

    if [ "$show_help" = true ]; then
        show_usage
        exit 0
    fi

    if [ -z "$vm_name" ]; then
        error "VM name is required"
        show_usage
        exit 1
    fi

    # Set global VM_NAME
    VM_NAME="$vm_name"

    # Return remaining args as space-separated string
    if [ ${#remaining_args[@]} -gt 0 ]; then
        printf '%s ' "${remaining_args[@]}"
    fi
}

# Ensure VM exists and return secure directory
ensure_vm_exists() {
    local vm_name="$1"
    local vm_dir
    
    vm_dir=$(get_vm_dir "$vm_name")
    if [ ! -d "$vm_dir" ]; then
        error "VM '$vm_name' not found"
        exit 1
    fi
    
    echo "$vm_dir"
}

# Get VM PID with validation
get_vm_pid() {
    local vm_name="$1"
    local vm_dir="$2"
    local pid_file="$vm_dir/${vm_name}.pid"

    if [ ! -f "$pid_file" ]; then
        return 1  # No PID file
    fi

    local pid
    pid=$(cat "$pid_file")

    # Check if process exists (handle both user and root-owned processes)
    if ! ps -p "$pid" >/dev/null 2>&1; then
        # Stale PID file
        rm -f "$pid_file"
        return 1
    fi

    echo "$pid"
}

# Check if VM is running
is_vm_running() {
    local vm_name="$1"
    local vm_dir="$2"
    
    get_vm_pid "$vm_name" "$vm_dir" >/dev/null
}

# Ensure VM is running
ensure_vm_running() {
    local vm_name="$1"
    local vm_dir="$2"
    
    if ! is_vm_running "$vm_name" "$vm_dir"; then
        error "VM '$vm_name' is not running"
        exit 1
    fi
}

# Ensure VM is not running
ensure_vm_stopped() {
    local vm_name="$1"
    local vm_dir="$2"

    if is_vm_running "$vm_name" "$vm_dir"; then
        error "VM '$vm_name' is already running"
        exit 1
    fi
}

# Get VM status from registry
get_vm_registry_status() {
    local vm_name="$1"

    if [ ! -f "$REGISTRY_FILE" ]; then
        echo "unknown"
        return
    fi

    jq -r ".vms[\"$vm_name\"].status // \"unknown\"" "$REGISTRY_FILE" 2>/dev/null || echo "unknown"
}

# Ensure VM is in running state (not paused)
ensure_vm_state_running() {
    local vm_name="$1"
    local vm_dir="$2"

    # First check if VM process exists
    if ! is_vm_running "$vm_name" "$vm_dir"; then
        error "VM '$vm_name' is not running"
        exit 1
    fi

    # Then check if it's in running state (not paused)
    local status
    status=$(get_vm_registry_status "$vm_name")
    if [ "$status" != "running" ]; then
        error "VM '$vm_name' is not in running state (current: $status)"
        exit 1
    fi
}

# Ensure VM is in paused state
ensure_vm_state_paused() {
    local vm_name="$1"
    local vm_dir="$2"

    # First check if VM process exists
    if ! is_vm_running "$vm_name" "$vm_dir"; then
        error "VM '$vm_name' is not running"
        exit 1
    fi

    # Then check if it's in paused state
    local status
    status=$(get_vm_registry_status "$vm_name")
    if [ "$status" != "paused" ]; then
        error "VM '$vm_name' is not paused (current: $status)"
        exit 1
    fi
}

# QMP command wrapper
qmp_command() {
    local socket="$1"
    local command="$2"
    
    if [ ! -S "$socket" ] || ! command -v socat >/dev/null 2>&1; then
        return 1
    fi
    
    echo '{"execute":"qmp_capabilities"}'"$command" | \
        socat - "UNIX-CONNECT:$socket" 2>/dev/null
}

# Common QMP operations
qmp_stop() {
    local vm_dir="$1"
    local vm_name="$2"
    qmp_command "$vm_dir/${vm_name}.qmp" '{"execute":"stop"}'
}

qmp_cont() {
    local vm_dir="$1"
    local vm_name="$2"
    qmp_command "$vm_dir/${vm_name}.qmp" '{"execute":"cont"}'
}

qmp_powerdown() {
    local vm_dir="$1"
    local vm_name="$2"
    qmp_command "$vm_dir/${vm_name}.qmp" '{"execute":"system_powerdown"}'
}

# Parse VM operation arguments and set globals
# Call this function directly (not in subshell) to set VM_NAME and VM_DIR
# Accepts VM name as first positional argument or --name option
parse_vm_operation_args() {
    local vm_name=""
    local show_help=false

    # Check if first argument is a VM name (not an option)
    if [[ $# -gt 0 && "$1" != --* ]]; then
        vm_name="$1"
        shift
    fi

    while [[ $# -gt 0 ]]; do
        case $1 in
            --name)
                if [ -n "$vm_name" ]; then
                    error "VM name specified both as positional argument and --name option"
                    exit 1
                fi
                vm_name="$2"
                shift 2
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                # Unknown argument - let script handle it
                break
                ;;
        esac
    done

    if [ -z "$vm_name" ]; then
        error "VM name is required as first argument"
        show_usage
        exit 1
    fi

    # Set global variables (this works because function is not called in subshell)
    VM_NAME="$vm_name"
    VM_DIR=$(ensure_vm_exists "$VM_NAME")

    # Set up cleanup trap
    setup_cleanup_trap "$VM_NAME" "$VM_DIR"
}

# Cleanup function for VM operations
cleanup_vm_operation() {
    local vm_name="$1"
    local vm_dir="$2"
    local exit_code="${3:-0}"
    
    # Add any cleanup logic here
    # For now, just update registry status if needed
    if [ "$exit_code" -ne 0 ]; then
        # Operation failed, ensure registry reflects reality
        sync_registry 2>/dev/null || true
    fi
}

# Set up cleanup trap
setup_cleanup_trap() {
    local vm_name="$1"
    local vm_dir="$2"

    trap 'cleanup_vm_operation "$vm_name" "$vm_dir" $?' EXIT
}

# Common show_usage pattern for VM operations
show_vm_usage() {
    local script_name="$1"
    local description="$2"
    local extra_options="$3"

    cat << EOF
Usage: $script_name <vm-name> [options]
   or: $script_name --name <vm-name> [options]

$description

Required:
  <vm-name>             VM name (first argument)

Options:
$extra_options
  --help                Show this help

Examples:
  $script_name myvm
  $script_name --name myvm
EOF
}

# Force kill a VM process
force_kill_vm() {
    local vm_name="$1"
    local vm_dir="$2"
    local pid="$3"

    log "Force killing VM: $vm_name (PID: $pid)"
    if kill -KILL "$pid" 2>/dev/null; then
        rm -f "$vm_dir/${vm_name}.pid"
        # No registry update needed - status computed live
        return 0
    else
        warn "Failed to kill process $pid"
        return 1
    fi
}

# Wait for VM to stop gracefully
wait_for_vm_stop() {
    local vm_name="$1"
    local vm_dir="$2"
    local pid="$3"
    local timeout="${4:-30}"

    log "Waiting up to ${timeout}s for graceful shutdown..."
    for ((i = 1; i <= timeout; i++)); do
        if ! kill -0 "$pid" 2>/dev/null; then
            rm -f "$vm_dir/${vm_name}.pid"
            # No registry update needed - status computed live
            log "✅ VM '$vm_name' stopped gracefully"
            return 0
        fi
        sleep 1
    done

    return 1  # Timeout
}
