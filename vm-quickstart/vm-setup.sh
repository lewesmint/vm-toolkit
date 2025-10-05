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
    ca-certificates \
    gnupg

sudo snap install task --classic

# Setup Task alias and completion in .bashrc
echo ""
log_info "Setting up Task alias and completion..."
cat >> ~/.bashrc << 'EOF'

# Task alias and completion
function t() {
    task "$@"
}

# Setup Task completion for both 'task' and 't'
if command -v task &> /dev/null; then
    eval "$(task --completion bash)"
    complete -F _task t
fi
EOF

log_success "Task alias and completion added to .bashrc"

# Install GitHub CLI
log_info "Installing GitHub CLI..."
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt update
sudo apt install -y gh

log_success "GitHub CLI and development tools installed"

# Authenticate with GitHub
echo ""
log_info "Setting up GitHub authentication..."
echo "🔑 This will open a browser for GitHub authentication"
echo "💡 Choose 'HTTPS' for Git operations when prompted"
echo ""
read -p "Press Enter to continue..."

gh auth login

# Verify authentication and configure Git
echo ""
log_info "Verifying GitHub authentication..."
if gh auth status > /dev/null 2>&1; then
    log_success "GitHub authentication successful!"

    # Get user info from GitHub API
    log_info "Retrieving user information from GitHub..."
    github_username=$(gh api user --jq .login)
    github_email=$(gh api user --jq .email)

    # If email is null/private, try to get a public email
    if [ "$github_email" = "null" ] || [ -z "$github_email" ]; then
        log_info "Primary email is private, checking for public emails..."
        github_email=$(gh api user/emails --jq '.[] | select(.primary == true) | .email' 2>/dev/null)

        # If still no email, ask user
        if [ "$github_email" = "null" ] || [ -z "$github_email" ]; then
            echo "⚠️  No public email found in your GitHub profile"
            read -p "Please enter your Git email: " github_email
        fi
    fi

    echo "   Logged in as: $github_username"
    echo "   Email: $github_email"

    # Configure Git with GitHub info
    log_info "Configuring Git with GitHub information..."
    git config --global user.name "$github_username"
    git config --global user.email "$github_email"
    git config --global init.defaultBranch main
    git config --global pull.rebase false

    log_success "Git configured with GitHub credentials"
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
echo "   ✅ Essential development tools"
echo "   ✅ Task (Taskfile.yml task runner)"
echo "   ✅ GitHub CLI (with git as dependency)"
echo "   ✅ GitHub authentication"
echo "   ✅ Task alias and completion (restart shell or run 'source ~/.bashrc')"
echo ""
echo "🚀 You're ready to start developing!"
echo ""
echo "💡 Useful commands:"
echo "   gh repo list                    # List your repositories"
echo "   gh repo clone <repo>           # Clone a repository"
echo "   gh auth status                 # Check authentication status"
echo "   gh auth refresh                # Refresh authentication"
echo "   task --list                     # List available tasks"
echo "   t --list                        # Same as above (alias)"