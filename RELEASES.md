# VM Toolkit Release History

## Version 1.0.0 - Initial Release (Current)

**Release Date**: October 2025

### 🎯 Major Features
- **Multi-Architecture Support**: x86_64 (primary), ARM64, i386
- **Apple Silicon Compatibility**: x86_64 emulation and native ARM64 support
- **Performance Options**: ARM64 VMs offer better performance on Apple Silicon
- **Flexible Installation**: Install from any directory with configurable data locations

### 🚀 New Features
- `--arch` parameter for VM creation (`arm64`, `x86_64`, `i386`)
- Architecture-specific QEMU binary selection
- Automatic acceleration detection (HVF on macOS, TCG elsewhere)
- Architecture-aware cloud image downloads
- VM registry stores architecture information
- Configurable installation and data directories

### 🔧 Technical Improvements
- Architecture detection and configuration functions
- Enhanced cloud image support for multiple architectures
- Improved dependency checking per architecture
- Better error handling and validation
- Comprehensive installation documentation

### 📦 Installation Methods
- Archive-based installation from GitHub releases
- Git clone installation
- Custom installation directories
- Configurable data storage locations

### 🏗️ Architecture Support Matrix

| Architecture | Status | Acceleration | Use Case |
|--------------|--------|--------------|----------|
| x86_64/AMD64 | ✅ Full | HVF/TCG | Primary architecture, maximum compatibility |
| ARM64/AArch64 | ✅ Full | HVF (macOS) | Performance option on Apple Silicon |
| i386 | ✅ Basic | TCG | Legacy applications |

### 🌍 Platform Support
- **Apple Silicon Macs Only**: M1, M2, M3, M4 (tested on M4 MacBook Pro)
- **Architecture Support**: x86_64 emulation, native ARM64 with HVF acceleration
- **Compatible Cloud Images**: Ubuntu, Debian, Fedora, CentOS for both architectures

### 📋 Breaking Changes
- None - fully backward compatible with v1.x VMs

---

## Version 1.0.0 - Initial Release

**Release Date**: October 2025

### 🎯 Core Features
- QEMU-based VM management for macOS
- True bridge networking via vmnet framework
- Cloud-init provisioning with SSH key support
- VM registry for centralized management
- Support for Ubuntu, Debian, Fedora, CentOS
- Nested virtualization (KVM support)

### 🔧 Technical Features
- x86_64 architecture support
- TCG acceleration
- Cloud image caching
- VM lifecycle management (create, start, stop, destroy)
- Status monitoring and IP detection
- Package installation during VM creation

### 📦 Installation
- Simple installation script
- Symlink creation for global access
- Configuration file support

### 🌐 Networking
- Bridge networking with real IP addresses
- No port forwarding required
- Direct SSH access
- Full network connectivity

---

## Upgrade Instructions

### From v1.x to v2.0
```bash
# Backup existing VMs (optional)
cp -r ~/vmq/vms ~/vm-backup

# Download and install v2.0
curl -L https://github.com/YOUR_USERNAME/vm-toolkit/archive/main.tar.gz | tar -xz
cd vm-toolkit-main
./install.sh --force

# Existing VMs will continue to work as x86_64 VMs
# Create new ARM64 VMs for better performance on Apple Silicon:
vm create --name fast-vm --arch arm64 --os ubuntu
```

### Migration Notes
- Existing VMs remain x86_64 and continue working
- VM registry is automatically updated with architecture info
- New ARM64 VMs can be created alongside existing x86_64 VMs
- Configuration files are preserved during upgrade

---

## Download Links

### Latest Release (v2.0.0)
- **Archive**: `https://github.com/YOUR_USERNAME/vm-toolkit/archive/main.tar.gz`
- **Git Clone**: `git clone https://github.com/YOUR_USERNAME/vm-toolkit.git`

### Previous Releases
- **v1.0.0**: Available in git history

---

## Support

For issues, feature requests, or questions:
- Create an issue on GitHub
- Check the documentation in `README.md` and `INSTALL.md`
- Review troubleshooting guides

---

## Roadmap

### Future Versions
- **v2.1**: Additional architecture support (RISC-V, PowerPC)
- **v2.2**: Enhanced cloud provider integration
- **v2.3**: GUI management interface
- **v3.0**: Container integration and Kubernetes support
