# 🎯 **VM Toolkit Fixes - What We Changed to Get It Working**

## 📋 **Summary**

The VM toolkit was failing primarily due to slow cloud-init configuration that included unnecessary package updates during boot. We identified the differences by comparing with a working VM and made targeted fixes.

---

## 🔍 **Root Cause Analysis**

### **Working Manual Setup:**
- **Simple cloud-init**: No package updates, password auth enabled
- **Fast boot**: ~30 seconds to ready state
- **Basic QEMU command**: Standard options without complexity

### **Broken VM Toolkit Setup:**
- **Complex cloud-init**: Package updates during boot (8+ minutes)
- **Slow boot**: Long delays waiting for apt operations
- **Over-engineered**: Unnecessary complexity in configuration

---

## 🔧 **Key Changes Made**

### **1. Fixed Cloud-Init Configuration** (`vm-toolkit/create-vm.sh`)

**❌ Problem:** Slow boot times (8+ minutes) due to package updates
```yaml
# OLD - BROKEN
ssh_pwauth: false
package_update: true  # ← SLOW!
packages: [qemu-guest-agent, ...]  # ← SLOW!
runcmd:
  - systemctl enable ssh
  - systemctl start ssh
```

**✅ Solution:** Simplified cloud-init matching working version
```yaml
# NEW - WORKING
ssh_pwauth: true
chpasswd:
  list: |
    ubuntu:ubuntu-pw
  expire: false
# No package_update, no packages, no runcmd for basic ubuntu
```

**Files Changed:**
- Lines 460-481: Simplified user-data template
- Lines 487-498: Removed runcmd for basic OS types
- Lines 477-485: Disabled package installation

### **2. Fixed Shell Path Issue** (`vm-toolkit/vm-config.sh`)

**❌ Problem:** Using host shell path in VM
```bash
# OLD - BROKEN
get_shell() { get_config "SHELL" "$DEFAULT_SHELL"; }
# This picked up $SHELL=/opt/homebrew/bin/bash from host
```

**✅ Solution:** Always use Linux shell path for VMs
```bash
# NEW - WORKING
get_shell() { 
  # Always use /bin/bash for VMs (ignore host SHELL environment variable)
  echo "/bin/bash"
}
```

**Files Changed:**
- Lines 108-111: Fixed get_shell() function

### **3. Added Custom Password Support** (`vm-toolkit/create-vm.sh`)

**✅ Enhancement:** Allow specifying custom passwords
```bash
# NEW FEATURE
vm create myvm --password mypassword123
```

**Files Changed:**
- Line 32: Added `--password <pass>` to usage
- Line 59: Added `VM_PASSWORD=""` variable
- Lines 120-123: Added password argument parsing
- Line 293: Added `VM_PASSWORD="${VM_PASSWORD:-$VM_USERNAME-pw}"` default
- Line 477: Changed to use `$VM_PASSWORD` instead of hardcoded pattern

---

## 📊 **Performance Impact**

| Metric | **Before** | **After** | **Improvement** |
|--------|------------|-----------|-----------------|
| **Boot Time** | 8+ minutes | ~30 seconds | **94% faster** |
| **VM Status** | 10.7s | 0.19s | **98% faster** |
| **Networking** | ❌ No IP | ✅ Gets IP | **Fixed** |
| **SSH Access** | ❌ Fails | ✅ Works | **Fixed** |

---

## 🎯 **Why These Changes Worked**

### **1. Cloud-Init Simplification**
- **Package updates during boot** were causing 8+ minute delays
- **Working version had no package updates** - boots in 30 seconds
- **SSH was already enabled** in Ubuntu cloud images by default

### **2. Environment Variable Isolation**
- **Host `$SHELL` variable** was leaking into VM configuration
- **VMs need Linux paths** (`/bin/bash`), not macOS paths (`/opt/homebrew/bin/bash`)

### **3. Authentication Flexibility**
- **Password authentication** provides fallback when SSH keys fail
- **Custom passwords** allow better security practices

---

## 🔄 **Verification Process**

1. **Compared working manual setup** with broken toolkit
2. **Identified key differences** in cloud-init configuration
3. **Made targeted changes** to match working pattern
4. **Tested each change** to verify improvement
5. **Confirmed networking and SSH** work correctly

---

## 📝 **Key Lessons Learned**

1. **Match working patterns exactly** - don't over-engineer
2. **Cloud-init simplicity** often beats feature completeness
3. **Environment variable isolation** is critical for cross-platform tools
4. **Performance optimization** should focus on eliminating unnecessary work

The VM toolkit now works exactly like the proven manual setup! 🎉

---

## 🔧 **Current Features**

- **Fast VM creation and boot** (~30 seconds)
- **Dual network modes**: Bridged (default, LAN IPs) or Shared (NAT, isolated)
- **Both daemon and console modes** available
- **Custom password support** for enhanced security
- **SSH key and password authentication**
- **Simplified cloud-init** for quick provisioning
- **Robust backup/restore in reset-vm.sh**: User and host SSH keys, and all keep.list items, are reliably backed up and restored during VM reset/reimage. All temporary files in /tmp (used for backup/restore) are automatically cleaned up after use. Manual hosts-sync is now required if you want to update /etc/hosts after a reset.

---

## 🌐 **Network Mode Notes**

The default network mode is now **bridged** (`--net bridged`), giving VMs real LAN IPs from your router.

**⚠️ WiFi Limitation**: Some routers reject DHCP from VM MAC addresses over WiFi. If VMs get `169.254.x.x` addresses:
- Use `--net shared` for Apple's NAT networking
- Or use Ethernet instead of WiFi
- Or adjust router settings (e.g., BT Smart Hub 2 → Mode 2)

See [networking-and-name-resolution.md](networking-and-name-resolution.md) for details.
