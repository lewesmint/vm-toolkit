#!/bin/bash

# VM Reset Script
# Resets a VM to original state while preserving Git and SSH settings

set -e

# Get script directory and load config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/vm-config.sh"
source "$SCRIPT_DIR/vm-registry.sh"
source "$SCRIPT_DIR/vm-common.sh"

show_usage() {
  cat << EOF
Usage: $0 <vm-name> [options]

Reset a VM to original cloud image state while preserving Git and SSH settings.

Required:
  <vm-name>             VM name to reset

Options:
  --preserve-home       Preserve entire home directory (default: only Git/SSH)
  --force               Skip confirmation prompt
  --help                Show this help

Examples:
  $0 gamma                    # Reset gamma, preserve Git/SSH only
  $0 gamma --preserve-home    # Reset gamma, preserve entire home
  $0 gamma --force            # Reset without confirmation

What gets preserved:
  - ~/.ssh/ (SSH keys and config)
  - ~/.gitconfig (Git configuration)
  - ~/.config/gh/ (GitHub CLI config)

What gets reset:
  - All system packages (back to cloud image)
  - All installed software (snap, apt packages, etc.)
  - System configuration
  - Everything else in home directory (unless --preserve-home)

EOF
}

# Parse arguments
VM_NAME=""
PRESERVE_HOME=false
FORCE_RESET=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --preserve-home)
      PRESERVE_HOME=true
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
  if [ "$PRESERVE_HOME" = true ]; then
    echo "  ✅ Entire home directory (/home/$(get_vm_info "$VM_NAME" username))"
  else
    echo "  ✅ SSH keys and config (~/.ssh/)"
    echo "  ✅ Git configuration (~/.gitconfig)"
    echo "  ✅ GitHub CLI config (~/.config/gh/)"
  fi
  echo ""
  echo "What will be reset:"
  echo "  ❌ All system packages (snap, apt, etc.)"
  echo "  ❌ All installed software"
  echo "  ❌ System configuration"
  if [ "$PRESERVE_HOME" = false ]; then
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

# Step 1: Start VM if needed and backup settings
VM_USERNAME=$(get_vm_info "$VM_NAME" username)

# Start VM if it's not running (needed for backup)
if [ "$VM_STATUS" != "running" ]; then
  log "Starting VM to backup settings..."
  "$SCRIPT_DIR/start-vm.sh" "$VM_NAME"

  # Wait for VM to be ready
  log "Waiting for VM to be ready..."
  for i in {1..30}; do
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$VM_USERNAME@$VM_NAME" "echo 'SSH ready'" >/dev/null 2>&1; then
      break
    fi
    if [ $i -eq 30 ]; then
      error "VM did not become accessible via SSH within 5 minutes"
      exit 1
    fi
    sleep 10
  done
fi

log "Backing up settings..."

if [ "$PRESERVE_HOME" = true ]; then
  # Backup entire home directory
  ssh "$VM_USERNAME@$VM_NAME" "tar -czf /tmp/home-backup.tar.gz -C /home $VM_USERNAME" || {
    error "Failed to backup home directory. VM may not be accessible via SSH."
    exit 1
  }
else
  # Backup only Git and SSH settings
  ssh "$VM_USERNAME@$VM_NAME" "
    mkdir -p /tmp/preserve
    cp -r ~/.ssh /tmp/preserve/ 2>/dev/null || true
    cp ~/.gitconfig /tmp/preserve/ 2>/dev/null || true
    cp -r ~/.config/gh /tmp/preserve/ 2>/dev/null || true

    # Create restore script
    cat > /tmp/preserve/restore.sh << 'EOF'
#!/bin/bash
echo '🔄 Restoring Git and SSH settings...'
mkdir -p ~/.config

# Restore from backup
cp -r /tmp/preserve/.ssh ~/ 2>/dev/null || true
cp /tmp/preserve/.gitconfig ~/ 2>/dev/null || true
cp -r /tmp/preserve/gh ~/.config/ 2>/dev/null || true

# Fix permissions
chmod 700 ~/.ssh 2>/dev/null || true
chmod 600 ~/.ssh/* 2>/dev/null || true

echo '✅ Git and SSH settings restored'
EOF
    chmod +x /tmp/preserve/restore.sh
  " || {
    error "Failed to backup settings. VM may not be accessible via SSH."
    exit 1
  }
fi

# Step 2: Stop VM if running
if [ "$VM_STATUS" = "running" ]; then
  log "Stopping VM..."
  "$SCRIPT_DIR/stop-vm.sh" "$VM_NAME"
fi

# Step 3: Reset with fresh instance-id
log "Resetting VM with fresh instance-id..."
cd "$VM_DIR"

# Generate new instance-id to force cloud-init re-run
INSTANCE_ID="iid-${VM_NAME}-$(date +%s)"
echo "$INSTANCE_ID" > "cloud-init/instance-id"

log "Generated new instance ID: $INSTANCE_ID"

# Step 4: Start VM
log "Starting reset VM..."
"$SCRIPT_DIR/start-vm.sh" "$VM_NAME"

# Step 5: Wait for VM to be ready and restore settings
log "Waiting for VM to be ready..."
sleep 10

# Wait for SSH to be available
for i in {1..30}; do
  if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$VM_USERNAME@$VM_NAME" "echo 'SSH ready'" >/dev/null 2>&1; then
    break
  fi
  if [ $i -eq 30 ]; then
    error "VM did not become accessible via SSH within 5 minutes"
    exit 1
  fi
  sleep 10
done

# Step 6: Clean home directory (except for preserved items)
if [ "$PRESERVE_HOME" = false ]; then
  log "Cleaning home directory (preserving only Git/SSH settings)..."
  ssh "$VM_USERNAME@$VM_NAME" "
    # Remove all contents of home directory except preserved backup
    find /home/$VM_USERNAME -mindepth 1 -maxdepth 1 ! -path '/tmp/preserve' -exec sudo rm -rf {} + 2>/dev/null || true

    # Copy basic skeleton files to recreate clean home
    sudo cp -r /etc/skel/. /home/$VM_USERNAME/ 2>/dev/null || true
    sudo chown -R $VM_USERNAME:$VM_USERNAME /home/$VM_USERNAME
    sudo chmod 755 /home/$VM_USERNAME
  "
fi

# Step 7: Restore preserved settings
log "Restoring preserved settings..."

if [ "$PRESERVE_HOME" = true ]; then
  # Restore entire home directory
  ssh "$VM_USERNAME@$VM_NAME" "
    cd /home
    sudo tar -xzf /tmp/home-backup.tar.gz
    sudo chown -R $VM_USERNAME:$VM_USERNAME /home/$VM_USERNAME
  "
else
  # Restore only Git and SSH settings
  ssh "$VM_USERNAME@$VM_NAME" "/tmp/preserve/restore.sh" 2>/dev/null || {
    log "Warning: Could not restore settings (backup may not exist)"
  }
fi

log "✅ VM '$VM_NAME' reset successfully!"
log ""
log "Summary:"
log "  - VM reset to original cloud image state"
if [ "$PRESERVE_HOME" = true ]; then
  log "  - Home directory preserved"
else
  log "  - Git and SSH settings preserved"
fi
log "  - All system packages and software reset"
log ""
log "Next steps:"
log "  - Check status: vm status $VM_NAME"
log "  - SSH into VM: ssh $VM_USERNAME@$VM_NAME"
