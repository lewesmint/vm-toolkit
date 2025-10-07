#!/bin/bash

# VM Reset Script
# Resets a VM to original state while keeping selected user settings

set -e

# Get script directory and load config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/vm-config.sh"
source "$SCRIPT_DIR/vm-registry.sh"
source "$SCRIPT_DIR/vm-common.sh"

# Port check helper compatible with macOS/BSD nc
port_check() {
  local host="$1" port="$2" timeout_secs="${3:-3}"
  if nc -h 2>&1 | grep -q " -G "; then
    nc -z -G "$timeout_secs" "$host" "$port" >/dev/null 2>&1
  else
    nc -z -w "$timeout_secs" "$host" "$port" >/dev/null 2>&1
  fi
}

show_usage() {
  cat << EOF
Usage: $0 <vm-name> [options]

Reset a VM to original cloud image state while keeping selected user settings.

Required:
  <vm-name>             VM name to reset

Options:
  --keep-home           Keep entire home directory (default: only items from keep.list)
  --force               Skip confirmation prompt
  --help                Show this help

Examples:
  $0 gamma                    # Reset gamma, keep items from keep.list (SSH/Git/GH by default)
  $0 gamma --keep-home        # Reset gamma, keep entire home
  $0 gamma --force            # Reset without confirmation

What gets kept:
  - Items from keep list (configurable):
    - Default: ~/.ssh, ~/.gitconfig, ~/.config/gh
    - Config file search order:
      1) $VM_KEEP_LIST_FILE (env var)
      2) ~/.vm-toolkit-keep.list
      3) <project>/keep.list
      4) <toolkit>/keep.list

What gets reset:
  - All system packages (back to cloud image)
  - All installed software (snap, apt packages, etc.)
  - System configuration
  - Everything else in home directory (unless --keep-home)

EOF
}

# Parse arguments
VM_NAME=""
KEEP_HOME=false
FORCE_RESET=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --keep-home)
      KEEP_HOME=true
      shift
      ;;
    # Back-compat
    --preserve-home)
      KEEP_HOME=true
      shift
      ;;
    --force)
      FORCE_RESET=true
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
      if [ -z "$VM_NAME" ]; then
        VM_NAME="$1"
      else
        error "Multiple VM names specified: $VM_NAME and $1"
        exit 1
      fi
      shift
      ;;
  esac
done

if [ -z "$VM_NAME" ]; then
  error "VM name is required"
  show_usage
  exit 1
fi

# Check if VM exists and get directory
VM_DIR=$(ensure_vm_exists "$VM_NAME")

# Check if VM is running
VM_STATUS=$(get_vm_status "$VM_NAME")
if [ "$VM_STATUS" = "running" ]; then
  log "VM '$VM_NAME' is currently running"
fi

# Confirmation prompt
if [ "$FORCE_RESET" = false ]; then
  echo "⚠️  WARNING: This will reset VM '$VM_NAME' to original cloud image state!"
  echo ""
  echo "What will be preserved:"
  if [ "$KEEP_HOME" = true ]; then
    echo "  ✅ Entire home directory (/home/$(get_vm_info "$VM_NAME" | jq -r '.username // "mintz"'))"
  else
    echo "  ✅ Items from keep list (default: ~/.ssh, ~/.gitconfig, ~/.config/gh)"
  fi
  echo ""
  echo "What will be reset:"
  echo "  ❌ All system packages (snap, apt, etc.)"
  echo "  ❌ All installed software"
  echo "  ❌ System configuration"
  if [ "$KEEP_HOME" = false ]; then
    echo "  ❌ Other files in home directory"
  fi
  echo ""
  read -r -p "Continue with reset? Type 'yes' to confirm: " confirm

  if [ "$confirm" != "yes" ]; then
    log "Reset cancelled"
    exit 0
  fi
fi

log "Resetting VM: $VM_NAME"

# Step 1: Ensure VM is ON and backup settings
VM_USERNAME=$(get_vm_info "$VM_NAME" | jq -r '.username // "mintz"')

# SSH options for reset operations
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

# Check current VM status
log "DEBUG: About to call get_vm_status for $VM_NAME"
CURRENT_VM_STATUS=$(get_vm_status "$VM_NAME")
log "DEBUG: get_vm_status returned: $CURRENT_VM_STATUS"

# Turn ON if needed
if [ "$CURRENT_VM_STATUS" = "stopped" ] || [ "$CURRENT_VM_STATUS" = "missing" ]; then
  log "VM is OFF - starting to backup settings..."
  "$SCRIPT_DIR/start-vm.sh" "$VM_NAME" --no-wait
else
  log "VM is already ON - proceeding with backup..."
fi

# Wait for VM to be running
log "Waiting for VM to be running..."

for i in {1..30}; do
  VM_STATUS=$(get_vm_status "$VM_NAME")
  log "Attempt $i: VM status = '$VM_STATUS'"

  if [ "$VM_STATUS" = "running" ]; then
    log "VM is running"
    break
  fi

  if [ $i -eq 30 ]; then
    error "VM did not reach running state within 5 minutes (VM status: $VM_STATUS)"
    exit 1
  fi

  sleep 10
done

best_ip="$(get_vm_best_ip "$VM_NAME" 2>/dev/null || true)"
if [ -n "$best_ip" ]; then
  log "Using IP for SSH: $best_ip (from best-IP logic)"
  SSH_HOST="$best_ip"
else
  log "Best IP not yet known; will attempt hostname and retry when ready"
  SSH_HOST="$VM_NAME"
fi

# Backup settings (VM is now guaranteed to be running)
log "Backing up settings..."
HOST_BACKUP_DIR="$VM_DIR/.reset-backup"
mkdir -p "$HOST_BACKUP_DIR"
if [ "$KEEP_HOME" = true ]; then
  log "  - Preserving entire home directory (streaming to host)"
  # Stream entire home directory to host file
  ssh $SSH_OPTS "$VM_USERNAME@${SSH_HOST:-$VM_NAME}" "tar -C /home -czf - $VM_USERNAME" > "$HOST_BACKUP_DIR/home-backup.tar.gz" || {
    error "Failed to backup home directory"
    exit 1
  }
else
  # Backup only configured keep items (default: SSH keys, Git config, GitHub CLI) to host
  KEEP_ITEMS=$(get_keep_items | tr '\n' ' ')
  ssh $SSH_OPTS "$VM_USERNAME@${SSH_HOST:-$VM_NAME}" "
    set -e
    mkdir -p /tmp/keep
    for item in $KEEP_ITEMS; do
      # Copy directories or files if they exist
      if [ -e \"~/\$item\" ]; then
        mkdir -p \"/tmp/keep/\$(dirname \"$item\")\"
        cp -a \"~/\$item\" \"/tmp/keep/\$item\" 2>/dev/null || true
      fi
    done
    # Create restore script
    cat > /tmp/keep/restore.sh << 'EOF'
#!/bin/bash
set -e
echo '🔄 Restoring kept settings...'
KEEP_ITEMS=($(cat /tmp/keep/.list 2>/dev/null || true))
mkdir -p ~/.config
for item in "${KEEP_ITEMS[@]}"; do
  src="/tmp/keep/$item"
  dest="$HOME/$item"
  if [ -e "$src" ]; then
    mkdir -p "$(dirname "$dest")"
    cp -a "$src" "$dest" 2>/dev/null || true
  fi
done
# Fix common SSH perms if present
[ -d ~/.ssh ] && chmod 700 ~/.ssh && chmod 600 ~/.ssh/* 2>/dev/null || true
echo '✅ Kept settings restored'
EOF
    chmod +x /tmp/keep/restore.sh
    # Save the keep list for restore
    printf '%s\n' $KEEP_ITEMS > /tmp/keep/.list
    # Tar up /tmp/keep to stdout
    tar -C /tmp -czf - keep
  " > "$HOST_BACKUP_DIR/keep-backup.tar.gz" || {
    error "Failed to backup kept items"
    exit 1
  }
fi

# Turn OFF for reset
log "Stopping VM for reset..."
"$SCRIPT_DIR/stop-vm.sh" "$VM_NAME" || {
  error "Failed to stop VM"
  exit 1
}

# Check if QEMU process is actually gone
log "Verifying VM is actually stopped..."
if ps aux | grep -v grep | grep "${VM_NAME}.qcow2" >/dev/null; then
  log "WARNING: QEMU process still running after stop command"
  log "Killing remaining processes..."
  pkill -f "${VM_NAME}.qcow2" || true
  sleep 2
else
  log "VM process confirmed stopped"
fi

# Step 2: Reset with fresh instance-id
log "Resetting VM with fresh instance-id..."
cd "$VM_DIR"

# Generate new instance-id to force cloud-init re-run
INSTANCE_ID="iid-${VM_NAME}-$(date +%s)"
echo "$INSTANCE_ID" > "cloud-init/instance-id"

log "Generated new instance ID: $INSTANCE_ID"

# Step 3: Start VM (retry if locked)
log "Starting reset VM..."
for i in {1..10}; do
  if "$SCRIPT_DIR/start-vm.sh" "$VM_NAME" --no-wait 2>/dev/null; then
    log "VM started successfully"
    break
  fi

  if [ $i -eq 10 ]; then
    error "Failed to start VM after 10 attempts"
    exit 1
  fi

  log "Start failed (attempt $i/10), retrying in 3 seconds..."
  sleep 3
done

# Step 4: Wait for VM to be ready for cleanup and restore
log "Waiting for VM to be ready for cleanup and restore..."

# Wait for VM to be running after reset
for i in {1..30}; do
  VM_STATUS=$(get_vm_status "$VM_NAME")

  if [ "$VM_STATUS" = "running" ]; then
    log "VM is running after reset"
    break
  fi

  if [ $i -eq 30 ]; then
    error "VM did not reach running state within 5 minutes after reset (VM status: $VM_STATUS)"
    exit 1
  fi

  log "VM status: $VM_STATUS, waiting..."
  sleep 10
done

# Refresh best IP after reset (DHCP may assign a new address)
post_reset_ip="$(get_vm_best_ip "$VM_NAME" 2>/dev/null || true)"
if [ -n "$post_reset_ip" ] && [ "$post_reset_ip" != "${SSH_HOST:-}" ]; then
  SSH_HOST="$post_reset_ip"
  log "Detected new IP after reset: $SSH_HOST"
fi

# Wait for SSH port to be available on best IP/hostname, refreshing best IP if it changes
log "Waiting for SSH to be ready on: ${SSH_HOST:-$VM_NAME}"
for i in {1..20}; do
  # Recompute best IP every few attempts to handle DHCP change
  if [ $((i % 2)) -eq 0 ]; then
    new_ip="$(get_vm_best_ip "$VM_NAME" 2>/dev/null || true)"
    if [ -n "$new_ip" ] && [ "$new_ip" != "${SSH_HOST:-}" ]; then
      log "Updated best IP discovered: $new_ip (was ${SSH_HOST:-N/A})"
      SSH_HOST="$new_ip"
      # Update hosts mapping on change
      if [ -f "$SCRIPT_DIR/hosts-sync.sh" ]; then
        bash "$SCRIPT_DIR/hosts-sync.sh" --apply "$VM_NAME" || true
      fi
    fi
  fi
  target_host="${SSH_HOST:-$VM_NAME}"
  log "SSH wait attempt $i/20 on $target_host:22"
  if port_check "$target_host" 22 3; then
    log "SSH port is ready"
    break
  fi

  if [ $i -eq 20 ]; then
    error "SSH port did not become available within 3.5 minutes"
    exit 1
  fi
  sleep 10
done

# Once IP is (re)discovered, sync hosts to avoid DNS/ARP staleness
if [ -f "$SCRIPT_DIR/hosts-sync.sh" ]; then
  log "Syncing /etc/hosts mapping for $VM_NAME (may prompt for sudo)..."
  bash "$SCRIPT_DIR/hosts-sync.sh" --apply "$VM_NAME" || true
fi

# Wait for cloud-init to complete (or reasonable readiness) before proceeding
log "Waiting for cloud-init (or readiness) to complete..."
for i in {1..30}; do
  target_host="${SSH_HOST:-$VM_NAME}"
  log "cloud-init check $i/30 on $target_host"

  # If cloud-init exists, check its state without blocking
  if ssh $SSH_OPTS "$VM_USERNAME@$target_host" "command -v cloud-init >/dev/null 2>&1"; then
    # Query status (non-blocking) and parse common completed states
    if ssh $SSH_OPTS "$VM_USERNAME@$target_host" "cloud-init status 2>/dev/null | grep -E 'status: (done|disabled|not running)' -q"; then
      log "Cloud-init reports completed (done/disabled/not running)"
      break
    fi

    # Fallback quick wait on final stage with a short timeout via systemd if present
    if ssh $SSH_OPTS "$VM_USERNAME@$target_host" "command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet cloud-final.service"; then
      log "cloud-final.service is active; proceeding"
      break
    fi
  else
    # cloud-init not installed; consider system ready if we can SSH
    log "cloud-init not found; proceeding without waiting"
    break
  fi

  # Alternative success signal used by some images
  if ssh $SSH_OPTS "$VM_USERNAME@$target_host" "test -f /var/lib/cloud/instance/boot-finished"; then
    log "boot-finished marker present; proceeding"
    break
  fi

  if [ $i -eq 30 ]; then
    warn "Cloud-init did not report completion within 5 minutes; proceeding anyway"
    break
  fi

  log "Cloud-init not finished yet; waiting..."
  sleep 10
done

# Step 5: Clean home directory (deferred)
# Defer cleaning to the restore step so we can upload backups first while key-based SSH is still available.
if [ "$KEEP_HOME" = false ]; then
  log "Deferring home cleaning to restore step (after uploading keep-backup)"
fi

# Step 6: Restore kept settings
log "Restoring kept settings..."

if [ "$KEEP_HOME" = true ]; then
  # Upload home backup and restore in a single session that cleans and restores
  if [ -f "$HOST_BACKUP_DIR/home-backup.tar.gz" ]; then
    scp -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$HOST_BACKUP_DIR/home-backup.tar.gz" "$VM_USERNAME@${SSH_HOST:-$VM_NAME}:/tmp/home-backup.tar.gz" || true
    ssh $SSH_OPTS "$VM_USERNAME@${SSH_HOST:-$VM_NAME}" "
      set -e
      # Ensure clean skeleton then restore
      sudo rm -rf /home/$VM_USERNAME/.[^.]* /home/$VM_USERNAME/* 2>/dev/null || true
      sudo cp -r /etc/skel/. /home/$VM_USERNAME/ 2>/dev/null || true
      sudo chown -R $VM_USERNAME:$VM_USERNAME /home/$VM_USERNAME
      # Now restore entire home
      cd /home
      sudo tar -xzf /tmp/home-backup.tar.gz
      sudo chown -R $VM_USERNAME:$VM_USERNAME /home/$VM_USERNAME
      # Fix SSH perms if present
      [ -d /home/$VM_USERNAME/.ssh ] && chmod 700 /home/$VM_USERNAME/.ssh && chmod 600 /home/$VM_USERNAME/.ssh/* 2>/dev/null || true
    " || log "Warning: Home restore encountered an issue"
  else
    log "Warning: Home backup not found; skipping restore"
  fi
else
  # Upload keep backup and restore in a single session that cleans and restores
  if [ -f "$HOST_BACKUP_DIR/keep-backup.tar.gz" ]; then
    scp -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$HOST_BACKUP_DIR/keep-backup.tar.gz" "$VM_USERNAME@${SSH_HOST:-$VM_NAME}:/tmp/keep-backup.tar.gz" || true
    ssh $SSH_OPTS "$VM_USERNAME@${SSH_HOST:-$VM_NAME}" "
      set -e
      # Clean home first
      sudo rm -rf /home/$VM_USERNAME/.[^.]* /home/$VM_USERNAME/* 2>/dev/null || true
      sudo cp -r /etc/skel/. /home/$VM_USERNAME/ 2>/dev/null || true
      sudo chown -R $VM_USERNAME:$VM_USERNAME /home/$VM_USERNAME
      # Extract keep payload and run restore script
      mkdir -p /tmp
      tar -C /tmp -xzf /tmp/keep-backup.tar.gz
      /tmp/keep/restore.sh || true
    " || log "Warning: Keep restore encountered an issue"
  else
    log "Warning: Keep backup not found; skipping restore"
  fi
fi

log "✅ VM '$VM_NAME' reset successfully!"
log ""
log "Summary:"
log "  - VM reset to original cloud image state"
if [ "$KEEP_HOME" = true ]; then
  log "  - Home directory preserved"
else
  log "  - Kept settings restored from list ($(get_keep_items | paste -sd, -))"
fi
log "  - All system packages and software reset"
log ""
log "Next steps:"
log "  - Check status: vm status $VM_NAME"
log "  - SSH into VM: ssh $VM_USERNAME@$VM_NAME"
