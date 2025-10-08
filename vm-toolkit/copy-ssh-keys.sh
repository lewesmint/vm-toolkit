#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/vm-config.sh"
source "$SCRIPT_DIR/vm-registry.sh"

usage() {
  cat <<EOF
Usage: vm keys-copy <vm-name> [--private <path>] [--public <path>]

Copies your host SSH keys into the VM user's ~/.ssh directory.
By default, uses VM_SSH_KEY for public key and derives private key
by stripping .pub; override with --private/--public.

Security note: This copies your private key into the VM. Only use on
trusted VMs you control.
EOF
}

VM_NAME="${1:-}"
shift || true

PRIV_OVERRIDE=""
PUB_OVERRIDE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --private)
      PRIV_OVERRIDE="$2"; shift 2 ;;
    --public)
      PUB_OVERRIDE="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

if [ -z "$VM_NAME" ]; then
  usage; exit 1
fi

VM_DIR="${VM_BASE_DIR}/${VM_NAME}"
if [ ! -d "$VM_DIR" ]; then
  echo "VM not found: $VM_NAME ($VM_DIR)" >&2
  exit 1
fi

# Determine VM username from cloud-init user-data or fallback
VM_USERNAME=""
if [ -f "$VM_DIR/cloud-init/user-data" ]; then
  VM_USERNAME=$(grep -A5 '^users:' "$VM_DIR/cloud-init/user-data" | grep -m1 'name:' | sed 's/.*name: *//' | tr -d '\r' || true)
fi
VM_USERNAME="${VM_USERNAME:-$(get_username)}"

# Resolve keys
PUB_KEY_PATH="${PUB_OVERRIDE:-$(get_ssh_key)}"
if [ ! -f "$PUB_KEY_PATH" ]; then
  echo "Public key not found: $PUB_KEY_PATH" >&2
  exit 1
fi

PRIV_KEY_PATH="${PRIV_OVERRIDE:-$(get_ssh_private_key)}"
if [ -z "$PRIV_KEY_PATH" ] || [ ! -f "$PRIV_KEY_PATH" ]; then
  echo "Private key not found; set VM_SSH_KEY/SSH_PRIVATE_KEY or use --private" >&2
  exit 1
fi

# Wait for SSH readiness (up to 90s) using best IP or name
TARGET_HOST="$VM_NAME"
for i in {1..30}; do
  ip=$(get_vm_best_ip "$VM_NAME" 2>/dev/null || true)
  if [ -n "$ip" ]; then TARGET_HOST="$ip"; fi
  if timeout 3 nc -z "$TARGET_HOST" 22 2>/dev/null; then break; fi
  sleep 3
done

# Stage keys to remote tmp and install with strict permissions
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
TMPDIR="/tmp/.sshcopy-$$"
scp -q $SSH_OPTS "$PRIV_KEY_PATH" "$PUB_KEY_PATH" "$VM_USERNAME@$TARGET_HOST:$TMPDIR/" 2>/dev/null || {
  ssh $SSH_OPTS "$VM_USERNAME@$TARGET_HOST" "mkdir -p '$TMPDIR'" || true
  scp -q $SSH_OPTS "$PRIV_KEY_PATH" "$PUB_KEY_PATH" "$VM_USERNAME@$TARGET_HOST:$TMPDIR/"
}

BASE="$(basename "$PRIV_KEY_PATH")"
PUBB="$(basename "$PUB_KEY_PATH")"
ssh $SSH_OPTS "$VM_USERNAME@$TARGET_HOST" bash -s <<'RSYNC_EOF'
set -e
TMPDIR="$(ls -d /tmp/.sshcopy-* 2>/dev/null | tail -n1 || echo /tmp/.sshcopy)"
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
if [ -f "$TMPDIR/$BASE" ]; then
  mv "$TMPDIR/$BASE" "$HOME/.ssh/$BASE"
  chmod 600 "$HOME/.ssh/$BASE"
fi
if [ -f "$TMPDIR/$PUBB" ]; then
  mv "$TMPDIR/$PUBB" "$HOME/.ssh/$PUBB"
  chmod 644 "$HOME/.ssh/$PUBB" 2>/dev/null || chmod 600 "$HOME/.ssh/$PUBB" || true
  touch "$HOME/.ssh/authorized_keys"
  chmod 600 "$HOME/.ssh/authorized_keys"
  if ! grep -F -x -q -f "$HOME/.ssh/$PUBB" "$HOME/.ssh/authorized_keys" 2>/dev/null; then
    cat "$HOME/.ssh/$PUBB" >> "$HOME/.ssh/authorized_keys"
  fi
fi
rm -rf "$TMPDIR" 2>/dev/null || true
RSYNC_EOF

echo "✅ Copied SSH keys to $VM_NAME as $VM_USERNAME (~/.ssh/$BASE and .pub; authorized_keys updated)"