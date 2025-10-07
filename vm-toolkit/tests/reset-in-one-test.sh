#!/bin/bash

# Test whether a reset can be performed with only one reboot
# Accepts the same arguments as reset-vm.sh but makes NO changes.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../vm-config.sh"
source "$SCRIPT_DIR/../vm-registry.sh"
source "$SCRIPT_DIR/../vm-common.sh"

show_usage() {
	cat << EOF
Usage: $0 <vm-name> [options]

Test whether a reset would complete with only one reboot.
No changes are made to the VM or host.

Required:
	<vm-name>             VM name to evaluate

Options (same as reset-vm):
	--keep-home           Consider a reset that preserves entire home directory
	--force               Ignored (accepted for compatibility)
	--help                Show this help

Exit codes:
	0  Single-boot reset is achievable right now
	1  Single-boot reset is not currently achievable
	2  Unknown/invalid VM

Examples:
	$0 alpha                 # Test default keep.list mode
	$0 alpha --keep-home     # Test keep-home mode
EOF
}

VM_NAME=""
KEEP_HOME=false

while [[ $# -gt 0 ]]; do
	case $1 in
		--keep-home)
			KEEP_HOME=true; shift ;;
		--preserve-home)
			KEEP_HOME=true; shift ;;
		--force)
			# accepted for compatibility with reset-vm; no effect here
			shift ;;
		--help|-h)
			show_usage; exit 0 ;;
		-*)
			echo "Unknown option: $1" >&2
			show_usage; exit 1 ;;
		*)
			if [ -z "$VM_NAME" ]; then VM_NAME="$1"; else
				echo "Multiple VM names specified: $VM_NAME and $1" >&2; exit 1; fi
			shift ;;
	esac
done

if [ -z "$VM_NAME" ]; then
	echo "VM name is required" >&2
	show_usage
	exit 2
fi

# Validate VM and compute paths
if ! VM_DIR=$(ensure_vm_exists "$VM_NAME" 2>/dev/null); then
	echo "VM '$VM_NAME' not found" >&2
	exit 2
fi
HOST_BACKUP_DIR="$VM_DIR/.reset-backup"
KEEP_BACKUP_FILE="$HOST_BACKUP_DIR/keep-backup.tar.gz"
HOME_BACKUP_FILE="$HOST_BACKUP_DIR/home-backup.tar.gz"

NEED_FILE="$KEEP_BACKUP_FILE"
MODE_DESC="keep.list items"
if [ "$KEEP_HOME" = true ]; then
	NEED_FILE="$HOME_BACKUP_FILE"
	MODE_DESC="entire home directory"
fi

mkdir -p "$HOST_BACKUP_DIR" >/dev/null 2>&1 || true

# Current state
STATUS=$(get_vm_status "$VM_NAME" 2>/dev/null || echo "unknown")

echo "Test: reset-in-one for VM '$VM_NAME' (mode: $MODE_DESC)"
echo "  VM status: $STATUS"
echo "  Required backup: $NEED_FILE"

if [ -f "$NEED_FILE" ]; then
	echo "PASS: Single-boot reset is achievable now (backup already present)."
	echo "Hint: Run 'vm reset $VM_NAME' with your desired options to perform it."
	exit 0
fi

if [ "$STATUS" = "running" ]; then
	echo "CONDITIONAL: Backup not present, but VM is running."
	echo "  You can create the backup now (without extra boots), then run reset for a single reboot."
	echo "  Suggested approach:"
	if [ "$KEEP_HOME" = true ]; then
		# Suggest streaming home-backup (mirror of reset-vm backup step)
		USERNAME=$(get_vm_info "$VM_NAME" | jq -r '.username // "mintz"')
		echo "    - Stream home to host: (no changes made by this test)"
		echo "      ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $USERNAME@$VM_NAME 'tar -C /home -czf - $USERNAME' > '$HOME_BACKUP_FILE'"
	else
		echo "    - Stream keep.list items using helper:"
		echo "      scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null '$SCRIPT_DIR/../scripts/prepare-keep-backup.sh' $USERNAME@$VM_NAME:/tmp/prepare-keep-backup.sh"
		echo "      KEEP_ITEMS=\"$(get_keep_items | paste -sd' ' -)\" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $USERNAME@$VM_NAME bash /tmp/prepare-keep-backup.sh > '$KEEP_BACKUP_FILE'"
	fi
	echo "  After creating the backup, run: vm reset $VM_NAME [--keep-home]"
	exit 1
fi

echo "FAIL: Backup not present and VM is not running."
echo "  A reset now would require an extra boot to collect backup before resetting."
echo "  Options:"
echo "   - Start VM and create the backup first (see steps above), then reset"
echo "   - Or perform 'vm reset' directly (will incur two boots)"
exit 1

