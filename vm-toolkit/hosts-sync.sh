#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/vm-config.sh"
source "$SCRIPT_DIR/vm-registry.sh"

APPLY=false
TARGET_HOSTS_FILE="/etc/hosts"
VMS=()

usage() {
  cat <<EOF
Usage: vm hosts-sync [--apply] [vm-name ...]

Sync /etc/hosts entries for VMs to their current best IPs.

Options:
  --apply        Write changes to $TARGET_HOSTS_FILE (requires sudo)
  --file <path>  Use a custom hosts file path (for testing)

Without --apply, prints a dry-run of proposed changes.
If no VM names are given, all registered VMs are considered.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)
      APPLY=true; shift ;;
    --file)
      TARGET_HOSTS_FILE="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    --*)
      echo "Unknown option: $1" >&2; usage; exit 1 ;;
    *)
      VMS+=("$1"); shift ;;
  esac
done

# Gather VM list if not provided
if [ ${#VMS[@]} -eq 0 ]; then
  mapfile -t VMS < <(list_vms)
fi

if [ ${#VMS[@]} -eq 0 ]; then
  echo "No VMs found." >&2
  exit 0
fi

declare -A proposed

for vm in "${VMS[@]}"; do
  # get_vm_best_ip should pick console/DNS/ARP reachable IP
  ip=$(get_vm_best_ip "$vm" 2>/dev/null || true)
  if [ -n "$ip" ]; then
    proposed["$vm"]="$ip"
  fi
done

if [ ${#proposed[@]} -eq 0 ]; then
  echo "No IPs discovered; nothing to do." >&2
  exit 0
fi

echo "Proposed host mappings (VM -> IP):"
for vm in "${!proposed[@]}"; do
  echo "  $vm -> ${proposed[$vm]}"
done

if [ "$APPLY" != true ]; then
  echo
  echo "Dry-run only. Re-run with --apply to write to $TARGET_HOSTS_FILE (sudo required)."
  exit 0
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

# Build new hosts file content by replacing or appending VM lines.
# Preserve everything else.
if [ -f "$TARGET_HOSTS_FILE" ]; then
  cp "$TARGET_HOSTS_FILE" "$tmp"
else
  : > "$tmp"
fi

for vm in "${!proposed[@]}"; do
  ip="${proposed[$vm]}"
  # Remove any existing lines mentioning the hostname as a word
  sed -i '' "/(^|\t|\s)$vm(\s|\t|$)/d" "$tmp" 2>/dev/null || true
  # Append new mapping
  echo "$ip	$vm" >> "$tmp"
done

if [ "$TARGET_HOSTS_FILE" = "/etc/hosts" ]; then
  echo "Writing updates to $TARGET_HOSTS_FILE (sudo may prompt)..."
  sudo tee "$TARGET_HOSTS_FILE" >/dev/null < "$tmp"
else
  echo "Writing updates to $TARGET_HOSTS_FILE..."
  cat "$tmp" > "$TARGET_HOSTS_FILE"
fi

echo "Done. You may need to flush caches:"
echo "  sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder"
