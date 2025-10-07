#!/usr/bin/env bash
set -euo pipefail

# This script runs on the SOURCE VM.
# It assembles /tmp/keep containing selected items from $HOME and emits
# a tar.gz archive of that directory to stdout.
# Inputs:
#   - KEEP_ITEMS: space-separated list of paths relative to $HOME (e.g., ".ssh .gitconfig .config/gh")

KEEP_ITEMS=${KEEP_ITEMS:-}

mkdir -p /tmp/keep

# Copy requested items if present
for item in $KEEP_ITEMS; do
  if [ -e "$HOME/$item" ]; then
    dir=$(dirname "$item")
    mkdir -p "/tmp/keep/$dir"
    cp -a "$HOME/$item" "/tmp/keep/$item" 2>/dev/null || true
  fi
done

# Create restore.sh to enable one-shot restore on target
cat > /tmp/keep/restore.sh << 'EOF'
#!/usr/bin/env bash
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
[ -d ~/.ssh ] && chmod 700 ~/.ssh && chmod 600 ~/.ssh/* 2>/dev/null || true
echo '✅ Kept settings restored'
EOF
chmod +x /tmp/keep/restore.sh

# Save keep list
printf '%s\n' $KEEP_ITEMS > /tmp/keep/.list

# Emit archive to stdout
tar -C /tmp -czf - keep
