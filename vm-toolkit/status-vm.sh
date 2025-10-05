#!/bin/bash

# VM Status Script
# Shows status of VMs using the registry

set -e

# Get script directory and load config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/vm-config.sh"
source "$SCRIPT_DIR/vm-registry.sh"

show_usage() {
  cat <<EOF
Usage: $0 [vm-name] [options]

Show status of VMs.

Options:
  vm-name               Show status for specific VM (positional argument)
  --name <name>         Show status for specific VM (alternative syntax)
  --all                 Show all VMs (default if no name specified)
  --json                Output in JSON format
  --sync                Sync registry before showing status
  --help                Show this help

Examples:
  $0                    # Show all VMs
  $0 myvm               # Show specific VM (positional)
  $0 --name myvm        # Show specific VM (named argument)
  $0 --all --json       # Show all VMs in JSON format
  $0 --sync             # Sync registry and show all VMs
EOF
}

# Parse command line arguments
VM_NAME=""
SHOW_ALL=true
OUTPUT_JSON=false
SYNC_FIRST=false

while [[ $# -gt 0 ]]; do
  case $1 in
  --name)
    VM_NAME="$2"
    SHOW_ALL=false
    shift 2
    ;;
  --all)
    SHOW_ALL=true
    shift
    ;;
  --json)
    OUTPUT_JSON=true
    shift
    ;;
  --sync)
    SYNC_FIRST=true
    shift
    ;;
  --help)
    show_usage
    exit 0
    ;;
  -*)
    error "Unknown option: $1"
    show_usage
    exit 1
    ;;
  *)
    # Positional argument - treat as VM name
    if [ -z "$VM_NAME" ]; then
      VM_NAME="$1"
      SHOW_ALL=false
    else
      error "Multiple VM names specified: '$VM_NAME' and '$1'"
      show_usage
      exit 1
    fi
    shift
    ;;
  esac
done

# Sync registry if requested
if [ "$SYNC_FIRST" = true ]; then
  sync_registry
fi

# Function to get detailed VM status
get_detailed_status() {
  local vm_name="$1"
  local vm_dir="${VM_BASE_DIR}/$vm_name"

  # Basic info
  local status
  status=$(get_vm_status "$vm_name")
  local ip
  ip=$(get_vm_ip "$vm_name")
  local pid=""
  local uptime=""
  local ssh_status="unknown"

  # Get PID if running
  if [ "$status" = "running" ]; then
    pid=$(get_vm_pid "$vm_name")

    # Get uptime (macOS ps format)
    if [ -n "$pid" ]; then
      uptime=$(ps -o etime= -p "$pid" 2>/dev/null | tr -d ' ' || echo "unknown")
    fi

    # Test SSH connectivity if we have an IP
    if [ -n "$ip" ]; then
      if timeout 3 nc -z "$ip" 22 2>/dev/null; then
        ssh_status="available"
      else
        ssh_status="not_ready"
      fi
    fi
  fi

  # Get VM metadata
  local hostname="$vm_name"
  local username="ubuntu"
  local mac=""
  local disk_size="unknown"
  local ubuntu_version="unknown"

  if [ -f "$vm_dir/${vm_name}.mac" ]; then
    mac=$(cat "$vm_dir/${vm_name}.mac")
  fi

  if [ -f "$vm_dir/cloud-init/user-data" ]; then
    hostname=$(grep "^hostname:" "$vm_dir/cloud-init/user-data" | cut -d' ' -f2 || echo "$vm_name")
    username=$(grep -A5 "^users:" "$vm_dir/cloud-init/user-data" | grep "name:" | head -1 | sed 's/.*name: *//' || echo "ubuntu")
  fi

  # Disk size available from registry (set during creation)
  disk_size=$(jq -r ".vms[\"$vm_name\"].disk_size // \"unknown\"" "$REGISTRY_FILE" 2>/dev/null || echo "unknown")

  if [ -f "$vm_dir/${vm_name}-base.img" ]; then
    ubuntu_version=$(basename "$vm_dir/${vm_name}-base.img" | cut -d'-' -f1)
  fi

  # Output format
  if [ "$OUTPUT_JSON" = true ]; then
    cat <<EOF
{
  "name": "$vm_name",
  "status": "$status",
  "hostname": "$hostname",
  "username": "$username",
  "ip_address": "$ip",
  "mac_address": "$mac",
  "pid": "$pid",
  "uptime": "$uptime",
  "ssh_status": "$ssh_status",
  "memory_mb": $(get_vm_memory_mb "$vm_name"),
  "vcpus": $(get_vm_vcpus "$vm_name"),
  "disk_size": "$disk_size",
  "ubuntu_version": "$ubuntu_version",
  "directory": "$vm_dir"
}
EOF
  else
    # Human readable format
    echo "VM: $vm_name"
    echo "  Status: $status"
    echo "  Hostname: $hostname"
    echo "  Username: $username"
    echo "  IP Address: ${ip:-N/A}"
    echo "  MAC Address: $mac"
    echo "  SSH: $ssh_status"
    if [ "$status" = "running" ]; then
      echo "  PID: $pid"
      echo "  Uptime: $uptime"
    fi
    echo "  Memory: $(get_vm_memory_mb "$vm_name")MB"
    echo "  vCPUs: $(get_vm_vcpus "$vm_name")"
    echo "  Disk Size: $disk_size"
    echo "  Ubuntu: $ubuntu_version"
    echo "  Directory: $vm_dir"

    if [ -n "$ip" ] && [ "$ssh_status" = "available" ]; then
      echo "  SSH Command: ssh $username@$hostname"
    fi
    echo
  fi
}

# Function to show summary table
show_summary_table() {
  printf "%-12s %-10s %-15s %-20s %-10s\n" "VM NAME" "STATUS" "IP ADDRESS" "SSH COMMAND" "UPTIME"
  printf "%-12s %-10s %-15s %-20s %-10s\n" "--------" "------" "----------" "-----------" "-------"

  for vm_name in $(list_vms | sort); do
    local status
    status=$(get_vm_status "$vm_name")
    local ip="N/A"
    local ssh_cmd="N/A"
    local uptime="N/A"

    # Only do expensive operations for running VMs
    if [ "$status" = "running" ]; then
      local vm_dir="${VM_BASE_DIR}/$vm_name"
      local pid
      pid=$(get_vm_pid "$vm_name")
      if [ -n "$pid" ]; then
        uptime=$(ps -o etime= -p "$pid" 2>/dev/null | tr -d ' ' || echo "unknown")
      fi

      # Get IP address (potentially slow)
      ip=$(get_vm_ip "$vm_name")

      if [ -n "$ip" ] && [ "$ip" != "N/A" ]; then
        local username="ubuntu"
        if [ -f "$vm_dir/cloud-init/user-data" ]; then
          username=$(grep -A5 "^users:" "$vm_dir/cloud-init/user-data" | grep "name:" | head -1 | sed 's/.*name: *//' || echo "ubuntu")
        fi

        # Quick SSH connectivity test
        if timeout 1 nc -z "$ip" 22 2>/dev/null; then
          # Get hostname for SSH command
          local vm_hostname="$vm_name"
          if [ -f "$vm_dir/cloud-init/user-data" ]; then
            vm_hostname=$(grep "^hostname:" "$vm_dir/cloud-init/user-data" | cut -d' ' -f2 || echo "$vm_name")
          fi
          ssh_cmd="ssh $username@$vm_hostname"
        else
          ssh_cmd="ssh not ready"
        fi
      else
        ip="N/A"
      fi
    fi

    printf "%-12s %-10s %-15s %-20s %-10s\n" "$vm_name" "$status" "$ip" "$ssh_cmd" "$uptime"
  done
}

# Main execution
init_registry

if [ "$SHOW_ALL" = true ]; then
  # Show all VMs
  vm_list=$(list_vms)

  if [ -z "$vm_list" ]; then
    echo "No VMs found."
    echo "Create one with: vm create --name <vm-name>"
    exit 0
  fi

  if [ "$OUTPUT_JSON" = true ]; then
    echo "{"
    echo '  "vms": ['
    first=true
    for vm_name in $(echo "$vm_list" | sort); do
      if [ "$first" = false ]; then
        echo ","
      fi
      get_detailed_status "$vm_name" | sed 's/^/    /'
      first=false
    done
    echo
    echo "  ],"
    echo '  "timestamp": "'"$(date -Iseconds)"'"'
    echo "}"
  else
    echo "🏗️  VM Status Overview"
    echo "===================="
    show_summary_table
    echo
    show_registry_stats
  fi
else
  # Show specific VM
  if [ -z "$VM_NAME" ]; then
    error "VM name is required when not showing all VMs"
    show_usage
    exit 1
  fi

  if [ -z "$(get_vm_info "$VM_NAME")" ] && [ ! -d "${VM_BASE_DIR}/$VM_NAME" ]; then
    error "VM '$VM_NAME' not found"
    exit 1
  fi

  get_detailed_status "$VM_NAME"
fi
