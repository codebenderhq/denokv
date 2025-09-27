#!/bin/bash

# Setup script for Rocky Linux to test DenoKV PostgreSQL integration
# This script installs all necessary dependencies and sets up the environment

set -e

echo "🚀 Setting up Rocky Linux environment for DenoKV PostgreSQL testing..."

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

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   print_error "This script should not be run as root. Please run as a regular user."
   exit 1
fi

# Update system packages
print_status "Updating system packages..."
sudo dnf update -y

# Install essential development tools
print_status "Installing essential development tools..."
sudo dnf groupinstall -y "Development Tools"
sudo dnf install -y git curl wget vim nano

# Install PostgreSQL development libraries
print_status "Installing PostgreSQL development libraries..."
sudo dnf install -y postgresql-devel postgresql-server postgresql-contrib

# Install Docker
print_status "Installing Docker..."
if ! command -v docker &> /dev/null; then
    # Add Docker repository
    sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Start and enable Docker service
    sudo systemctl start docker
    sudo systemctl enable docker
    
    # Add current user to docker group
    sudo usermod -aG docker $USER
    
    print_success "Docker installed successfully"
else
    print_warning "Docker is already installed"
fi

# Install Docker Compose (standalone)
print_status "Installing Docker Compose..."
if ! command -v docker-compose &> /dev/null; then
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    print_success "Docker Compose installed successfully"
else
    print_warning "Docker Compose is already installed"
fi

# Install Rust
print_status "Installing Rust..."
if ! command -v cargo &> /dev/null; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source ~/.cargo/env
    print_success "Rust installed successfully"
else
    print_warning "Rust is already installed"
fi

# Install additional dependencies for Rust compilation
print_status "Installing additional dependencies for Rust compilation..."
sudo dnf install -y openssl-devel pkg-config

# Clone the repository
print_status "Cloning DenoKV repository..."
if [ ! -d "denokv" ]; then
    git clone https://github.com/codebenderhq/denokv.git
    cd denokv
    print_success "Repository cloned successfully"
else
    print_warning "Repository directory already exists"
    cd denokv
fi

# Build the project
print_status "Building the project..."
source ~/.cargo/env
cargo build --release

print_success "Build completed successfully"

# Create a test script
print_status "Creating test script..."
cat > test-postgres-integration.sh << 'EOF'
#!/bin/bash

# Test script for PostgreSQL integration on Rocky Linux

set -e

echo "🧪 Testing PostgreSQL integration..."

# Start PostgreSQL container
echo "Starting PostgreSQL container..."
docker-compose -f docker-compose.test.yml up -d postgres

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to be ready..."
until docker-compose -f docker-compose.test.yml exec postgres pg_isready -U postgres; do
  echo "PostgreSQL is not ready yet..."
  sleep 2
done

echo "PostgreSQL is ready!"

# Set environment variables for tests
export POSTGRES_URL="postgresql://postgres:password@localhost:5432/denokv_test"
export DENO_KV_ACCESS_TOKEN="1234abcd5678efgh"  # Test access token (minimum 12 chars)

# Run the tests
echo "Running PostgreSQL tests..."
source ~/.cargo/env
cargo test --package denokv_postgres test_postgres

# Clean up
echo "Cleaning up..."
docker-compose -f docker-compose.test.yml down

echo "✅ Tests completed successfully!"
EOF

# Create a production server startup script
print_status "Creating production server script..."
cat > start-denokv-server.sh << 'EOF'
#!/bin/bash

# Production DenoKV server startup script for Rocky Linux

set -e

echo "🚀 Starting DenoKV server..."

# Check if access token is provided
if [ -z "$DENO_KV_ACCESS_TOKEN" ]; then
    echo "❌ Error: DENO_KV_ACCESS_TOKEN environment variable is required"
    echo "   Set it with: export DENO_KV_ACCESS_TOKEN='your-secure-token-here'"
    echo "   Token must be at least 12 characters long"
    exit 1
fi

# Check if PostgreSQL URL is provided
if [ -z "$DENO_KV_POSTGRES_URL" ]; then
    echo "❌ Error: DENO_KV_POSTGRES_URL environment variable is required"
    echo "   Set it with: export DENO_KV_POSTGRES_URL='postgresql://user:pass@host:port/db'"
    exit 1
fi

# Set default values
export DENO_KV_DATABASE_TYPE=${DENO_KV_DATABASE_TYPE:-"postgres"}
export DENO_KV_NUM_WORKERS=${DENO_KV_NUM_WORKERS:-"4"}

echo "Configuration:"
echo "  Database Type: $DENO_KV_DATABASE_TYPE"
echo "  PostgreSQL URL: $DENO_KV_POSTGRES_URL"
echo "  Access Token: ${DENO_KV_ACCESS_TOKEN:0:8}..." # Show only first 8 chars
echo "  Workers: $DENO_KV_NUM_WORKERS"
echo ""

# Start the server
source ~/.cargo/env
cargo run --release -- serve --addr 0.0.0.0:4512
EOF

chmod +x start-denokv-server.sh

chmod +x test-postgres-integration.sh

print_success "Test script created successfully"

# Create a README for the setup
print_status "Creating setup README..."
cat > ROCKY_LINUX_SETUP.md << 'EOF'
# Rocky Linux Setup for DenoKV PostgreSQL Testing

This document describes how to set up a Rocky Linux environment for testing DenoKV PostgreSQL integration.

## Prerequisites

- Rocky Linux 8 or 9
- Internet connection
- Non-root user with sudo privileges

## Quick Setup

Run the setup script:

```bash
chmod +x setup-rocky-linux.sh
./setup-rocky-linux.sh
```

## What the Setup Script Does

1. **Updates system packages** - Ensures all packages are up to date
2. **Installs development tools** - Installs essential development packages
3. **Installs PostgreSQL development libraries** - Required for PostgreSQL backend compilation
4. **Installs Docker and Docker Compose** - For running PostgreSQL test container
5. **Installs Rust** - Required for building the project
6. **Installs additional dependencies** - OpenSSL and pkg-config for Rust compilation
7. **Clones the repository** - Downloads the DenoKV source code
8. **Builds the project** - Compiles all components
9. **Creates test script** - Generates a script to run PostgreSQL integration tests

## Running Tests

After setup, you can run the PostgreSQL integration tests:

```bash
./test-postgres-integration.sh
```

## Manual Steps After Setup

1. **Log out and log back in** - This ensures Docker group membership takes effect
2. **Verify Docker access** - Run `docker ps` to confirm Docker is accessible
3. **Run tests** - Execute the test script to verify everything works

## Troubleshooting

### Docker Permission Issues
If you get permission denied errors with Docker:
```bash
sudo usermod -aG docker $USER
# Then log out and log back in
```

### Rust Not Found
If Rust commands are not found:
```bash
source ~/.cargo/env
```

### PostgreSQL Connection Issues
Make sure the PostgreSQL container is running:
```bash
docker-compose -f docker-compose.test.yml ps
```

## Project Structure

- `denokv/` - Main DenoKV project
- `postgres/` - PostgreSQL backend implementation
- `docker-compose.test.yml` - PostgreSQL test container configuration
- `test-postgres.sh` - Original test script
- `test-postgres-integration.sh` - Enhanced test script for Rocky Linux

## Environment Variables

The test script sets the following environment variable:
- `POSTGRES_URL=postgresql://postgres:password@localhost:5432/denokv_test`

## Cleanup

To stop and remove the PostgreSQL test container:
```bash
docker-compose -f docker-compose.test.yml down
```
EOF

print_success "Setup README created successfully"

echo ""
print_success "🎉 Setup completed successfully!"
echo ""
print_status "Next steps:"
echo "1. Log out and log back in to ensure Docker group membership takes effect"
echo "2. Run: docker ps (to verify Docker access)"
echo "3. Run: ./test-postgres-integration.sh (to test PostgreSQL integration)"
echo ""
print_status "For production server:"
echo "1. Set DENO_KV_ACCESS_TOKEN environment variable (minimum 12 characters)"
echo "2. Set DENO_KV_POSTGRES_URL environment variable"
echo "3. Run: ./start-denokv-server.sh"
echo ""
print_status "Setup documentation is available in ROCKY_LINUX_SETUP.md"
echo ""
print_warning "Note: You may need to restart your terminal or run 'source ~/.cargo/env' to use Rust commands"
print_warning "Security: Generate a strong access token for production use!"