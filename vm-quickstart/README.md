# VM Quickstart Setup

A simple script to quickly set up a fresh Ubuntu VM with GitHub access and development tools.

## What it does

🚀 **Installs essential tools:**
- Git and GitHub CLI
- Development tools (vim, htop, build-essential)
- Common utilities (curl, wget, ca-certificates)

🔧 **Configures Git:**
- Sets up your username and email
- Configures sensible defaults

🔑 **Sets up GitHub authentication:**
- Authenticates with GitHub CLI
- Verifies the connection
- Optionally clones a repository

## Usage

### In a fresh VM:

```bash
# Download and run the setup script
curl -fsSL https://raw.githubusercontent.com/lewesmint/vm-toolkit/main/vm-quickstart/vm-setup.sh | bash
```

### Or if you have the repository:

```bash
cd vm-quickstart
./vm-setup.sh
```

## What you'll be prompted for:

1. **Git username** (e.g., "lewesmint")
2. **Git email** (e.g., "minty@keergill.co.uk")
3. **GitHub authentication** (browser-based)
4. **Optional repository to clone**

## After setup:

Your VM will be ready for development with:
- ✅ Git configured with your identity
- ✅ GitHub CLI authenticated
- ✅ Essential development tools installed
- ✅ Ready to clone and work on repositories

## Useful commands after setup:

```bash
gh repo list                    # List your repositories
gh repo clone <repo>           # Clone a repository
gh auth status                 # Check authentication status
gh auth refresh                # Refresh authentication
```

## Requirements:

- Fresh Ubuntu VM (20.04+ recommended)
- Internet connection
- Sudo access
