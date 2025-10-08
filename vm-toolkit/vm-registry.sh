#!/bin/bash

# VM Registry Management
# Maintains a registry of all VMs and their metadata

set -e

# Get script directory and load config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/vm-config.sh"

# Registry file location (use configured path or default)
REGISTRY_FILE="${REGISTRY_FILE:-${VM_PROJECT_DIR}/.vm-registry.json}"

# Optional fast-mode caches (populated when VM_STATUS_FAST=true)
__VM_FAST_CACHE_INIT=false
__ARP_CACHE=""
__QEMU_PS_CACHE=""
# Resolve hostname to candidate IPv4s using fast, cache-bypassing tools when possible.
# Returns unique newline-separated IPv4 addresses. Prefer dig (bypasses OS caches),
# then fall back to dscacheutil on macOS. Does not guarantee the IP belongs to this VM.

vm_fast_cache_init() {
  if [ "${VM_STATUS_FAST:-false}" = true ] && [ "$__VM_FAST_CACHE_INIT" != true ]; then
    # Cache ARP table and QEMU processes once per invocation to reduce latency
    __ARP_CACHE=$(arp -a 2>/dev/null || true)
    __QEMU_PS_CACHE=$(ps aux | grep "qemu-system-" | grep -v grep || true)
    __VM_FAST_CACHE_INIT=true
  fi
}

vm_fast_get_arp() {
  if [ "${VM_STATUS_FAST:-false}" = true ]; then
    vm_fast_cache_init
    echo "$__ARP_CACHE"
  else
    arp -a 2>/dev/null || true
  fi
}

vm_fast_get_qemu_ps() {
  if [ "${VM_STATUS_FAST:-false}" = true ]; then
    vm_fast_cache_init
    echo "$__QEMU_PS_CACHE"
  else
    ps aux | grep "qemu-system-" | grep -v grep || true
  fi
}

# Resolve hostname to candidate IPv4s using fast, cache-bypassing tools when possible.
# Returns unique newline-separated IPv4 addresses. Prefer dig (bypasses OS caches),
# then fall back to dscacheutil on macOS. Does not guarantee the IP belongs to this VM.
resolve_dns_ipv4_candidates() {
  local hostname="$1"
  local out=""

  local pref
  pref=$(get_dns_preference)

  # Helper to append dig results
  _append_dig() {
    if command -v dig >/dev/null 2>&1; then
      local dig_out
      dig_out=$(dig +short A "$hostname" 2>/dev/null | grep -E '^[0-9]+(\.[0-9]+){3}$' || true)
      if [ -n "$dig_out" ]; then out+="$dig_out"$'\n'; fi
      if [[ "$hostname" != *.* ]]; then
        local dig_local
        dig_local=$(dig +short A "${hostname}.local" 2>/dev/null | grep -E '^[0-9]+(\.[0-9]+){3}$' || true)
        if [ -n "$dig_local" ]; then out+="$dig_local"$'\n'; fi
      fi
    fi
  }

  # Helper to append dscacheutil result
  _append_dscache() {
    if command -v dscacheutil >/dev/null 2>&1; then
      local ds_out
      ds_out=$(dscacheutil -q host -a name "$hostname" 2>/dev/null | awk '/ip_address:/ {print $2}')
      if [ -n "$ds_out" ]; then out+="$ds_out"$'\n'; fi
    fi
  }

  case "$pref" in
    dig-first)
      _append_dig; _append_dscache ;;
    dscache-first)
      _append_dscache; _append_dig ;;
    dig-only)
      _append_dig ;;
    dscache-only)
      _append_dscache ;;
    *)
      _append_dig; _append_dscache ;;
  esac

  # Deduplicate while preserving order
  if [ -n "$out" ]; then
    echo "$out" | awk '!seen[$0]++'
  fi
}

# Extract candidate IPs from the VM console log (best-effort)
get_vm_ips_from_console() {
  local vm_name="$1"
  local vm_dir="${VM_BASE_DIR}/$vm_name"

  local console_file="$vm_dir/console.log"
  if [ ! -f "$console_file" ]; then
    return
  fi

  # Read last 400 lines, extract IPv4s, filter non-routable, prefer RFC1918 ranges and preserve order
  tail -n 400 "$console_file" 2>/dev/null |
    grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' |
    awk 'BEGIN{seen[""]=0} {
      ip=$0;
      # quick sanity: octets 0-255
      split(ip, o, ".");
      valid=1; for(i=1;i<=4;i++){ if(o[i]<0 || o[i]>255){ valid=0; break } }
      if(!valid) next;
      # exclude non-routable/special addresses
      if (ip=="0.0.0.0") next;              # unspecified
      if (o[1]==127) next;                   # loopback
      if (o[1]==169 && o[2]==254) next;      # link-local
      if (ip=="255.255.255.255") next;      # broadcast
      if (o[1]>=224) next;                   # multicast/reserved (224+)
      # prefer RFC1918 addresses
      rfc1918 = (o[1]==10) || (o[1]==172 && o[2]>=16 && o[2]<=31) || (o[1]==192 && o[2]==168);
      if(!(ip in seen)){
        # tag with preference score (lower is better)
        score = rfc1918 ? 0 : 1;
        print score, ip;
        seen[ip]=1;
      }
    }' |
    sort -k1,1n |
    awk '{print $2}'
}

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
  local memory_mb="${10:-$(get_mem_mb)}"
  local vcpus="${11:-$(get_vcpus)}"

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
  "memory_mb": $memory_mb,
  "vcpus": $vcpus,
  "os_version": "$os_version",
  "architecture": "$architecture",
  "mac_address": "$mac_address",
  "instance_id": "$instance_id",
  "created": "$timestamp",
  "updated": "$timestamp"
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

# Get VM memory from registry
get_vm_memory_mb() {
  local vm_name="$1"

  if [ ! -f "$REGISTRY_FILE" ]; then
    get_mem_mb  # Default fallback
    return
  fi

  if command -v jq >/dev/null 2>&1; then
    local memory_mb
    memory_mb=$(jq -r ".vms[\"$vm_name\"].memory_mb // empty" "$REGISTRY_FILE" 2>/dev/null)
    if [ -n "$memory_mb" ] && [ "$memory_mb" != "null" ]; then
      echo "$memory_mb"
    else
      get_mem_mb  # Fallback to default
    fi
  else
    get_mem_mb  # Fallback to default
  fi
}

# Get VM vCPUs from registry
get_vm_vcpus() {
  local vm_name="$1"

  if [ ! -f "$REGISTRY_FILE" ]; then
    get_vcpus  # Default fallback
    return
  fi

  if command -v jq >/dev/null 2>&1; then
    local vcpus
    vcpus=$(jq -r ".vms[\"$vm_name\"].vcpus // empty" "$REGISTRY_FILE" 2>/dev/null)
    if [ -n "$vcpus" ] && [ "$vcpus" != "null" ]; then
      echo "$vcpus"
    else
      get_vcpus  # Fallback to default
    fi
  else
    get_vcpus  # Fallback to default
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
    # Check if process exists (handle both user and root processes)
    if ps -p "$pid" >/dev/null 2>&1; then
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
      if [ "${VM_STATUS_FAST:-false}" = true ] || [ "${VM_STATUS_BASIC:-false}" = true ]; then
        vm_ip=$(get_vm_ip "$vm_name")
      else
        vm_ip=$(get_vm_best_ip "$vm_name")
      fi

      if [ -n "$vm_ip" ]; then
        # Has IP address, check if SSH is ready
        if [ "${VM_STATUS_BASIC:-false}" = true ]; then
          echo "running"
        elif [ "${VM_STATUS_FAST:-false}" = true ]; then
          echo "running"  # Assume running in fast mode
        elif timeout 2 nc -z "$vm_ip" 22 2>/dev/null; then
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
      # Stale PID file - clean it up
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
    qemu_pids=$(vm_fast_get_qemu_ps | grep "qemu-system-x86_64" | grep "$vm_mac" | awk '{print $2}' || true)
  else
    # Fallback: search by disk file name
    qemu_pids=$(vm_fast_get_qemu_ps | grep "qemu-system-x86_64" | grep "${vm_name}.qcow2" | awk '{print $2}' || true)
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
    # Check if process exists (handle both user and root processes)
    if ps -p "$pid" >/dev/null 2>&1; then
      echo "$pid"
      return
    else
      # Clean up stale PID file
      rm -f "$vm_dir/${vm_name}.pid"
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

# Get VM IP address (only if VM is actually running)
get_vm_ip() {

  local vm_name="$1"
  local vm_dir="${VM_BASE_DIR}/$vm_name"

  # First check if VM is actually running - don't return stale IPs
  local vm_pid
  vm_pid=$(get_vm_pid "$vm_name")
  if [ -z "$vm_pid" ]; then
    # VM not running, don't return stale IP addresses

    return
  fi

  if [ ! -f "$vm_dir/${vm_name}.mac" ]; then
    return
  fi

  local mac
  mac=$(cat "$vm_dir/${vm_name}.mac" | tr 'A-F' 'a-f')

  # Normalize target MAC to zero-padded lowercase (xx:xx:xx:xx:xx:xx)
  local target_mac
  target_mac=$(echo "$mac" | awk 'BEGIN{FS=":";OFS=":"} {for(i=1;i<=NF;i++){ if(length($i)==1){$i="0"$i} else if(length($i)==0){$i="00"} else {$i=tolower($i)} } print }')

  # Parse ARP table and return first matching IP by normalizing each MAC from output
  # Works on macOS and Linux
  local all_ips
  all_ips=$(vm_fast_get_arp | awk -v tgt="$target_mac" '
    {
      ip=""; mac="";
      # macOS: ? (192.168.1.50) at 52:54:0:64:b4:d0 on en0 ifscope [ethernet]
      # Linux: ? (192.168.1.50) at 52:54:00:64:b4:d0 [ether] on br0
      for (i=1;i<=NF;i++) {
        if ($i ~ /^\(/) { gsub(/[()]/, "", $i); ip=$i; }
        if ($i == "at") { if (i+1<=NF) { mac=$(i+1); } }
      }
      if (ip != "" && mac != "") {
        # normalize mac from ARP: split, left-pad to 2, lowercase
        n=split(mac, a, ":");
        if (n==6) {
          for (j=1;j<=6;j++) {
            m=a[j];
            gsub(/[^0-9A-Fa-f]/, "", m);
            if (length(m)==1) m="0" m;
            if (length(m)==0) m="00";
            a[j]=tolower(m);
          }
          norm=a[1]":"a[2]":"a[3]":"a[4]":"a[5]":"a[6];
          if (norm==tgt) { print ip; exit } # first match only
        }
      }
    }')

  echo "$all_ips" | head -1

  # Fallback: try resolving by hostname via system resolver (macOS dscacheutil)
  # This helps when ARP cache hasn't learned the VM yet but DNS/mDNS has
  if [ -z "$all_ips" ] && [ "${VM_STATUS_FAST:-false}" != true ]; then
    local hostname="$vm_name"
    if [ -f "$vm_dir/cloud-init/user-data" ]; then
      local ci_hn
      ci_hn=$(grep -E "^hostname:" "$vm_dir/cloud-init/user-data" | awk '{print $2}' | tr -d '\r')
      if [ -n "$ci_hn" ]; then hostname="$ci_hn"; fi
    fi

    if command -v dscacheutil >/dev/null 2>&1; then
      local dns_ip
      dns_ip=$(dscacheutil -q host -a name "$hostname" 2>/dev/null | awk '/ip_address:/ {print $2; exit}')
      if [ -n "$dns_ip" ]; then
        # Try to populate ARP quickly (non-fatal if it fails)
  (timeout 1 nc -z "$dns_ip" 22 >/dev/null 2>&1 || ping -c 1 -t 1 "$dns_ip" >/dev/null 2>&1) || true
        # Verify MAC if we can
        local arp_line mac_out norm_out
        arp_line=$(arp -n "$dns_ip" 2>/dev/null | head -1)
        mac_out=$(echo "$arp_line" | awk '{for(i=1;i<=NF;i++){if($i=="at" && i+1<=NF){print $(i+1); exit}}}')
        if [ -n "$mac_out" ]; then
          norm_out=$(echo "$mac_out" | awk 'BEGIN{FS=":";OFS=":"} {for(i=1;i<=NF;i++){ m=$i; gsub(/[^0-9A-Fa-f]/, "", m); if(length(m)==1){m="0"m} if(length(m)==0){m="00"} $i=tolower(m)} print }')
          if [ "$norm_out" = "$target_mac" ]; then
            echo "$dns_ip"
            return
          fi
        fi
        # If we can't verify MAC, still return DNS IP as best effort
        echo "$dns_ip"
        return
      fi
    fi
  fi
}

# Return all ARP IPs for a VM's MAC (space/newline separated)
get_vm_ips_for_mac() {
  local vm_name="$1"
  local vm_dir="${VM_BASE_DIR}/$vm_name"

  if [ ! -f "$vm_dir/${vm_name}.mac" ]; then
    return
  fi

  local mac
  mac=$(cat "$vm_dir/${vm_name}.mac" | tr 'A-F' 'a-f')
  local target_mac
  target_mac=$(echo "$mac" | awk 'BEGIN{FS=":";OFS=":"} {for(i=1;i<=NF;i++){ if(length($i)==1){$i="0"$i} else if(length($i)==0){$i="00"} else {$i=tolower($i)} } print }')

  # Return all matching IPs for this MAC (space/newline separated)
  vm_fast_get_arp | awk -v tgt="$target_mac" '
    {
      ip=""; mac="";
      for (i=1;i<=NF;i++) {
        if ($i ~ /^\(/) { gsub(/[()]/, "", $i); ip=$i; }
        if ($i == "at") { if (i+1<=NF) { mac=$(i+1); } }
      }
      if (ip != "" && mac != "") {
        n=split(mac, a, ":");
        if (n==6) {
          for (j=1;j<=6;j++) {
            m=a[j];
            gsub(/[^0-9A-Fa-f]/, "", m);
            if (length(m)==1) m="0" m;
            if (length(m)==0) m="00";
            a[j]=tolower(m);
          }
          norm=a[1]":"a[2]":"a[3]":"a[4]":"a[5]":"a[6];
          if (norm==tgt) { print ip }
        }
      }
    }'
}

# Choose the best current IP for status display by probing SSH when needed
get_vm_best_ip() {
  local vm_name="$1"

  # Only consider when VM is actually running
  local vm_pid
  vm_pid=$(get_vm_pid "$vm_name")
  if [ -z "$vm_pid" ]; then
    return
  fi

  local ips
  ips=$(get_vm_ips_for_mac "$vm_name")

  # Optionally include DNS-resolved IP even if ARP has entries (to avoid stale ARP)
  local vm_dir="${VM_BASE_DIR}/$vm_name"
  local hostname="$vm_name"
  local dns_ip=""
  # Prepare target MAC for verification of DNS entries
  local target_mac=""
  if [ -f "$vm_dir/${vm_name}.mac" ]; then
    local mac
    mac=$(cat "$vm_dir/${vm_name}.mac" | tr 'A-F' 'a-f')
    target_mac=$(echo "$mac" | awk 'BEGIN{FS=":";OFS=":"} {for(i=1;i<=NF;i++){ if(length($i)==1){$i="0"$i} else if(length($i)==0){$i="00"} else {$i=tolower($i)} } print }')
  fi
  if [ "${VM_STATUS_FAST:-false}" != true ]; then
    if [ -f "$vm_dir/cloud-init/user-data" ]; then
      local ci_hn
      ci_hn=$(grep -E "^hostname:" "$vm_dir/cloud-init/user-data" | awk '{print $2}' | tr -d '\r')
      if [ -n "$ci_hn" ]; then hostname="$ci_hn"; fi
    fi
    # Collect DNS candidates via dig and dscacheutil
    dns_candidates=$(resolve_dns_ipv4_candidates "$hostname" 2>/dev/null || true)
  fi

  # Build candidate list: prefer ARP IPs that match the VM MAC; only include DNS IP if its ARP MAC matches
  local candidates=""
  if [ -n "$ips" ]; then
    # Add ARP-derived IPs first (authoritative for MAC match)
    for ip in $ips; do
      candidates+=" $ip"
    done
    candidates=$(echo "$candidates" | sed -e 's/^ *//')
  fi

  # Consider DNS IPs only if we can verify MAC matches this VM
  if [ -n "$dns_candidates" ] && [ -n "$target_mac" ]; then
    for dns_ip in $dns_candidates; do
      # Nudge ARP to learn the MAC quickly (best-effort)
      (timeout 1 nc -z "$dns_ip" 22 >/dev/null 2>&1 || ping -c 1 -t 1 "$dns_ip" >/dev/null 2>&1) || true
      local arp_line mac_out norm_out
      arp_line=$(arp -n "$dns_ip" 2>/dev/null | head -1)
      mac_out=$(echo "$arp_line" | awk '{for(i=1;i<=NF;i++){if($i=="at" && i+1<=NF){print $(i+1); exit}}}')
      if [ -n "$mac_out" ]; then
        norm_out=$(echo "$mac_out" | awk 'BEGIN{FS=":";OFS=":"} {for(i=1;i<=NF;i++){ m=$i; gsub(/[^0-9A-Fa-f]/, "", m); if(length(m)==1){m="0"m} if(length(m)==0){m="00"} $i=tolower(m)} print }')
        if [ "$norm_out" = "$target_mac" ]; then
          case " $candidates " in
            *" $dns_ip "*) :;;
            *) candidates+=" $dns_ip" ;;
          esac
        fi
      fi
    done
  fi

  # Add console-derived IPs (best effort) to the end, dedup
  local console_ips
  console_ips=$(get_vm_ips_from_console "$vm_name" 2>/dev/null || true)
  if [ -n "$console_ips" ]; then
    for ip in $console_ips; do
      case " $candidates " in
        *" $ip "*) :;;
        *) candidates+=" $ip" ;;
      esac
    done
  fi

  if [ -z "$candidates" ]; then
    return
  fi

  # Prefer the one that answers SSH quickly; otherwise first entry
  for ip in $candidates; do
    # skip non-routable/special addresses defensively
    case "$ip" in
      0.0.0.0|255.255.255.255) continue;;
    esac
    case "$ip" in
      127.*|169.254.*) continue;;
    esac
    if timeout 1 nc -z "$ip" 22 2>/dev/null; then
      echo "$ip"
      return
    fi
  done

  # None answered SSH: return the first candidate (ARP-derived preferred)
  for ip in $candidates; do
    case "$ip" in
      0.0.0.0|255.255.255.255) continue;;
    esac
    case "$ip" in
      127.*|169.254.*) continue;;
    esac
    echo "$ip"; break;
  done
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

        # Use default memory and CPU for unregistered VMs
        local default_memory_mb
        default_memory_mb=$(get_mem_mb)
        local default_vcpus
        default_vcpus=$(get_vcpus)
        register_vm "$vm_name" "$vm_dir" "$hostname" "$username" "$disk_size" "$ubuntu_version" "$mac_address" "$instance_id" "x86_64" "$default_memory_mb" "$default_vcpus"
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
  export -f get_vm_info list_vms get_vm_status get_vm_pid get_vm_ip get_vm_architecture get_vm_memory_mb get_vm_vcpus sync_registry
fi
