#!/bin/bash

# VM Reset Script
# Resets a VM to original state while keeping selected user settings

set -e

# Get script directory and load config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/vm-config.sh"
source "$SCRIPT_DIR/vm-registry.sh"
source "$SCRIPT_DIR/vm-common.sh"

# Normalize a possibly quoted path by stripping surrounding single/double quotes
normalize_quoted_path() {
  local p="$1"
  # Strip surrounding double quotes
  p="${p%\"}"
  p="${p#\"}"
  # Strip surrounding single quotes
  p="${p%\'}"
  p="${p#\'}"
  echo "$p"
}

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
  --hard                Recreate the overlay disk from base image (full disk reimage)
  --no-keep             Do not restore items from keep.list (home will be cleaned to skeleton)
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
HARD_RESET=false
NO_KEEP=false
FORCE_RESET=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --keep-home)
      KEEP_HOME=true
      shift
      ;;
    --hard)
      HARD_RESET=true
      shift
      ;;
    --no-keep)
      NO_KEEP=true
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

# Validate incompatible options
if [ "$KEEP_HOME" = true ] && [ "$NO_KEEP" = true ]; then
  error "--keep-home and --no-keep cannot be used together"
  exit 1
fi

# Check if VM exists and get directory
VM_DIR=$(ensure_vm_exists "$VM_NAME")
# Host backup cache dir for this VM
HOST_BACKUP_DIR="$VM_DIR/.reset-backup"
mkdir -p "$HOST_BACKUP_DIR"

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
  elif [ "$NO_KEEP" = true ]; then
    echo "  ⚠️  No items from keep.list will be restored (home will be cleaned to skeleton)"
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
  if [ "$HARD_RESET" = true ]; then
    echo "  ❌ Overlay disk will be recreated from base image (all rootfs changes discarded)"
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
# Preflight: detect host public key path for later seeding
HOST_PUB_KEY_PATH="$(get_ssh_key)"
HOST_PUB_KEY_PATH="$(normalize_quoted_path "$HOST_PUB_KEY_PATH")"
if [ ! -f "$HOST_PUB_KEY_PATH" ]; then
  warn "Host public key not found; SSH key seeding will be skipped"
fi

# Check current VM status
log "DEBUG: About to call get_vm_status for $VM_NAME"
CURRENT_VM_STATUS=$(get_vm_status "$VM_NAME")
log "DEBUG: get_vm_status returned: $CURRENT_VM_STATUS"

# Decide if we need to boot just to take a backup
NEED_BACKUP=true
if [ "$KEEP_HOME" = true ] && [ -f "$HOST_BACKUP_DIR/home-backup.tar.gz" ]; then
  NEED_BACKUP=false
elif [ "$KEEP_HOME" = false ] && [ -f "$HOST_BACKUP_DIR/keep-backup.tar.gz" ]; then
  NEED_BACKUP=false
fi

# If explicitly not keeping, we don't need backups
if [ "$NO_KEEP" = true ]; then
  NEED_BACKUP=false
fi

if [ "$NEED_BACKUP" = false ]; then
  log "Found existing host backup in $HOST_BACKUP_DIR; skipping pre-reset boot/backup"
else
  # Turn ON if needed
  if [ "$CURRENT_VM_STATUS" = "stopped" ] || [ "$CURRENT_VM_STATUS" = "missing" ]; then
    log "VM is OFF - starting to backup settings..."
    "$SCRIPT_DIR/start-vm.sh" "$VM_NAME" --no-wait
  else
    log "VM is already ON - proceeding with backup..."
  fi

  # Backup will be performed below in the dedicated NEED_BACKUP block once the VM is confirmed running
fi

if [ "$NEED_BACKUP" = true ]; then
  # Wait for VM to be running (only when taking a fresh backup)
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
      KEEP_ITEMS=\"$KEEP_ITEMS\"
      mkdir -p /tmp/keep
      for item in \$KEEP_ITEMS; do
        # Copy directories or files if they exist
        if [ -e \"\$HOME/\$item\" ]; then
          dir=\$(dirname \"\$item\")
          mkdir -p \"/tmp/keep/\$dir\"
          cp -a \"\$HOME/\$item\" \"/tmp/keep/\$item\" 2>/dev/null || true
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
      printf '%s\n' \$KEEP_ITEMS > /tmp/keep/.list
      # Tar up /tmp/keep to stdout
      tar -C /tmp -czf - keep
    " > "$HOST_BACKUP_DIR/keep-backup.tar.gz" || {
      error "Failed to backup kept items"
      exit 1
    }
  fi
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

# Optional hard reset: recreate overlay from base image
if [ "$HARD_RESET" = true ]; then
  log "Performing HARD reset: recreating overlay from base image..."
  cd "$VM_DIR"
  BASE_IMG="${VM_NAME}-base.img"
  OVERLAY_IMG="${VM_NAME}.qcow2"
  if [ ! -f "$BASE_IMG" ]; then
    error "Base image not found: $VM_DIR/$BASE_IMG"
    exit 1
  fi
  # Determine disk virtual size from existing overlay if present; fallback to registry size
  DISK_SIZE_ARG=""
  if [ -f "$OVERLAY_IMG" ] && command -v qemu-img >/dev/null 2>&1; then
    # Parse virtual size line like: "virtual size: 100G (107374182400 bytes)"
    vs=$(qemu-img info "$OVERLAY_IMG" 2>/dev/null | grep -i "virtual size" | sed -E 's/.*\(([^ ]+) bytes\).*/\1/' ) || true
    if [ -n "$vs" ]; then
      # Prefer specifying same size; qemu-img create accepts bytes or with suffixes, but we'll use registry size below if available
      :
    fi
  fi
  # If registry has disk_size, use it; else default to get_disk_size
  REG_DISK_SZ=$(get_vm_info "$VM_NAME" | jq -r '.disk_size // empty' 2>/dev/null || true)
  if [ -n "$REG_DISK_SZ" ] && [ "$REG_DISK_SZ" != "null" ]; then
    DISK_SIZE_ARG="$REG_DISK_SZ"
  else
    DISK_SIZE_ARG="$(get_disk_size)"
  fi
  # Remove old overlay and create a new one referencing base
  rm -f "$OVERLAY_IMG"
  log "Creating new overlay $OVERLAY_IMG (size: $DISK_SIZE_ARG) based on $BASE_IMG"
  qemu-img create -f qcow2 -F qcow2 -b "$BASE_IMG" "$OVERLAY_IMG" "$DISK_SIZE_ARG" >/dev/null
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

# Automatic /etc/hosts updates removed; use 'vm hosts-sync --apply' manually if desired

# Refresh macOS DNS caches after reset so hostname resolution is up to date on the host
if [ -f "$SCRIPT_DIR/flush-dns.sh" ]; then
  log "Refreshing macOS DNS caches (may prompt for sudo)..."
  bash "$SCRIPT_DIR/flush-dns.sh" || log "DNS cache flush failed; you can run it later: $SCRIPT_DIR/flush-dns.sh"
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
    # Upload host public key for in-session seeding (avoid later password prompts)
    if [ -f "$HOST_PUB_KEY_PATH" ]; then
      if scp -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$HOST_PUB_KEY_PATH" "$VM_USERNAME@${SSH_HOST:-$VM_NAME}:/tmp/host_pub.key"; then :; else
        warn "Failed to upload host public key; will rely on final seeding"
      fi
    fi
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
      # Ensure host pub key is present for key-based SSH going forward
      if [ -f /tmp/host_pub.key ]; then
        mkdir -p /home/$VM_USERNAME/.ssh
        touch /home/$VM_USERNAME/.ssh/authorized_keys
        chmod 700 /home/$VM_USERNAME/.ssh
        chmod 600 /home/$VM_USERNAME/.ssh/authorized_keys
        if ! grep -F -x -q -f /tmp/host_pub.key /home/$VM_USERNAME/.ssh/authorized_keys 2>/dev/null; then
          cat /tmp/host_pub.key >> /home/$VM_USERNAME/.ssh/authorized_keys
        fi
        chown -R $VM_USERNAME:$VM_USERNAME /home/$VM_USERNAME/.ssh
      fi
    " || log "Warning: Home restore encountered an issue"
  else
    log "Warning: Home backup not found; skipping restore"
  fi
else
  # Upload keep backup and restore in a single session that cleans and restores
  if [ "$NO_KEEP" = true ]; then
    # Clean home only, seed host public key for SSH, do not restore any keep items
    if [ -f "$HOST_PUB_KEY_PATH" ]; then
      if scp -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$HOST_PUB_KEY_PATH" "$VM_USERNAME@${SSH_HOST:-$VM_NAME}:/tmp/host_pub.key"; then :; else
        warn "Failed to upload host public key; SSH access may require password after cleaning home"
      fi
    fi
    ssh $SSH_OPTS "$VM_USERNAME@${SSH_HOST:-$VM_NAME}" "
      set -e
      # Clean home first
      sudo rm -rf /home/$VM_USERNAME/.[^.]* /home/$VM_USERNAME/* 2>/dev/null || true
      sudo cp -r /etc/skel/. /home/$VM_USERNAME/ 2>/dev/null || true
      sudo chown -R $VM_USERNAME:$VM_USERNAME /home/$VM_USERNAME
      # Ensure host pub key is present for key-based SSH going forward
      if [ -f /tmp/host_pub.key ]; then
        mkdir -p /home/$VM_USERNAME/.ssh
        touch /home/$VM_USERNAME/.ssh/authorized_keys
        chmod 700 /home/$VM_USERNAME/.ssh
        chmod 600 /home/$VM_USERNAME/.ssh/authorized_keys
        if ! grep -F -x -q -f /tmp/host_pub.key /home/$VM_USERNAME/.ssh/authorized_keys 2>/dev/null; then
          cat /tmp/host_pub.key >> /home/$VM_USERNAME/.ssh/authorized_keys
        fi
        chown -R $VM_USERNAME:$VM_USERNAME /home/$VM_USERNAME/.ssh
      fi
    " || log "Warning: Home cleanup encountered an issue"
  elif [ -f "$HOST_BACKUP_DIR/keep-backup.tar.gz" ]; then
    # Upload host public key for in-session seeding (avoid later password prompts)
    if [ -f "$HOST_PUB_KEY_PATH" ]; then
      if scp -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$HOST_PUB_KEY_PATH" "$VM_USERNAME@${SSH_HOST:-$VM_NAME}:/tmp/host_pub.key"; then :; else
        warn "Failed to upload host public key; will rely on final seeding"
      fi
    fi
    scp -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$HOST_BACKUP_DIR/keep-backup.tar.gz" "$VM_USERNAME@${SSH_HOST:-$VM_NAME}:/tmp/keep-backup.tar.gz" || true
    ssh $SSH_OPTS "$VM_USERNAME@${SSH_HOST:-$VM_NAME}" "
      set -e
      # Clean home first
      sudo rm -rf /home/$VM_USERNAME/.[^.]* /home/$VM_USERNAME/* 2>/dev/null || true
      sudo cp -r /etc/skel/. /home/$VM_USERNAME/ 2>/dev/null || true
      sudo chown -R $VM_USERNAME:$VM_USERNAME /home/$VM_USERNAME
      # Extract keep payload (robust to bad tar)
      mkdir -p /tmp
      if tar -tzf /tmp/keep-backup.tar.gz >/dev/null 2>&1; then
        tar -C /tmp -xzf /tmp/keep-backup.tar.gz || true
      else
        echo 'Warning: keep-backup tar appears corrupted; skipping extraction'
      fi
      restored=false
      if [ -x /tmp/keep/restore.sh ]; then
        /tmp/keep/restore.sh && restored=true || true
      fi
      if [ "\$restored" != true ]; then
        echo 'Fallback restore: applying items from list'
        if [ -f /tmp/keep/.list ]; then
          while IFS= read -r item; do
            [ -z "$item" ] && continue
            if [ -e "/tmp/keep/$item" ]; then
              mkdir -p "$(dirname "$HOME/$item")"
              cp -a "/tmp/keep/$item" "$HOME/$item" 2>/dev/null || true
            fi
          done < /tmp/keep/.list
        fi
        [ -d ~/.ssh ] && chmod 700 ~/.ssh && chmod 600 ~/.ssh/* 2>/dev/null || true
      fi
      # Ensure host pub key is present for key-based SSH going forward
      if [ -f /tmp/host_pub.key ]; then
        mkdir -p ~/.ssh
        touch ~/.ssh/authorized_keys
        chmod 700 ~/.ssh
        chmod 600 ~/.ssh/authorized_keys
        if ! grep -F -x -q -f /tmp/host_pub.key ~/.ssh/authorized_keys 2>/dev/null; then
          cat /tmp/host_pub.key >> ~/.ssh/authorized_keys
        fi
      fi
    " || log "Warning: Keep restore encountered an issue"
  else
    log "Warning: Keep backup not found; skipping restore"
  fi
fi

# Final: ensure authorized_keys exists by seeding from host key if missing
HOST_PUB_KEY_PATH="$(get_ssh_key)"
HOST_PUB_KEY_PATH="$(normalize_quoted_path "$HOST_PUB_KEY_PATH")"
# Final: Only attempt extra seeding if we have key and remote auth still works
if [ -f "$HOST_PUB_KEY_PATH" ]; then
  if ssh $SSH_OPTS "$VM_USERNAME@${SSH_HOST:-$VM_NAME}" "true" >/dev/null 2>&1; then
    # Upload the host public key (again) and check/append remotely to avoid local cat expansion
    if scp -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$HOST_PUB_KEY_PATH" "$VM_USERNAME@${SSH_HOST:-$VM_NAME}:/tmp/host_pub.key"; then
      if ! ssh $SSH_OPTS "$VM_USERNAME@${SSH_HOST:-$VM_NAME}" "grep -F -x -q -f /tmp/host_pub.key ~/.ssh/authorized_keys 2>/dev/null"; then
        log "Seeding authorized_keys from host public key to restore SSH access"
        ssh $SSH_OPTS "$VM_USERNAME@${SSH_HOST:-$VM_NAME}" "mkdir -p ~/.ssh && touch ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys && cat /tmp/host_pub.key >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys" || true
      fi
    else
      warn "Failed to upload host public key during final seeding step"
    fi
  fi
fi

# Verification: ensure all keep items exist after restore (fix up any misses like .gitconfig)
if [ -f "$HOST_BACKUP_DIR/keep-backup.tar.gz" ]; then
  KEEP_ITEMS_CHECK=$(get_keep_items | tr '\n' ' ')
  ssh $SSH_OPTS "$VM_USERNAME@${SSH_HOST:-$VM_NAME}" "
    set -e
    if [ -f /tmp/keep/.list ]; then
      while IFS= read -r item; do
        [ -z \"\$item\" ] && continue
        if [ ! -e \"\$HOME/\$item\" ] && [ -e \"/tmp/keep/\$item\" ]; then
          mkdir -p \"\$(dirname \"\$HOME/\$item\")\"
          cp -a \"/tmp/keep/\$item\" \"\$HOME/\$item\" 2>/dev/null || true
        fi
      done < /tmp/keep/.list
    fi
    # Normalize SSH permissions again just in case
    [ -d ~/.ssh ] && chmod 700 ~/.ssh && chmod 600 ~/.ssh/* 2>/dev/null || true
  " || true
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
