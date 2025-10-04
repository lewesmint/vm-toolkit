#!/bin/bash

# VM Registry Management
# Maintains a registry of all VMs and their metadata

set -e

# Get script directory and load config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/vm-config.sh"

# Registry file location (use configured path or default)
REGISTRY_FILE="${REGISTRY_FILE:-${VM_PROJECT_DIR}/.vm-registry.json}"

# Fix registry file ownership if running as root via sudo
fix_registry_ownership() {
  if [ "$EUID" -eq 0 ] && [ -n "$SUDO_USER" ] && [ -f "$REGISTRY_FILE" ]; then
    chown "$SUDO_USER:$(id -gn "$SUDO_USER")" "$REGISTRY_FILE"
  fi
}

# Initialize registry if it doesn't exist
init_registry() {
  if [ ! -f "$REGISTRY_FILE" ]; then
    echo '{"vms": {}, "version": "1.0", "created": "'"$(date -Iseconds)"'"}' >"$REGISTRY_FILE"

    # Fix ownership if running as root via sudo
    if [ "$EUID" -eq 0 ] && [ -n "$SUDO_USER" ]; then
      chown "$SUDO_USER:$(id -gn "$SUDO_USER")" "$REGISTRY_FILE"
    fi

    # Set secure permissions for registry file
    chmod 600 "$REGISTRY_FILE"
    log "Initialized VM registry: $REGISTRY_FILE"
  fi
}

# Add or update VM in registry
register_vm() {
  local vm_name="$1"
  local vm_dir="$2"
  local hostname="$3"
  local username="$4"
  local disk_size="$5"
  local os_version="$6"
  local mac_address="$7"
  local instance_id="$8"
  local architecture="${9:-x86_64}"

  init_registry

  local timestamp
  timestamp=$(date -Iseconds)
  local vm_entry
  vm_entry=$(
    cat <<EOF
{
  "name": "$vm_name",
  "directory": "$vm_dir",
  "hostname": "$hostname",
  "username": "$username",
  "disk_size": "$disk_size",
  "os_version": "$os_version",
  "architecture": "$architecture",
  "mac_address": "$mac_address",
  "instance_id": "$instance_id",
  "created": "$timestamp",
  "updated": "$timestamp",
  "status": "stopped"
}
EOF
  )

  # Use jq if available, otherwise use a simpler approach
  if command -v jq >/dev/null 2>&1; then
    local temp_file
    temp_file=$(mktemp)
    jq --argjson vm "$vm_entry" '.vms[$vm.name] = $vm | .updated = "'"$timestamp"'"' "$REGISTRY_FILE" >"$temp_file"
    mv "$temp_file" "$REGISTRY_FILE"
  else
    # Fallback: simple JSON manipulation (less robust but works)
    local temp_file
    temp_file=$(mktemp)
    if grep -q '"vms": {}' "$REGISTRY_FILE"; then
      # Empty registry
      sed 's/"vms": {}/"vms": {"'"$vm_name"'": '"$vm_entry"'}/' "$REGISTRY_FILE" >"$temp_file"
    else
      # Add to existing registry (basic approach)
      sed 's/"vms": {/"vms": {"'"$vm_name"'": '"$vm_entry"',/' "$REGISTRY_FILE" >"$temp_file"
    fi
    mv "$temp_file" "$REGISTRY_FILE"
  fi

  # Fix ownership if running as root via sudo
  fix_registry_ownership

  log "Registered VM '$vm_name' in registry"
}

# Registry only stores static configuration - no dynamic state
# Dynamic state (status, pid, ip) is computed live from system state

# Get VM architecture from registry
get_vm_architecture() {
  local vm_name="$1"

  if [ ! -f "$REGISTRY_FILE" ]; then
    echo "x86_64"  # Default fallback
    return
  fi

  if command -v jq >/dev/null 2>&1; then
    local arch
    arch=$(jq -r ".vms[\"$vm_name\"].architecture // \"x86_64\"" "$REGISTRY_FILE" 2>/dev/null)
    echo "${arch:-x86_64}"
  else
    # Fallback: try to extract architecture from JSON
    local arch
    arch=$(grep -A 20 "\"$vm_name\"" "$REGISTRY_FILE" | grep '"architecture"' | sed 's/.*"architecture": *"\([^"]*\)".*/\1/' | head -1)
    echo "${arch:-x86_64}"
  fi
}

# Remove VM from registry
unregister_vm() {
  local vm_name="$1"

  if [ ! -f "$REGISTRY_FILE" ]; then
    return 0
  fi

  if command -v jq >/dev/null 2>&1; then
    local temp_file
    temp_file=$(mktemp)
    jq 'del(.vms["'"$vm_name"'"]) | .updated = "'"$(date -Iseconds)"'"' "$REGISTRY_FILE" >"$temp_file"
    mv "$temp_file" "$REGISTRY_FILE"
  else
    # Fallback: mark as updated
    touch "$REGISTRY_FILE"
  fi

  log "Unregistered VM '$vm_name' from registry"
}

# Get VM info from registry
get_vm_info() {
  local vm_name="$1"

  if [ ! -f "$REGISTRY_FILE" ]; then
    return 1
  fi

  if command -v jq >/dev/null 2>&1; then
    jq -r '.vms["'"$vm_name"'"] // empty' "$REGISTRY_FILE"
  else
    # Fallback: basic grep (less reliable)
    grep -o '"'"$vm_name"'": {[^}]*}' "$REGISTRY_FILE" 2>/dev/null || true
  fi
}

# List all VMs in registry
list_vms() {
  init_registry

  if command -v jq >/dev/null 2>&1; then
    jq -r '.vms | keys[]' "$REGISTRY_FILE" 2>/dev/null || true
  else
    # Fallback: basic parsing
    grep -o '"[^"]*": {' "$REGISTRY_FILE" | sed 's/": {$//' | sed 's/^"//' || true
  fi
}

# Get VM status with live checking
get_vm_status() {
  local vm_name="$1"
  local vm_dir="${VM_BASE_DIR}/$vm_name"

  # Check if VM directory exists
  if [ ! -d "$vm_dir" ]; then
    echo "missing"
    return
  fi

  # First check if PID file exists and process is running
  if [ -f "$vm_dir/${vm_name}.pid" ]; then
    local pid
    pid=$(cat "$vm_dir/${vm_name}.pid")
    if kill -0 "$pid" 2>/dev/null; then
      # Quick check if VM is paused via QMP (fast operation)
      local qmp_socket="$vm_dir/${vm_name}.qmp"
      if [ -S "$qmp_socket" ] && command -v socat >/dev/null 2>&1; then
        local qmp_status
        qmp_status=$(timeout 1 bash -c 'echo "{\"execute\":\"qmp_capabilities\"}{\"execute\":\"query-status\"}" | socat - "UNIX-CONNECT:'"$qmp_socket"'"' 2>/dev/null |
          grep -o '"status": "[^"]*"' | cut -d'"' -f4 || echo "running")

        if [ "$qmp_status" = "paused" ]; then
          echo "paused"
          return
        fi
      fi

      # Process is running, now check if it has an IP address
      local vm_ip
      vm_ip=$(get_vm_ip "$vm_name")

      if [ -n "$vm_ip" ]; then
        # Has IP address, check if SSH is ready
        if timeout 2 nc -z "$vm_ip" 22 2>/dev/null; then
          echo "running"  # Fully operational
        else
          echo "booting"  # Has IP but SSH not ready yet
        fi
      else
        # No IP yet, still initializing
        echo "initializing"
      fi
      return
    else
      # Stale PID file
      rm -f "$vm_dir/${vm_name}.pid"
    fi
  fi

  # Check for running QEMU processes even without PID file
  # This handles cases like console mode where PID file might not be created
  local vm_mac=""
  if [ -f "$vm_dir/${vm_name}.mac" ]; then
    vm_mac=$(cat "$vm_dir/${vm_name}.mac")
  fi

  # Look for QEMU processes that match this VM
  local qemu_pids
  if [ -n "$vm_mac" ]; then
    # Search by MAC address (most reliable)
    qemu_pids=$(ps aux | grep "qemu-system-x86_64" | grep "$vm_mac" | grep -v grep | awk '{print $2}' || true)
  else
    # Fallback: search by disk file name
    qemu_pids=$(ps aux | grep "qemu-system-x86_64" | grep "${vm_name}.qcow2" | grep -v grep | awk '{print $2}' || true)
  fi

  if [ -n "$qemu_pids" ]; then
    # Found running QEMU process(es) for this VM
    local first_pid
    first_pid=$(echo "$qemu_pids" | head -1)

    # Create/update PID file if missing
    if [ ! -f "$vm_dir/${vm_name}.pid" ]; then
      echo "$first_pid" > "$vm_dir/${vm_name}.pid"
    fi

    # For performance: just return "running" if we found a process
    # The detailed status checking (IP, SSH) can be done on-demand
    echo "running"
    return
  fi

  echo "stopped"
}

# Get detailed VM status including IP and SSH connectivity (slower)
get_vm_detailed_status() {
  local vm_name="$1"
  local basic_status
  basic_status=$(get_vm_status "$vm_name")

  if [ "$basic_status" = "running" ]; then
    # Only do expensive checks if VM is actually running
    local vm_ip
    vm_ip=$(get_vm_ip "$vm_name")
    if [ -n "$vm_ip" ] && timeout 1 nc -z "$vm_ip" 22 2>/dev/null; then
      echo "running"  # Fully booted and SSH ready
    else
      echo "starting" # Running but not fully booted yet
    fi
  else
    echo "$basic_status"
  fi
}

# Get VM PID (even if PID file is missing)
get_vm_pid() {
  local vm_name="$1"
  local vm_dir="${VM_BASE_DIR}/$vm_name"

  # First try PID file
  if [ -f "$vm_dir/${vm_name}.pid" ]; then
    local pid
    pid=$(cat "$vm_dir/${vm_name}.pid")
    if kill -0 "$pid" 2>/dev/null; then
      echo "$pid"
      return
    fi
  fi

  # Search for running QEMU process
  local vm_mac=""
  if [ -f "$vm_dir/${vm_name}.mac" ]; then
    vm_mac=$(cat "$vm_dir/${vm_name}.mac")
  fi

  local qemu_pids
  if [ -n "$vm_mac" ]; then
    # Search by MAC address (most reliable)
    qemu_pids=$(ps aux | grep "qemu-system-x86_64" | grep "$vm_mac" | grep -v grep | awk '{print $2}' || true)
  else
    # Fallback: search by disk file name
    qemu_pids=$(ps aux | grep "qemu-system-x86_64" | grep "${vm_name}.qcow2" | grep -v grep | awk '{print $2}' || true)
  fi

  if [ -n "$qemu_pids" ]; then
    echo "$qemu_pids" | head -1
  fi
}

# Get VM IP address
get_vm_ip() {
  local vm_name="$1"
  local vm_dir="${VM_BASE_DIR}/$vm_name"

  if [ ! -f "$vm_dir/${vm_name}.mac" ]; then
    return
  fi

  local mac
  mac=$(cat "$vm_dir/${vm_name}.mac")

  # Method 1: Check console log for IP address (most reliable for fresh boots)
  if [ -f "$vm_dir/console.log" ]; then
    local console_ip
    # Look for cloud-init network info table with IP and MAC: "| ens3 | True | 192.168.1.79 | 255.255.255.0 | global | 52:54:00:be:9d:58 |"
    console_ip=$(grep -E '([0-9]{1,3}\.){3}[0-9]{1,3}.*([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}' "$vm_dir/console.log" 2>/dev/null | \
      grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | \
      grep -v '^127\.' | grep -v '255\.255' | head -1)
    if [ -n "$console_ip" ]; then
      echo "$console_ip"
      return
    fi
  fi

  # Method 2: Try hostname resolution (works when DNS is registered)
  local hostname_ip
  hostname_ip=$(nslookup "$vm_name" 2>/dev/null | grep "Address:" | grep -v "#53" | head -1 | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}')
  if [ -n "$hostname_ip" ]; then
    echo "$hostname_ip"
    return
  fi

  # Method 4: Use arp -a but with timeout to prevent hanging (fallback)
  # Handle MAC address format variations (macOS strips leading zeros in hex octets)
  # Convert 52:54:00:8e:d3:f6 to pattern that matches 52:54:0:8e:d3:f6
  local mac_no_leading_zeros
  mac_no_leading_zeros=$(echo "$mac" | sed 's/:0\([0-9a-f]\)/:\1/g')

  # Try both formats: with and without leading zeros
  local arp_result
  arp_result=$(timeout 2 arp -a 2>/dev/null | grep -E "($mac|$mac_no_leading_zeros)" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
  if [ -n "$arp_result" ]; then
    echo "$arp_result"
  fi
}

# Sync registry - only remove missing VMs (no dynamic state updates)
sync_registry() {
  init_registry

  log "Syncing registry - removing missing VMs..."

  # Find and remove phantom VMs (VMs in registry but directory missing)
  local phantom_vms=()
  for vm_name in $(list_vms); do
    if [ ! -d "${VM_BASE_DIR}/$vm_name" ]; then
      # VM directory doesn't exist - mark as phantom for removal
      phantom_vms+=("$vm_name")
      warn "Found phantom VM in registry: $vm_name (directory missing)"
    fi
  done

  # Remove phantom VMs from registry
  for vm_name in "${phantom_vms[@]}"; do
    log "Removing phantom VM from registry: $vm_name"
    unregister_vm "$vm_name"
  done

  # Discover unregistered VMs
  for vm_dir in "${VM_BASE_DIR}"/*/; do
    if [ -d "$vm_dir" ]; then
      local vm_name
      vm_name=$(basename "$vm_dir")
      # Skip hidden directories and non-VM directories
      if [[ "$vm_name" == .* ]] || [ ! -f "$vm_dir/${vm_name}.qcow2" ]; then
        continue
      fi

      # Check if VM is registered
      if [ -z "$(get_vm_info "$vm_name")" ]; then
        warn "Found unregistered VM: $vm_name"
        # Try to register with basic info
        local hostname="$vm_name"
        local username="ubuntu"
        local disk_size="unknown"
        local ubuntu_version="unknown"
        local mac_address=""
        local instance_id="unknown"

        if [ -f "$vm_dir/${vm_name}.mac" ]; then
          mac_address=$(cat "$vm_dir/${vm_name}.mac")
        fi

        if [ -f "$vm_dir/cloud-init/instance-id" ]; then
          instance_id=$(cat "$vm_dir/cloud-init/instance-id")
        fi

        register_vm "$vm_name" "$vm_dir" "$hostname" "$username" "$disk_size" "$ubuntu_version" "$mac_address" "$instance_id"
      fi
    fi
  done

  log "Registry sync complete"
}

# Show registry statistics
show_registry_stats() {
  init_registry
  sync_registry

  local total_vms
  total_vms=$(list_vms | wc -l)
  local running_vms=0
  local stopped_vms=0

  # Compute live status for each VM
  for vm_name in $(list_vms); do
    local status
    status=$(get_vm_status "$vm_name")
    if [ "$status" = "running" ] || [ "$status" = "initializing" ] || [ "$status" = "booting" ]; then
      running_vms=$((running_vms + 1))
    else
      stopped_vms=$((stopped_vms + 1))
    fi
  done

  echo "VM Registry Statistics:"
  echo "  Total VMs: $total_vms"
  echo "  Running: $running_vms"
  echo "  Stopped: $stopped_vms"
  echo "  Registry file: $REGISTRY_FILE"
}

# Export registry functions for use by other scripts
if [ "${BASH_SOURCE[0]}" != "${0}" ]; then
  # Being sourced, export functions
  export -f init_registry register_vm unregister_vm
  export -f get_vm_info list_vms get_vm_status get_vm_pid get_vm_ip get_vm_architecture sync_registry
fi
