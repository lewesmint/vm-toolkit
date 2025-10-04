# VM Toolkit Installation Guide

The VM Toolkit can be installed from any directory and configured to store VMs and data wherever you prefer.

## Quick Installation

### From GitHub Release (Recommended)

```bash
# Download and extract the latest release
curl -L https://github.com/YOUR_USERNAME/vm-toolkit/archive/refs/heads/main.tar.gz | tar -xz
cd vm-toolkit-main

# Install with defaults
./install.sh
```

### From Git Clone

```bash
git clone https://github.com/YOUR_USERNAME/vm-toolkit.git
cd vm-toolkit
./install.sh
```

## Custom Installation

### Installation Options

```bash
# Install to specific directory with custom data location
./install.sh --install-dir /opt/vm-toolkit --data-dir /var/vm-data

# Force overwrite existing installation
./install.sh --force

# See all options
./install.sh --help
```

### Installation Locations

| Component | Default Location | Configurable |
|-----------|------------------|--------------|
| Toolkit Code | Current directory | `--install-dir` |
| VM Data | `./vm-toolkit-data` | `--data-dir` |
| Configuration | `~/.vm-toolkit-config` | No |
| Command Link | `~/bin/vm` | No |

## What Gets Installed

### Directory Structure

After installation, your data directory will contain:

```
vm-toolkit-data/             # Data directory (in project root by default)
├── .cache/                  # Cloud image cache
├── .vm-registry.json        # VM registry database
└── vms/                     # Individual VM directories
    ├── vm1/                 # VM named "vm1"
    │   ├── vm1.qcow2        # VM disk image
    │   ├── vm1.pid          # Process ID file
    │   ├── vm1.mac          # MAC address
    │   └── cloud-init/      # Cloud-init configuration
    └── vm2/                 # VM named "vm2"
        └── ...
```

### Configuration File

The installer creates `~/.vm-toolkit-config` with your installation paths:

```bash
# Installation paths
VM_TOOLKIT_DIR="/path/to/vm-toolkit"
VM_PROJECT_DIR="/path/to/vm-data"

# Data locations
VM_BASE_DIR="$VM_PROJECT_DIR/vms"
CLOUD_IMAGE_CACHE="$VM_PROJECT_DIR/.cache"
REGISTRY_FILE="$VM_PROJECT_DIR/.vm-registry.json"

# User settings (customize as needed)
VM_USERNAME="your-username"
VM_SSH_KEY="$HOME/.ssh/id_ed25519.pub"
# ... more settings
```

## Advanced Installation Scenarios

### System-Wide Installation

```bash
# Install for all users (requires sudo)
sudo ./install.sh --install-dir /opt/vm-toolkit --data-dir /var/vm-data

# Each user needs their own config
cp /opt/vm-toolkit/vm-toolkit/examples/vm-toolkit-config.example ~/.vm-toolkit-config
# Edit ~/.vm-toolkit-config to point to shared data directory
```

### Data Directory Location

**New Default (v1.1+)**: VM data is stored in `./vm-toolkit-data` within the project directory by default. This provides:
- **Cleaner project structure**: All VM data contained within the project
- **Easier backup**: Single directory contains everything
- **Better portability**: Moving the project moves all data with it
- **Simpler organization**: Data stays with the toolkit

**Legacy installations** that used `~/vm-toolkit-data` continue to work via user configuration overrides.

### Portable Installation

```bash
# Install to a portable directory
./install.sh --install-dir /media/usb/vm-toolkit --data-dir /media/usb/vm-data

# Update PATH for this session
export PATH="/media/usb/vm-toolkit:$PATH"
```

### Multiple Installations

You can have multiple toolkit installations for different purposes:

```bash
# Development environment
./install.sh --data-dir ~/vm-dev

# Production environment  
./install.sh --data-dir ~/vm-prod --force

# Switch between them by editing ~/.vm-toolkit-config
```

## Upgrading

### From Archive/Release

```bash
# Download new version
curl -L https://github.com/YOUR_USERNAME/vm-toolkit/archive/refs/heads/main.tar.gz | tar -xz
cd vm-toolkit-main

# Upgrade (preserves existing config and data)
./install.sh --force
```

### From Git

```bash
cd /path/to/vm-toolkit
git pull
./install.sh --force
```

## Uninstalling

```bash
# Remove command symlink
rm ~/bin/vm

# Remove configuration (optional)
rm ~/.vm-toolkit-config

# Remove data directory (WARNING: deletes all VMs!)
rm -rf ./vm-toolkit-data  # or ~/vm-toolkit-data for older installations

# Remove toolkit code
rm -rf /path/to/vm-toolkit
```

## Troubleshooting

### Command Not Found

```bash
# Check if symlink exists
ls -la ~/bin/vm

# Check if ~/bin is in PATH
echo $PATH | grep "$HOME/bin"

# Add to PATH if missing
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

### Permission Issues

```bash
# Fix ownership of data directory
sudo chown -R $USER:$USER ./vm-toolkit-data

# Fix permissions
chmod -R 755 ./vm-toolkit-data
```

### Configuration Issues

```bash
# Regenerate configuration
./install.sh --force

# Check configuration
cat ~/.vm-toolkit-config

# Test configuration
vm help
```

## Migration from Old Installation

If you have an existing installation in `~/vmq`:

```bash
# Backup existing VMs
cp -r ~/vmq/vms ./vm-toolkit-data/

# Copy registry
cp ~/vmq/.vm-registry.json ./vm-toolkit-data/

# Copy cache
cp -r ~/vmq/.cache ./vm-toolkit-data/

# Update registry paths (if needed)
vm sync
```
