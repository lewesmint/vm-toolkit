#!/bin/bash
set -e

# VM Quickstart Setup Script
# Sets up GitHub CLI, authentication, and common development tools

echo "🚀 VM Quickstart Setup"
echo "======================"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    echo "❌ Please don't run this script as root"
    echo "   Run as regular user - script will prompt for sudo when needed"
    exit 1
fi

# Update packages and install essential tools
log_info "Updating package lists..."
sudo apt update

log_info "Installing essential tools..."
sudo apt install -y \
    curl \
    git \
    ca-certificates \
    gnupg

# Optional: Ask user if they want development tools
echo ""
read -p "Install development tools (vim, htop, build-essential)? [y/N]: " install_dev_tools
if [[ "$install_dev_tools" =~ ^[Yy]$ ]]; then
    log_info "Installing development tools..."
    sudo apt install -y vim htop build-essential
    log_success "Development tools installed"
fi

# Install GitHub CLI
log_info "Installing GitHub CLI..."
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt update
sudo apt install -y gh

log_success "GitHub CLI and development tools installed"

# Configure Git (get user info first)
echo ""
log_info "Configuring Git..."
echo "Please enter your Git configuration:"
read -p "Git username: " git_username
read -p "Git email: " git_email

git config --global user.name "$git_username"
git config --global user.email "$git_email"
git config --global init.defaultBranch main
git config --global pull.rebase false

log_success "Git configured"

# Authenticate with GitHub
echo ""
log_info "Setting up GitHub authentication..."
echo "🔑 This will open a browser for GitHub authentication"
echo "💡 Choose 'HTTPS' for Git operations when prompted"
echo ""
read -p "Press Enter to continue..."

gh auth login

# Verify authentication
echo ""
log_info "Verifying GitHub authentication..."
if gh auth status > /dev/null 2>&1; then
    log_success "GitHub authentication successful!"
    echo "   Logged in as: $(gh api user --jq .login)"
else
    echo "❌ GitHub authentication failed"
    exit 1
fi

# Optional: Clone a repository
echo ""
echo "🔄 Would you like to clone a repository now?"
read -p "Repository (e.g., username/repo-name) or press Enter to skip: " repo_name

if [ -n "$repo_name" ]; then
    log_info "Cloning repository: $repo_name"
    gh repo clone "$repo_name"
    log_success "Repository cloned successfully"
fi

echo ""
log_success "🎉 VM setup complete!"
echo ""
echo "📋 What was installed:"
echo "   ✅ Essential development tools (git, vim, htop, build-essential)"
echo "   ✅ GitHub CLI"
echo "   ✅ Git configuration"
echo "   ✅ GitHub authentication"
echo ""
echo "🚀 You're ready to start developing!"
echo ""
echo "💡 Useful commands:"
echo "   gh repo list                    # List your repositories"
echo "   gh repo clone <repo>           # Clone a repository"
echo "   gh auth status                 # Check authentication status"
echo "   gh auth refresh                # Refresh authentication"