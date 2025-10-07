# Changelog

All notable changes to the VM Toolkit project will be documented in this file.

## [v1.2.0] - 2025-10-07

### ✨ Features

- Keep semantics and configuration
	- Renamed “preserve” → “keep” across scripts and docs, with full backward compatibility
	- Added configurable keep list used by resets and post-clone cleanup
		- Search order: $VM_KEEP_LIST_FILE → ~/.vm-toolkit-keep.list → <project>/vm-toolkit/keep.list → toolkit default
		- Back-compat supported: VM_PRESERVE_LIST_FILE and preserve.list files
- Reset improvements
	- Primary flag: `--keep-home` (keeps entire home); default keeps items from keep.list
	- Fixed variable mismatch bugs and clarified logs/prompts
- Clone workflow
	- `--reset` to immediately clean the new VM while keeping items from keep.list
	- New `--keep-home` (with --reset) to keep entire home during post-clone reset
	- Overlay rebase fix: cloned qcow2 now correctly rebased to the new base filename
- Name resolution helper
	- New `vm hosts-sync` to map VM names to best IPs in /etc/hosts (dry-run/apply)
	- macOS-safe sed usage and cache flush guidance
- Status accuracy and performance
	- Best-IP selection combines ARP (normalized MAC), DNS fallback, console-derived IPs, and SSH reachability
	- Added `--fast` and `--basic` status modes for quicker overviews
- SSH readiness
	- Cloud-init runcmd enables/starts ssh/sshd for Ubuntu/Debian/Fedora/CentOS

### 🧹 Misc

- README refreshed to document keep.list, status modes, clone flags, hosts-sync, and troubleshooting for stale DNS/ARP

## [v1.1.0] - 2024-10-04

### 🏗️ **Major Architecture Improvements**

#### Data Directory Location
- **BREAKING**: Default data directory moved from `~/vm-toolkit-data` to `./vm-toolkit-data` (project root)
- **Benefit**: Cleaner project structure, easier backup, better portability
- **Migration**: Existing installations continue to work via user config overrides
- **Installer**: New installations default to project root location

#### Registry Architecture Redesign
- **BREAKING**: Registry no longer stores dynamic state (status, pid, ip_address)
- **NEW**: Registry only stores static configuration (name, disk_size, created_time, mac_address)
- **NEW**: VM status computed live from system state (more accurate, no stale data)
- **NEW**: Simplified registry sync - only removes missing VMs
- **Benefit**: Eliminates stale data issues, more reliable status detection

#### Status Detection Improvements
- **NEW**: Live status computation from actual system state
- **NEW**: Clear status states: missing, stopped, initializing, booting, running
- **FIXED**: Status always reflects current reality, not cached values
- **PERFORMANCE**: Status detection is now more reliable and accurate

### 🐛 **Bug Fixes**

#### Write Lock Errors
- **FIXED**: "Failed to get shared write lock" errors when destroying running VMs
- **CHANGE**: Removed unnecessary disk size checks during VM destruction
- **BENEFIT**: Can now safely destroy running VMs without errors

#### Console Output
- **FIXED**: Console log paths now show full absolute paths
- **IMPROVEMENT**: Console paths are copy-pasteable and accurate
- **EXAMPLE**: `/Users/user/vmq/vm-toolkit-data/vms/alpha/console.log`

### 📚 **Documentation Updates**

- **UPDATED**: README.md reflects new data directory location
- **UPDATED**: INSTALL.md updated with new default paths
- **ADDED**: Architecture section explaining registry design
- **ADDED**: Status states documentation
- **UPDATED**: Project structure shows complete layout

### 🔄 **Migration Guide**

#### For Existing Users
Your existing installation continues to work unchanged. The user config file (`~/.vm-toolkit-config`) overrides the new defaults.

#### For New Installations
- Data will be stored in `./vm-toolkit-data` by default
- All VM operations work the same way
- Better project organization and portability

#### Manual Migration (Optional)
```bash
# Move data to project root (optional)
mv ~/vm-toolkit-data ./vm-toolkit-data

# Update user config
sed -i 's|~/vm-toolkit-data|./vm-toolkit-data|' ~/.vm-toolkit-config

# Verify everything works
vm list
```

### 🎯 **Benefits Summary**

1. **Cleaner Architecture**: Static vs dynamic data clearly separated
2. **More Reliable**: Status always reflects current system state
3. **Better Organization**: All project data in one place
4. **Easier Backup**: Single directory contains everything
5. **No More Lock Errors**: Safe VM destruction operations
6. **Accurate Status**: Live computation eliminates stale data

---

## [v1.0.0] - 2024-10-03

### 🎉 **Initial Release**

- Complete VM toolkit for Apple Silicon Macs
- Support for x86_64 and ARM64 virtual machines
- Bridge networking with real IP addresses
- Cloud-init integration for VM configuration
- Registry-based VM management
- Comprehensive CLI interface
- Installation and setup automation
