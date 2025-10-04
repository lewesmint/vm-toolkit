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
- **✅ VM Registry**: Centralized tracking of all VMs and their status
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

**📦 Archive Installation**: The toolkit is designed to work from any directory. Download the archive, extract it anywhere, and run the installer. Your VMs and data will be stored in a separate configurable location (default: `~/vm-toolkit-data`).

For detailed installation options, see [INSTALL.md](INSTALL.md)

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
# Create a VM with defaults (x86_64)
vm create --name test

# Create an ARM64 VM (faster on Apple Silicon)
vm create --name test-arm --arch arm64

# Start the VM (will show console output)
vm start --name test --console

# In another terminal, check status
vm status --name test

# SSH to the VM when ready
ssh ubuntu@<vm-ip>
```

## 📋 Commands

### Core Commands

```bash
vm create --name <vm-name> [options]    # Create a new VM
vm start --name <vm-name> [options]     # Start a VM
vm stop --name <vm-name> [options]      # Stop a VM
vm status [--name <vm-name>]            # Show VM status
vm list                                 # List all VMs
vm destroy --name <vm-name> [options]   # Destroy a VM
vm sync                                 # Sync registry
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

### User Configuration

```bash
# Copy example config and customize
cp vm-toolkit/examples/vm-toolkit-config.example ~/.vm-toolkit-config
vim ~/.vm-toolkit-config
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

## 🏗️ VM Registry

The toolkit maintains a registry of all VMs in `.vm-registry.json`:

```bash
vm list                    # Show all VMs with status
vm status --name myvm      # Detailed status for specific VM
vm status --json           # JSON output for scripting
vm sync                    # Sync registry with actual state
```

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

### Toolkit Installation (can be anywhere)
```
vm-toolkit/                         # Toolkit installation directory
├── install.sh                     # Installation script
├── README.md                      # This file
├── INSTALL.md                     # Detailed installation guide
├── vm                             # Main VM command (symlinked to ~/bin/vm)
└── vm-toolkit/                    # Core toolkit scripts
    ├── create-vm.sh               # VM creation
    ├── destroy-vm.sh              # VM destruction
    ├── start-vm.sh                # VM startup
    ├── status-vm.sh               # Status checking
    ├── stop-vm.sh                 # VM shutdown
    ├── vm-config.sh               # Configuration system
    ├── vm-registry.sh             # Registry management
    └── examples/
        └── vm-toolkit-config.example # Configuration template
```

### Data Directory (configurable location)
```
~/vm-toolkit-data/                 # Default data directory (configurable)
├── .cache/                        # Cloud image cache
│   └── noble-server-cloudimg-amd64.img
├── .vm-registry.json             # VM registry database
└── vms/                           # VM storage
    ├── vm1/                       # Individual VM directories
    │   ├── vm1.qcow2              # VM disk image
    │   ├── vm1.pid                # Process ID file
    │   └── cloud-init/            # Cloud-init configuration
    └── vm2/
        └── ...
```

### Configuration
```
~/.vm-toolkit-config               # User configuration file
~/bin/vm                          # Command symlink (in PATH)
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

## 🔧 Troubleshooting

### VM won't start
- Check QEMU installation: `brew reinstall qemu`
- Verify vmnet support: `qemu-system-x86_64 -netdev help | grep vmnet`

### Can't find VM IP
- Wait 1-2 minutes for boot and DHCP
- Check: `vm status --name <vm-name>`
- Sync registry: `vm sync`

### SSH connection refused
- VM may still be booting (check console: `tail -f <vm-name>/console.log`)
- Check SSH service: `vm status --name <vm-name>`

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
