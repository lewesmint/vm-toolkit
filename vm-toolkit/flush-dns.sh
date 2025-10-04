#!/bin/bash

# VM Toolkit DNS Cache Flush Utility
# Flushes macOS DNS cache to resolve hostname resolution issues with VMs

set -euo pipefail

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/vm-config.sh"

# Function to display usage
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] [VM_NAME]

Flush macOS DNS cache to resolve VM hostname resolution issues.

OPTIONS:
    -h, --help      Show this help message
    -v, --verbose   Show detailed output
    -t, --test      Test hostname resolution after flush

EXAMPLES:
    $(basename "$0")                    # Flush DNS cache
    $(basename "$0") -t                 # Flush and test all running VMs
    $(basename "$0") -t gamma           # Flush and test specific VM
    $(basename "$0") --verbose          # Show detailed output

DESCRIPTION:
    This utility fixes the common macOS issue where:
    - nslookup/dig work for VM hostnames
    - ping/ssh fail with "cannot resolve hostname"
    
    The script flushes both the system DNS cache and restarts
    the mDNS responder service to pick up new VM hostname entries.

EOF
}

# Function to log messages
log() {
    echo "[$(date '+%H:%M:%S')] $*"
}

# Function to log verbose messages
verbose() {
    if [ "$VERBOSE" = true ]; then
        echo "[VERBOSE] $*"
    fi
}

# Function to flush DNS cache
flush_dns_cache() {
    log "🔄 Flushing macOS DNS cache..."
    
    verbose "Running: sudo dscacheutil -flushcache"
    if sudo dscacheutil -flushcache 2>/dev/null; then
        verbose "✅ System DNS cache flushed"
    else
        echo "❌ Failed to flush system DNS cache"
        return 1
    fi
    
    verbose "Running: sudo killall -HUP mDNSResponder"
    if sudo killall -HUP mDNSResponder 2>/dev/null; then
        verbose "✅ mDNS responder restarted"
    else
        echo "❌ Failed to restart mDNS responder"
        return 1
    fi
    
    log "✅ DNS cache flushed successfully"
    
    # Give DNS services a moment to restart
    sleep 2
}

# Function to test hostname resolution
test_hostname() {
    local hostname="$1"
    local result
    
    verbose "Testing hostname resolution for: $hostname"
    
    # Test with dscacheutil (system resolver)
    result=$(dscacheutil -q host -a name "$hostname" 2>/dev/null | grep "ip_address:" | cut -d' ' -f2)
    
    if [ -n "$result" ]; then
        echo "  ✅ $hostname → $result"
        return 0
    else
        echo "  ❌ $hostname → not resolved"
        return 1
    fi
}

# Function to test all running VMs
test_all_vms() {
    log "🧪 Testing hostname resolution for running VMs..."
    
    # Source registry functions
    source "$SCRIPT_DIR/vm-registry.sh"
    
    local tested=0
    local passed=0
    
    # Get list of running VMs
    local running_vms
    running_vms=$(jq -r '.vms | to_entries[] | select(.value.status == "running") | .key' "$REGISTRY_FILE" 2>/dev/null || echo "")
    
    if [ -z "$running_vms" ]; then
        echo "  ℹ️  No running VMs found"
        return 0
    fi
    
    for vm_name in $running_vms; do
        tested=$((tested + 1))
        if test_hostname "$vm_name"; then
            passed=$((passed + 1))
        fi
    done
    
    echo ""
    log "📊 Test Results: $passed/$tested VMs resolving correctly"
    
    if [ "$passed" -eq "$tested" ]; then
        log "🎉 All running VMs are resolving correctly!"
        return 0
    else
        log "⚠️  Some VMs are not resolving - you may need to wait or restart them"
        return 1
    fi
}

# Function to test specific VM
test_specific_vm() {
    local vm_name="$1"
    
    log "🧪 Testing hostname resolution for VM: $vm_name"
    
    if test_hostname "$vm_name"; then
        log "✅ VM '$vm_name' is resolving correctly"
        return 0
    else
        log "❌ VM '$vm_name' is not resolving"
        echo ""
        echo "Troubleshooting suggestions:"
        echo "  1. Wait a few more seconds for DNS propagation"
        echo "  2. Check if VM is fully booted: vm status $vm_name"
        echo "  3. Try direct DNS query: nslookup $vm_name"
        echo "  4. Restart the VM if needed: vm restart $vm_name"
        return 1
    fi
}

# Parse command line arguments
VERBOSE=false
TEST_MODE=false
VM_NAME=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -t|--test)
            TEST_MODE=true
            shift
            ;;
        -*)
            echo "Error: Unknown option $1"
            usage
            exit 1
            ;;
        *)
            if [ -z "$VM_NAME" ]; then
                VM_NAME="$1"
            else
                echo "Error: Multiple VM names specified"
                usage
                exit 1
            fi
            shift
            ;;
    esac
done

# Main execution
main() {
    log "🚀 VM Toolkit DNS Cache Flush Utility"
    echo ""
    
    # Check if we need sudo access
    if ! sudo -n true 2>/dev/null; then
        log "🔐 This operation requires sudo access to flush DNS cache"
        echo "Please enter your password:"
    fi
    
    # Flush DNS cache
    if ! flush_dns_cache; then
        exit 1
    fi
    
    echo ""
    
    # Run tests if requested
    if [ "$TEST_MODE" = true ]; then
        if [ -n "$VM_NAME" ]; then
            test_specific_vm "$VM_NAME"
        else
            test_all_vms
        fi
    else
        log "💡 Tip: Use -t flag to test hostname resolution after flush"
        if [ -n "$VM_NAME" ]; then
            log "💡 Example: $(basename "$0") -t $VM_NAME"
        fi
    fi
    
    echo ""
    log "🎯 DNS cache flush complete!"
}

# Run main function
main "$@"
