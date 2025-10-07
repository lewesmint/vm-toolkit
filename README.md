# VM Toolkit

**🍎 Apple Silicon Mac Virtual Machine Management Toolkit**

A comprehensive QEMU-based virtual machine management toolkit **exclusively for Apple Silicon Macs** (M1, M2, M3, M4) that provides a complete workflow for creating, managing, and controlling VMs with cloud-init provisioning and true bridge networking via the macOS vmnet framework.

**🎯 Primary Goal**: Enable x86_64 virtual machines on Apple Silicon Macs with true bridge networking and cloud-init provisioning. ARM64 support added for improved performance on compatible workloads.

**🖥️ Headless Server Focus**: This toolkit is designed for **headless server VMs** and **command-line automation**, deliberately avoiding GUI tools like UTM for several key reasons:

- **🚀 Automation-First**: Perfect for CI/CD, scripting, and infrastructure-as-code
- **🌐 True Bridge Networking**: VMs get real IP addresses (no NAT/port forwarding like UTM)
- **☁️ Cloud-Init Integration**: Industry-standard VM provisioning with SSH keys and packages
- **📦 Reproducible Deployments**: Configuration files and scripts for consistent VM creation
- **🔧 Developer Workflow**: Optimized for developers who prefer terminal-based tools
- **⚡ Lightweight**: No GUI overhead, just pure VM management functionality

**Why Not UTM?**
- UTM is excellent for desktop VMs with GUI, but this toolkit targets **server workloads**
- UTM uses NAT networking by default; this toolkit provides **real bridge networking**
- UTM focuses on interactive use; this toolkit enables **automation and scripting**
- UTM is GUI-centric; this toolkit is **CLI-native for DevOps workflows**

**⚠️ Platform Requirements**:
- **Apple Silicon Mac required** (M1, M2, M3, M4)
- **Tested on**: M4 Pro MacBook Pro
- **M4 Pro Performance**: On M4 Pro (and higher) chips, VMs have sufficient performance for **nested virtualization with KVM**, enabling Docker, Kubernetes, and container development workflows
- **Will NOT work on**: Intel Macs, Linux, or Windows

## 🎯 Key Features

- **✅ Headless Server VMs**: Designed for server workloads, not desktop GUI VMs
- **✅ True Bridge Networking**: VMs get real IP addresses on your network (no NAT/port forwarding)
- **✅ CLI-Only Management**: No GUI required, perfect for automation and DevOps
- **✅ Cloud-init Provisioning**: Industry-standard automated VM setup with SSH keys and packages
- **✅ Nested Virtualization**: Full KVM support inside VMs for container development
- **✅ Enhanced VM Defaults**: Dynamic CPU allocation (host cores - 2), 16GB RAM, 60GB disk
- **✅ VM Registry**: Live status tracking with static configuration storage
- **✅ VM Reset**: Clean slate development while preserving Git/SSH credentials
- **✅ Configurable Defaults**: Multiple configuration layers with precedence
- **✅ Multi-Architecture Support**: x86_64, ARM64, i386 with optimal acceleration
- **✅ Scriptable & Reproducible**: Perfect for infrastructure-as-code workflows

## 🎯 Perfect For

**Headless Server Development:**
- Web application development and testing
- Database servers (PostgreSQL, MySQL, Redis)
- Container development with Docker/Podman
- Kubernetes development with K3s/minikube
- **Nested Virtualization**: Full KVM support (especially powerful on M4 Pro and higher)
- CI/CD pipeline testing
- Microservices architecture development

**DevOps & Infrastructure:**
- Infrastructure-as-code testing
- Ansible playbook development
- Configuration management testing
- Network service development
- API development and testing

**NOT Suitable For:**
- Desktop Linux with GUI applications (use UTM instead)
- Gaming or graphics-intensive applications
- Interactive desktop environments

## 🚀 Quick Start

### 1. Installation

#### Quick Install (Recommended)
```bash
# Download latest release archive and install
curl -L https://github.com/YOUR_USERNAME/vm-toolkit/archive/refs/heads/main.tar.gz | tar -xz
cd vm-toolkit-main
./install.sh

# The installer creates a symlink: ~/bin/vm -> /path/to/vm-toolkit/vm
# and ensures ~/bin is in your PATH

# Now you can use 'vm' from anywhere
vm help
```

#### Alternative Methods
```bash
# Clone from git (for development)
git clone https://github.com/YOUR_USERNAME/vm-toolkit.git
cd vm-toolkit
./install.sh

# Custom installation location
./install.sh --install-dir /opt/vm-toolkit --data-dir /var/vm-data
```

**📦 Archive Installation**: The toolkit is designed to work from any directory. Download the archive, extract it anywhere, and run the installer. Your VMs and data will be stored in a configurable location (default: `./vm-toolkit-data` in the project directory).

For detailed installation options, see [INSTALL.md](INSTALL.md)
For recent changes and improvements, see [CHANGELOG.md](CHANGELOG.md)

### 2. Prerequisites

**⚠️ Apple Silicon Mac Required**: This toolkit only works on Apple Silicon Macs (M1, M2, M3, M4). It will not work on Intel Macs, Linux, or Windows.

```bash
# Install QEMU
brew install qemu

# Generate SSH key (if you don't have one)
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519

# Optional: Install jq for better registry support
brew install jq
```

### 3. Create and Start Your First VM

```bash
# Create a VM with enhanced defaults (x86_64, 12 cores, 16GB RAM, 60GB disk)
vm create --name test

# Create an ARM64 VM (faster on Apple Silicon)
vm create --name test-arm --arch arm64

# Start the VM (will show console output)
vm start --name test --console

# In another terminal, check status
vm status --name test

# SSH to the VM when ready (check status for IP and username)
vm status --name test
ssh <username>@<vm-ip>
```

## 📋 Commands

### Core Commands

```bash
vm create --name <vm-name> [options]    # Create a new VM
vm start --name <vm-name> [options]     # Start a VM
vm stop --name <vm-name> [options]      # Stop a VM
vm pause --name <vm-name>               # Pause a running VM
vm resume --name <vm-name>              # Resume a paused VM
vm status [--name <vm-name>]            # Show VM status with live checking
vm console --name <vm-name>             # Connect to VM console
vm list                                 # Quick list of all VMs
vm destroy --name <vm-name> [options]   # Destroy a VM completely
vm reset --name <vm-name> [options]     # Reset VM to original state (keep items from keep.list or entire home)
vm clone <src> <tgt> [options]          # Clone an existing VM to a new one
vm hosts-sync [--apply] [vms...]        # Sync /etc/hosts with best IPs for VMs
vm sync                                 # Sync registry with actual VM state
vm cleanup                              # Remove missing VMs from registry
vm help                                 # Show help
```

### Create Options

```bash
vm create --name myvm \
  --username developer \
  --disk 100G \
  --ubuntu noble \
  --packages "build-essential,docker.io,git"
```

### Start Options

```bash
vm start --name myvm \
  --mem 8192 \
  --vcpus 8 \
  --console        # Show console output
```

## ⚙️ Configuration

### Configuration Hierarchy (highest to lowest precedence):

1. **Command-line arguments** (always win)
2. **Environment variables** (`VM_*` prefix)
3. **User config file** (`~/.vm-toolkit-config`)
4. **System defaults** (`vm-toolkit/vm-config.sh`)

### Enhanced VM Defaults

**Optimized for Modern Development:**
- **CPU**: Dynamic allocation (host cores - 2, min 2, max 16)
  - M4 Pro (14 cores) → VMs get 12 cores
  - Automatically adapts to different host machines
- **Memory**: 16GB RAM (up from 4GB)
- **Disk**: 60GB storage (up from 40GB)
- **Performance**: Optimized QEMU flags (explicit SMP topology, writeback cache)
- **Networking**: Headless optimized (no GPU overhead)

**Resource Efficiency:**
- Uses 85.7% of host CPU cores (leaves 2 for host OS)
- Uses 33.3% of host RAM on 48GB systems
- Perfect balance of VM performance and host responsiveness

### User Configuration

```bash
# Copy example config and customize
cp vm-toolkit/examples/vm-toolkit-config.example ~/.vm-toolkit-config
vim ~/.vm-toolkit-config

# Override defaults if needed
echo 'VM_MEM_MB="8192"' >> ~/.vm-toolkit-config    # Use 8GB instead of 16GB
echo 'VM_DISK_SIZE="100G"' >> ~/.vm-toolkit-config # Use 100GB instead of 60GB
```

### Environment Variables

```bash
# Temporary override
VM_USERNAME="alice" VM_MEM_MB="8192" vm create --name dev

# Persistent override
export VM_USERNAME="alice"
export VM_DISK_SIZE="100G"
vm create --name workstation
```

### Keep List Configuration (for Resets and Post-Clone)

The toolkit can keep selected user items during a reset (and optional post-clone cleanup) using a configurable keep list.

- Defaults kept:
  - `~/.ssh`
  - `~/.gitconfig`
  - `~/.config/gh`
- Configuration file search order (highest precedence first):
  1) `$VM_KEEP_LIST_FILE` (env var, if set)
  2) `~/.vm-toolkit-keep.list`
  3) `<project>/vm-toolkit/keep.list`
  4) Toolkit default: `<repo>/vm-toolkit/keep.list`
- Backward compatibility: `VM_PRESERVE_LIST_FILE`, `~/.vm-toolkit-preserve.list`, and `<project>/vm-toolkit/preserve.list` are still honored if present.

Example `keep.list`:

```
# Paths are relative to the VM user's home
.ssh
.gitconfig
.config/gh
# Add more as needed, e.g.:
.config/nvim
.config/fish
```

## 🏗️ VM Registry

The toolkit maintains a registry of all VMs with enhanced architecture:

**Static Configuration Storage:**
- VM metadata: name, hostname, username, disk size, memory, vCPUs
- Creation details: OS version, architecture, MAC address, instance ID
- Timestamps: created, updated

**Live Status Computation:**
- VM status computed in real-time from system state
- No stale cached status - always current
- Status includes: running, stopped, paused, initializing, booting

```bash
vm list                    # Quick list with live status
vm status --name myvm      # Detailed status with IP, uptime, SSH availability
vm status --json           # JSON output for scripting
vm sync                    # Sync registry (removes phantom VMs)
vm cleanup                 # Remove missing VMs from registry
```

### Status modes and IP selection

Status collection prioritizes accuracy while offering faster modes:

- Default mode: Uses multiple signals to find the “best IP”
  - ARP (with MAC normalization on macOS)
  - DNS fallback
  - Console log parsing for DHCP-assigned IPs
  - SSH reachability probe to avoid stale DNS/ARP
- `--fast`: Skips slower checks like DNS resolution and stats
- `--basic`: PID-only (no IP/SSH), fastest for quick overviews

This logic reduces “initializing/booting” misreports when IPs change and DNS/ARP are stale.

## 🏗️ Multi-Architecture Support

The toolkit supports multiple CPU architectures with optimal performance:

### **x86_64/AMD64** 🔧 (Primary Architecture - Default)
```bash
vm create --name compat-vm --arch x86_64 --os ubuntu  # Default
```
- **Primary use case**: Maximum software compatibility
- All existing Docker images and x86_64 software
- **Note**: Runs via emulation on Apple Silicon (slower but fully compatible)

### **ARM64/AArch64** ⚡ (Performance Option on Apple Silicon)
```bash
vm create --name fast-vm --arch arm64 --os ubuntu
```
- **Native performance** on Apple Silicon Macs
- Uses HVF acceleration for optimal speed
- Growing ecosystem support (Docker, cloud images)
- Good for cloud-native development on ARM64 platforms

### **i386** 🕰️ (Legacy Support)
```bash
vm create --name legacy-vm --arch i386 --os debian
```
- 32-bit x86 support
- Legacy software and embedded development
- Limited cloud image availability

### **Architecture Performance on Apple Silicon**

| Architecture | Performance | Use Case | Acceleration |
|--------------|-------------|----------|--------------|
| **x86_64** | 🔧 **Emulated** | Maximum software compatibility | TCG Emulation |
| **ARM64** | ⚡ **Native** | Better performance when ARM64 software is available | HVF |

**💡 Recommendation**: Use x86_64 for maximum compatibility with existing software, ARM64 when you have ARM64-compatible software and want better performance.

### **Architecture Detection**
The toolkit automatically:
- Detects your host architecture
- Uses optimal acceleration (HVF on macOS, TCG elsewhere)
- Downloads correct cloud images for each architecture
- Configures QEMU with architecture-specific settings

## 🌐 Bridge Networking

VMs use **true bridge networking** via macOS vmnet framework:

- **Real IP addresses** from your router's DHCP
- **Direct SSH access** on port 22 (no port forwarding)
- **Full network connectivity** like physical machines
- **Requires sudo** for vmnet access (Apple security requirement)

## 📁 Project Structure

### Complete Project Structure
```
vm-toolkit/                         # Project root directory
├── install.sh                     # Installation script
├── README.md                      # This file
├── INSTALL.md                     # Detailed installation guide
├── vm                             # Main VM command (symlinked to ~/bin/vm)
├── vm-toolkit/                    # Core toolkit scripts
│   ├── create-vm.sh               # VM creation
│   ├── destroy-vm.sh              # VM destruction
│   ├── start-vm.sh                # VM startup
│   ├── status-vm.sh               # Status checking
│   ├── stop-vm.sh                 # VM shutdown
│   ├── vm-config.sh               # Configuration system
│   ├── vm-registry.sh             # Registry management
│   └── examples/
│       └── vm-toolkit-config.example # Configuration template
└── vm-toolkit-data/               # VM data directory (default location)
    ├── .cache/                    # Cloud image cache
    ├── .vm-registry.json          # VM registry database
    └── vms/                       # Individual VM directories
```

### Configuration
```
~/.vm-toolkit-config               # User configuration file
~/bin/vm -> /path/to/vm-toolkit/vm # Command symlink (in PATH)
```

## 💡 Examples

### Development Environment

```bash
# Create development VM
vm create --name dev \
  --username developer \
  --disk 100G \
  --packages "build-essential,git,docker.io,nodejs,npm"

# Start with more resources
vm start --name dev --mem 8192 --vcpus 8
```

### Multiple Test VMs

```bash
# Create lightweight test VMs
VM_MEM_MB="2048" VM_VCPUS="2" VM_DISK_SIZE="20G" vm create --name test1
VM_MEM_MB="2048" VM_VCPUS="2" VM_DISK_SIZE="20G" vm create --name test2

# Start both
vm start --name test1 &
vm start --name test2 &

# Check status
vm list
```

### VM Reset (Clean Slate Development)

```bash
# Reset VM to original cloud image state while keeping selected settings
vm reset --name dev

# What gets kept by default (configurable via keep.list):
#   ✅ SSH keys (~/.ssh/)
#   ✅ Git configuration (~/.gitconfig)
#   ✅ GitHub CLI authentication (~/.config/gh/)

# What gets reset:
#   ❌ All installed packages (snap, apt, etc.)
#   ❌ System configuration
#   ❌ Other files in home directory

# Options:
vm reset --name dev --force         # Skip confirmation
vm reset --name dev --keep-home     # Keep entire home directory

# Perfect for:
# - Cleaning up after experiments
# - Starting fresh but keeping Git access
# - Removing accumulated cruft while preserving credentials
```

### Clone VMs

```bash
# Clone src -> tgt, update hostname/username, and force re-provisioning
vm clone src tgt --hostname tgt --username developer --fresh

# Clone and immediately reset the new VM, keeping only keep.list items
vm clone src tgt --reset

# Clone and keep entire home on the reset (post-clone)
vm clone src tgt --reset --keep-home
```

Notes:
- The overlay disk is rebased to the new base image automatically.
- A new MAC address is generated for the target VM.
- Safety: cloning a running VM is blocked unless `--force` is provided.
- `--fresh` regenerates the cloud-init instance-id to re-run provisioning.

### Sync /etc/hosts with VM IPs

```bash
# Dry-run (shows proposed mappings)
vm hosts-sync

# Apply changes to /etc/hosts (requires sudo)
vm hosts-sync --apply

# Only specific VMs
vm hosts-sync --apply alpha bravo
```

This helper writes the toolkit’s “best” IP for each VM into `/etc/hosts` to avoid stale DNS/ARP. On macOS, you can flush caches if needed:

```bash
sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder
```

## 🏗️ Architecture

### Registry Design (v1.1+)
The VM registry has been redesigned for better reliability:
- **Static configuration only**: Registry stores only immutable VM properties (name, disk size, creation time, MAC address)
- **Live status computation**: VM status is computed in real-time from system state (process running, IP available, SSH ready)
- **No stale data**: Status always reflects current reality, not cached values
- **Simplified sync**: Registry sync only removes VMs with missing directories

### Status States
- `missing` → VM directory doesn't exist
- `stopped` → Directory exists, no process running
- `initializing` → Process running, no IP yet
- `booting` → Process running, has IP, SSH not ready
- `running` → Process running, has IP, SSH ready

## 🚀 VM Quickstart Script

The toolkit includes a quickstart script for setting up fresh VMs with development tools:

**Location**: `vm-quickstart/vm-setup.sh`

**What it does:**
- Installs essential development tools (GitHub CLI, vim, htop, build-essential)
- Authenticates with GitHub (browser-based)
- Automatically configures Git with your GitHub credentials
- Optionally clones repositories

**Usage:**
```bash
# Copy to VM and run
scp vm-quickstart/vm-setup.sh mintz@myvm:~/
ssh mintz@myvm './vm-setup.sh'

# Or copy to specific directory
ssh mintz@myvm "mkdir -p ~/kube"
scp vm-quickstart/vm-setup.sh mintz@myvm:~/kube/
ssh mintz@myvm 'cd ~/kube && ./vm-setup.sh'
```

**Perfect for:**
- Setting up fresh VMs quickly
- Standardizing development environments
- Getting GitHub access configured automatically

## 🔧 Troubleshooting

### VM won't start
- Check QEMU installation: `brew reinstall qemu`
- Verify vmnet support: `qemu-system-x86_64 -netdev help | grep vmnet`

### Can't find VM IP
- Wait 1-2 minutes for boot and DHCP
- Check: `vm status --name <vm-name>`
- Try faster status modes if you only need a snapshot: `vm status --fast` or `vm status --basic`
- Sync registry: `vm sync`
- If DNS/ARP is stale on macOS, run: `vm hosts-sync --apply` and then flush caches (`sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder`)

### SSH connection refused or slow to appear
- VM may still be booting (check console: `tail -f vm-toolkit-data/vms/<vm>/console.log`)
- The toolkit enables and starts SSH via cloud-init on major OSes:
  - Ubuntu/Debian: `systemctl enable --now ssh`
  - Fedora/CentOS: `systemctl enable --now sshd`
- Give it a minute for cloud-init to finish; status will indicate SSH reachability.

## 🎊 Success Criteria

When everything works, you should see:

```bash
$ vm list
🏗️  VM Status Overview
====================
VM NAME      STATUS     IP ADDRESS      SSH COMMAND          UPTIME    
--------     ------     ----------      -----------          -------   
dev          running    192.168.1.100   ssh developer@192.168.1.100  01:23:45
test         running    192.168.1.101   ssh ubuntu@192.168.1.101     00:05:12

$ ssh developer@192.168.1.100
Welcome to Ubuntu 24.04.3 LTS (GNU/Linux 6.8.0-85-generic x86_64)
developer@dev:~$ kvm-ok
INFO: /dev/kvm exists
KVM acceleration can be used
```

## 📝 Notes

- **Performance**: x86_64 VMs run via emulation (slower), ARM64 VMs use native acceleration (faster)
- **Sudo required**: vmnet framework needs elevated privileges
- **MAC addresses**: Automatically generated based on VM name
- **Cloud images**: Cached in `.cache/` directory
- **Nested virtualization**: Fully functional KVM inside VMs (excellent performance on M4 MAX)
- **M4 MAX advantage**: Superior performance for container development and nested virtualization workloads

## ⚖️ License

This project is licensed under the MIT License with additional disclaimers - see the [LICENSE](LICENSE) file for details.

**⚠️ USE AT YOUR OWN RISK**: This software manages virtual machines and requires elevated privileges. Users assume all responsibility for any consequences of its use.
