#!/bin/bash

# Upgrade script for DenoKV on Rocky Linux
# This script pulls the latest changes and rebuilds the project

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo "🔄 DenoKV Upgrade Script for Rocky Linux"
echo "=========================================="
echo ""

# Check if we're in the right directory
if [ ! -f "Cargo.toml" ] || [ ! -f "setup-rocky-linux.sh" ]; then
    print_error "This script must be run from the DenoKV project root directory"
    print_error "Make sure you're in the directory that contains Cargo.toml and setup-rocky-linux.sh"
    exit 1
fi

# Check if git is available
if ! command -v git &> /dev/null; then
    print_error "Git is not installed. Please run the setup script first:"
    print_error "  ./setup-rocky-linux.sh"
    exit 1
fi

# Check if cargo is available
if ! command -v cargo &> /dev/null; then
    print_error "Cargo is not installed. Please run the setup script first:"
    print_error "  ./setup-rocky-linux.sh"
    exit 1
fi

# Check current status
print_status "Checking current git status..."
git status --porcelain

# Check if there are uncommitted changes
if [ -n "$(git status --porcelain)" ]; then
    print_warning "You have uncommitted changes:"
    git status --short
    echo ""
    read -p "Do you want to stash these changes before upgrading? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_status "Stashing uncommitted changes..."
        git stash push -m "Auto-stash before upgrade $(date)"
        print_success "Changes stashed"
    else
        print_warning "Proceeding with uncommitted changes..."
    fi
fi

# Fetch latest changes
print_status "Fetching latest changes from remote..."
git fetch origin

# Check current branch
CURRENT_BRANCH=$(git branch --show-current)
print_status "Current branch: $CURRENT_BRANCH"

# Check if there are updates available
BEHIND=$(git rev-list --count HEAD..origin/$CURRENT_BRANCH 2>/dev/null || echo "0")
if [ "$BEHIND" -eq 0 ]; then
    print_success "You're already up to date!"
    print_status "No new commits to pull"
else
    print_status "Found $BEHIND new commit(s) to pull"
fi

# Pull latest changes
print_status "Pulling latest changes..."
if git pull origin $CURRENT_BRANCH; then
    print_success "Successfully pulled latest changes"
else
    print_error "Failed to pull changes. Please resolve conflicts manually."
    exit 1
fi

# Clean build artifacts
print_status "Cleaning previous build artifacts..."
cargo clean

# Source Rust environment
print_status "Sourcing Rust environment..."
source ~/.cargo/env

# Update dependencies
print_status "Updating dependencies..."
cargo update

# Build the project
print_status "Building DenoKV with latest changes..."
if cargo build --release; then
    print_success "Build completed successfully!"
else
    print_error "Build failed. Please check the error messages above."
    exit 1
fi

# Check if any scripts need to be updated
print_status "Checking for script updates..."

# Update script permissions
chmod +x setup-rocky-linux.sh 2>/dev/null || true
chmod +x start-denokv-server.sh 2>/dev/null || true
chmod +x test-postgres-integration.sh 2>/dev/null || true
chmod +x generate-access-token.sh 2>/dev/null || true

print_success "Script permissions updated"

# Show upgrade summary
echo ""
print_success "🎉 Upgrade completed successfully!"
echo ""
print_status "Summary:"
echo "  ✅ Latest changes pulled from remote"
echo "  ✅ Dependencies updated"
echo "  ✅ Project rebuilt successfully"
echo "  ✅ Script permissions updated"
echo ""

# Install the new binary
print_status "Installing new DenoKV binary..."
if [ -f "target/release/denokv" ]; then
    # Stop service first so we can overwrite the binary
    if systemctl list-unit-files | grep -q "denokv.service"; then
        if sudo systemctl is-active --quiet denokv.service; then
            print_status "Stopping DenoKV service to update binary..."
            sudo systemctl stop denokv.service
        fi
    fi
    
    # Copy the binary
    sudo cp target/release/denokv /usr/local/bin/denokv
    sudo chmod +x /usr/local/bin/denokv
    sudo chown root:root /usr/local/bin/denokv
    print_success "Binary installed to /usr/local/bin/denokv"
else
    print_error "Binary not found at target/release/denokv"
    exit 1
fi

# Check if systemd service exists and start it
if systemctl list-unit-files | grep -q "denokv.service"; then
    print_status "Starting DenoKV systemd service with new binary..."
    if sudo systemctl start denokv.service; then
        sleep 2
        if sudo systemctl is-active --quiet denokv.service; then
            print_success "DenoKV service restarted successfully!"
        else
            print_error "Service restarted but is not active. Check status:"
            echo "  sudo systemctl status denokv.service"
        fi
    else
        print_error "Failed to restart service"
        exit 1
    fi
else
    print_warning "Systemd service not found. Server may be running manually."
    if pgrep -f "denokv.*serve" > /dev/null; then
        print_status "DenoKV process found. You may want to restart it manually:"
        echo "  pkill -f 'denokv.*serve'  # Stop current server"
        echo "  ./start-denokv-server.sh   # Start with new version"
    fi
fi

echo ""
print_status "Available commands:"
echo "  sudo systemctl status denokv.service  - Check service status"
echo "  sudo journalctl -u denokv.service -f  - View service logs"
echo "  ./upgrade-denokv.sh                   - Run this upgrade script again"
echo ""


     1 │# Stop the service first
     2 │sudo systemctl stop denokv.service
     3 │
     4 │# Then copy the binary
     5 │sudo cp target/release/denokv /usr/local/bin/denokv
     6 │sudo chmod +x /usr/local/bin/denokv
     7 │sudo chown root:root /usr/local/bin/denokv
     8 │
     9 │# Start the service
    10 │sudo systemctl start denokv.service
    11 │
    12 │# Verify
    13 │sudo systemctl status denokv.service


      3 │cargo build --release
     4 │sudo systemctl stop denokv.service
     5 │sudo cp target/release/denokv /usr/local/bin/denokv
     6 │sudo chmod +x /usr/local/bin/denokv
     7 │sudo systemctl start denokv.service
     8 │sudo systemctl status denokv.service