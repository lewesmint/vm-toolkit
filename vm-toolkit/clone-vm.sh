#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/vm-config.sh"
source "$SCRIPT_DIR/vm-registry.sh"
source "$SCRIPT_DIR/vm-common.sh"

show_usage() {
  cat <<EOF
Usage: $0 <source-vm> <target-vm> [--hostname <name>] [--username <name>] [--reimage] [--force] [--reset] [--keep-home]

Clone an existing VM into a new VM.

Arguments:
  <source-vm>          Existing VM name to clone from
  <target-vm>          New VM name to create

Options:
  --hostname <name>    Hostname for the new VM (default: target name)
  --username <name>    Username for the new VM (default: copy from source)
  --reimage            Perform a HARD reset of the target after cloning: recreate overlay from base,
                       then restore items from keep.list by default (use with --keep-home to keep full home).
  --force              Proceed even if source VM is running (not recommended)
  --reset              After cloning, run a reset on the new VM that wipes the home directory
                       except for items from keep.list (same behavior as 'vm reset' without --keep-home).
                       Implies starting the VM and waiting for cloud-init.
  --keep-home          With --reset, keep the entire home directory instead of just keep.list items.
  --help               Show this help

Notes:
  - The clone reuses the same base image but copies the overlay disk (qcow2).
  - A new MAC address is generated for the target VM.
  - Cloud-init user-data is updated with new hostname and username.
  - Instance-id is always regenerated during clone so cloud-init runs on first boot.
EOF
}

if [[ $# -lt 2 ]]; then
  show_usage; exit 1
fi

SRC_VM="$1"; shift
TGT_VM="$1"; shift
TGT_HOSTNAME=""
TGT_USERNAME=""
FORCE=false
POST_RESET=false
POST_RESET_KEEP_HOME=false
POST_RESET_HARD=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --hostname) TGT_HOSTNAME="$2"; shift 2 ;;
    --username) TGT_USERNAME="$2"; shift 2 ;;
  --reimage|--hard) POST_RESET=true; POST_RESET_HARD=true; shift ;;
  --force) FORCE=true; shift ;;
  --reset) POST_RESET=true; shift ;;
  --keep-home) POST_RESET_KEEP_HOME=true; shift ;;
  # Backward-compat (undocumented): accept previous name if present
  --reset-preserve-keys) POST_RESET=true; shift ;;
    --help|-h) show_usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; show_usage; exit 1 ;;
  esac
done

# Validate names and directories
SRC_DIR=$(get_vm_dir "$SRC_VM")
if [ ! -d "$SRC_DIR" ]; then
  error "Source VM not found: $SRC_VM"
  exit 1
fi

TGT_DIR=$(get_vm_dir "$TGT_VM")
if [ -d "$TGT_DIR" ]; then
  error "Target VM already exists: $TGT_VM"
  exit 1
fi

ensure_vm_base_dir

# Prevent cloning a running VM unless --force
SRC_STATUS=$(get_vm_status "$SRC_VM" || true)
if [[ "$SRC_STATUS" =~ ^(running|booting|initializing|paused)$ ]] && [ "$FORCE" != true ]; then
  error "Source VM '$SRC_VM' is $SRC_STATUS. Stop it first or use --force to continue."
  exit 1
fi
mkdir -p "$TGT_DIR/cloud-init"

# Copy base image and overlay
if [ ! -f "$SRC_DIR/${SRC_VM}-base.img" ]; then
  error "Missing base image in source VM: $SRC_DIR/${SRC_VM}-base.img"
  exit 1
fi
cp "$SRC_DIR/${SRC_VM}-base.img" "$TGT_DIR/${TGT_VM}-base.img"

if [ ! -f "$SRC_DIR/${SRC_VM}.qcow2" ]; then
  error "Missing disk overlay in source VM: $SRC_DIR/${SRC_VM}.qcow2"
  exit 1
fi
cp "$SRC_DIR/${SRC_VM}.qcow2" "$TGT_DIR/${TGT_VM}.qcow2"

# Rebase overlay to point at the new base filename inside target dir
if ! command -v qemu-img >/dev/null 2>&1; then
  error "qemu-img not found; required for rebasing overlay"
  exit 1
fi
( cd "$TGT_DIR" && qemu-img rebase -u -F qcow2 -b "${TGT_VM}-base.img" "${TGT_VM}.qcow2" )

# Copy cloud-init materials
if [ -f "$SRC_DIR/cloud-init/meta-data" ]; then
  cp "$SRC_DIR/cloud-init/meta-data" "$TGT_DIR/cloud-init/meta-data"
fi
if [ -f "$SRC_DIR/cloud-init/user-data" ]; then
  cp "$SRC_DIR/cloud-init/user-data" "$TGT_DIR/cloud-init/user-data"
fi

# Generate new instance-id to force cloud-init re-run (always regenerated on clone)
INSTANCE_ID="iid-${TGT_VM}-$(date +%s)"
echo "$INSTANCE_ID" > "$TGT_DIR/cloud-init/instance-id"

# Update cloud-init configs: hostname and username
TGT_HOSTNAME="${TGT_HOSTNAME:-$TGT_VM}"
SRC_INFO=$(get_vm_info "$SRC_VM" 2>/dev/null || true)
SRC_USERNAME=$(echo "$SRC_INFO" | jq -r '.username' 2>/dev/null || echo "")
TGT_USERNAME="${TGT_USERNAME:-${SRC_USERNAME:-$(get_username)}}"

if [ -f "$TGT_DIR/cloud-init/user-data" ]; then
  # Update hostname: replace existing hostname: line
  if grep -q '^hostname:' "$TGT_DIR/cloud-init/user-data"; then
    sed -i '' -E "s/^hostname:.*/hostname: $TGT_HOSTNAME/" "$TGT_DIR/cloud-init/user-data"
  else
    printf '\nhostname: %s\n' "$TGT_HOSTNAME" >> "$TGT_DIR/cloud-init/user-data"
  fi
  # Update username in users block (first user entry)
  sed -i '' -E "s/(^- name: )[A-Za-z0-9_-]+/\\1$TGT_USERNAME/" "$TGT_DIR/cloud-init/user-data" || true
fi

if [ -f "$TGT_DIR/cloud-init/meta-data" ]; then
  # Update local-hostname in meta-data
  if grep -q '^local-hostname:' "$TGT_DIR/cloud-init/meta-data"; then
    sed -i '' -E "s/^local-hostname:.*/local-hostname: $TGT_HOSTNAME/" "$TGT_DIR/cloud-init/meta-data"
  else
    printf 'local-hostname: %s\n' "$TGT_HOSTNAME" >> "$TGT_DIR/cloud-init/meta-data"
  fi
  if grep -q '^instance-id:' "$TGT_DIR/cloud-init/meta-data"; then
    sed -i '' -E "s/^instance-id:.*/instance-id: $INSTANCE_ID/" "$TGT_DIR/cloud-init/meta-data"
  else
    printf 'instance-id: %s\n' "$INSTANCE_ID" >> "$TGT_DIR/cloud-init/meta-data"
  fi
fi

# Rebuild seed ISO for target
( cd "$TGT_DIR" && mkisofs -output "${TGT_VM}-seed.iso" -volid cidata -joliet -rock cloud-init/user-data cloud-init/meta-data >/dev/null )

# Generate new MAC for target and write file
NEW_MAC=$(generate_mac "$TGT_VM")
echo "$NEW_MAC" > "$TGT_DIR/${TGT_VM}.mac"

# Register new VM in registry using source’s shape but new directory, mac, instance-id
SRC_INFO=$(get_vm_info "$SRC_VM" 2>/dev/null || true)
DISK_SIZE=$(echo "$SRC_INFO" | jq -r '.disk_size' 2>/dev/null || echo "")
OS_VERSION=$(echo "$SRC_INFO" | jq -r '.os_version' 2>/dev/null || echo "")
ARCH=$(echo "$SRC_INFO" | jq -r '.architecture' 2>/dev/null || echo "x86_64")
MEM_MB=$(echo "$SRC_INFO" | jq -r '.memory_mb' 2>/dev/null || get_mem_mb)
VCPUS=$(echo "$SRC_INFO" | jq -r '.vcpus' 2>/dev/null || get_vcpus)

register_vm "$TGT_VM" "$TGT_DIR" "$TGT_HOSTNAME" "$TGT_USERNAME" "${DISK_SIZE:-$(get_disk_size)}" "${OS_VERSION:-unknown}" "$NEW_MAC" "$INSTANCE_ID" "$ARCH" "$MEM_MB" "$VCPUS"

log "✅ Cloned '$SRC_VM' -> '$TGT_VM'"
log "  - Dir: $TGT_DIR"
log "  - Hostname: $TGT_HOSTNAME"
log "  - MAC: $NEW_MAC"
log "  - Instance ID: $INSTANCE_ID"
log "Next steps:"
log "  - Start VM: vm start $TGT_VM"
log "  - Check status: vm status $TGT_VM"

# Optional post-clone reset that keeps only configured items (Git/SSH/GitHub by default)
if [ "$POST_RESET" = true ]; then
  # Try to preseed a backup from the source so the target reset can be single-boot
  TGT_BACKUP_DIR="$TGT_DIR/.reset-backup"
  mkdir -p "$TGT_BACKUP_DIR"
  SRC_BACKUP_DIR="$SRC_DIR/.reset-backup"
  if [ "$POST_RESET_KEEP_HOME" = true ]; then
    if [ -f "$SRC_BACKUP_DIR/home-backup.tar.gz" ]; then
      log "Preseeding home backup from source to target for single-boot reset"
      cp "$SRC_BACKUP_DIR/home-backup.tar.gz" "$TGT_BACKUP_DIR/home-backup.tar.gz" || true
    else
      # Generate home-backup from source by briefly starting it (target remains single-boot)
      SRC_WAS_RUNNING=false
      SRC_STATUS_NOW=$(get_vm_status "$SRC_VM" || true)
      if [[ ! "$SRC_STATUS_NOW" =~ ^(running|booting|initializing|paused)$ ]]; then
        SRC_WAS_RUNNING=false
        log "Starting source VM '$SRC_VM' briefly to gather entire home..."
        "$SCRIPT_DIR/start-vm.sh" "$SRC_VM" --no-wait
        for i in {1..18}; do
          s=$(get_vm_status "$SRC_VM" || true)
          if [ "$s" = "running" ]; then break; fi
          sleep 10
        done
      else
        SRC_WAS_RUNNING=true
      fi

      SRC_IP=$(get_vm_best_ip "$SRC_VM" 2>/dev/null || true)
      if [ -n "$SRC_IP" ]; then
        # Determine source username
        SRC_USER="$TGT_USERNAME"
        u=$(echo "$SRC_INFO" | jq -r '.username' 2>/dev/null || echo "")
        if [ -n "$u" ] && [ "$u" != "null" ]; then SRC_USER="$u"; fi
        SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
        log "Streaming entire /home/$SRC_USER from source to target backup..."
        if ssh $SSH_OPTS "$SRC_USER@$SRC_IP" "tar -C /home -czf - $SRC_USER" > "$TGT_BACKUP_DIR/home-backup.tar.gz" 2>/dev/null; then
          :
        else
          log "Warning: Failed to preseed home-backup from source; proceeding without it"
          rm -f "$TGT_BACKUP_DIR/home-backup.tar.gz" || true
        fi
      fi

      if [ "$SRC_WAS_RUNNING" = false ]; then
        log "Stopping source VM '$SRC_VM' after seeding home backup"
        "$SCRIPT_DIR/stop-vm.sh" "$SRC_VM" >/dev/null 2>&1 || true
      fi
    fi
  else
    if [ -f "$SRC_BACKUP_DIR/keep-backup.tar.gz" ]; then
      log "Preseeding keep backup from source to target for single-boot reset"
      cp "$SRC_BACKUP_DIR/keep-backup.tar.gz" "$TGT_BACKUP_DIR/keep-backup.tar.gz" || true
    else
      # Attempt to generate keep-backup from source by briefly starting it (target remains single-boot)
      SRC_WAS_RUNNING=false
      SRC_STATUS_NOW=$(get_vm_status "$SRC_VM" || true)
      if [[ ! "$SRC_STATUS_NOW" =~ ^(running|booting|initializing|paused)$ ]]; then
        SRC_WAS_RUNNING=false
        log "Starting source VM '$SRC_VM' briefly to gather keep items..."
        "$SCRIPT_DIR/start-vm.sh" "$SRC_VM" --no-wait
        # Wait until running (up to ~3 minutes)
        for i in {1..18}; do
          s=$(get_vm_status "$SRC_VM" || true)
          if [ "$s" = "running" ]; then break; fi
          sleep 10
        done
      else
        SRC_WAS_RUNNING=true
      fi

      SRC_IP=$(get_vm_best_ip "$SRC_VM" 2>/dev/null || true)
      if [ -n "$SRC_IP" ]; then
        SRC_USER="$TGT_USERNAME"
        # Prefer source-recorded username if available
        u=$(echo "$SRC_INFO" | jq -r '.username' 2>/dev/null || echo "")
        if [ -n "$u" ] && [ "$u" != "null" ]; then SRC_USER="$u"; fi
        SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
        KEEP_ITEMS=$(get_keep_items | tr '\n' ' ')
        log "Gathering keep items from source and seeding target backup..."
        # Upload helper and run it remotely to stream tarball
        scp -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SCRIPT_DIR/scripts/prepare-keep-backup.sh" "$SRC_USER@$SRC_IP:/tmp/prepare-keep-backup.sh" 2>/dev/null || true
        if ssh $SSH_OPTS "$SRC_USER@$SRC_IP" env KEEP_ITEMS="$KEEP_ITEMS" bash /tmp/prepare-keep-backup.sh > "$TGT_BACKUP_DIR/keep-backup.tar.gz" 2>/dev/null; then
          :
        else
          log "Warning: Failed to preseed keep-backup from source; proceeding without it"
          rm -f "$TGT_BACKUP_DIR/keep-backup.tar.gz" || true
        fi
      fi

      # Stop source if we started it
      if [ "$SRC_WAS_RUNNING" = false ]; then
        log "Stopping source VM '$SRC_VM' after seeding backup"
        "$SCRIPT_DIR/stop-vm.sh" "$SRC_VM" >/dev/null 2>&1 || true
      fi
    fi
  fi

  if [ "$POST_RESET_KEEP_HOME" = true ]; then
    if [ "$POST_RESET_HARD" = true ]; then
  log "Running post-clone HARD reset (--reimage --keep-home) on '$TGT_VM' (reimage disk, keep full home)..."
      "$SCRIPT_DIR/reset-vm.sh" "$TGT_VM" --force --hard --keep-home
    else
      log "Running post-clone reset (--reset --keep-home) on '$TGT_VM' (keeping entire home)..."
      "$SCRIPT_DIR/reset-vm.sh" "$TGT_VM" --force --keep-home
    fi
  else
    if [ "$POST_RESET_HARD" = true ]; then
  log "Running post-clone HARD reset (--reimage) on '$TGT_VM' (reimage disk, keep items from keep.list)..."
      "$SCRIPT_DIR/reset-vm.sh" "$TGT_VM" --force --hard
    else
      log "Running post-clone reset (--reset) on '$TGT_VM' (keeping items from keep.list)..."
      "$SCRIPT_DIR/reset-vm.sh" "$TGT_VM" --force
    fi
  fi
fi
