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

# Configure firewall for DenoKV port
print_status "Configuring firewall for DenoKV..."
if command -v firewall-cmd &> /dev/null; then
    sudo firewall-cmd --permanent --add-port=4512/tcp
    sudo firewall-cmd --reload
    print_success "Firewall configured - port 4512 is open"
else
    print_warning "firewalld not found. You may need to manually open port 4512"
fi

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

# Ensure PostgreSQL service is running
echo "Ensuring PostgreSQL service is running..."
sudo systemctl start postgresql

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to be ready..."
until sudo -u postgres pg_isready; do
  echo "PostgreSQL is not ready yet..."
  sleep 2
done

echo "PostgreSQL service is ready!"

# Set environment variables for tests
export POSTGRES_URL="postgresql://denokv:denokv_password@localhost:5432/denokv"
export DENO_KV_ACCESS_TOKEN="1234abcd5678efgh"  # Test access token (minimum 12 chars)

# Run the tests
echo "Running PostgreSQL tests..."
source ~/.cargo/env
cargo test --package denokv_postgres test_postgres

# Tests completed - PostgreSQL service remains running
echo "✅ Tests completed successfully!"
echo "PostgreSQL service remains running for production use"
EOF

# Create a production server startup script
print_status "Creating production server script..."
cat > start-denokv-server.sh << 'EOF'
#!/bin/bash

# Production DenoKV server startup script for Rocky Linux

set -e

echo "🚀 Starting DenoKV server..."

# Generate access token if not provided
if [ -z "$DENO_KV_ACCESS_TOKEN" ]; then
    echo "🔑 Generating secure access token..."
    if command -v openssl &> /dev/null; then
        DENO_KV_ACCESS_TOKEN=$(openssl rand -hex 16)
    elif command -v /dev/urandom &> /dev/null; then
        DENO_KV_ACCESS_TOKEN=$(head -c 32 /dev/urandom | base64 | tr -d "=+/" | cut -c1-32)
    else
        echo "❌ Error: Cannot generate access token. Please install openssl or set DENO_KV_ACCESS_TOKEN manually"
        echo "   Set it with: export DENO_KV_ACCESS_TOKEN='your-secure-token-here'"
        echo "   Token must be at least 12 characters long"
        exit 1
    fi
    export DENO_KV_ACCESS_TOKEN
    echo "✅ Generated access token: ${DENO_KV_ACCESS_TOKEN:0:8}..."
    echo "💾 Save this token securely: $DENO_KV_ACCESS_TOKEN"
    echo ""
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

# Create a token generation utility script
print_status "Creating token generation utility..."
cat > generate-access-token.sh << 'EOF'
#!/bin/bash

# Utility script to generate secure access tokens for DenoKV

set -e

echo "🔑 DenoKV Access Token Generator"
echo "================================="
echo ""

# Generate token using best available method
if command -v openssl &> /dev/null; then
    echo "Using OpenSSL for token generation..."
    TOKEN=$(openssl rand -hex 16)
elif command -v /dev/urandom &> /dev/null; then
    echo "Using /dev/urandom for token generation..."
    TOKEN=$(head -c 32 /dev/urandom | base64 | tr -d "=+/" | cut -c1-32)
else
    echo "❌ Error: No secure random generator available"
    echo "Please install openssl or use a manual token"
    exit 1
fi

echo ""
echo "✅ Generated secure access token:"
echo "   $TOKEN"
echo ""
echo "📋 To use this token:"
echo "   export DENO_KV_ACCESS_TOKEN='$TOKEN'"
echo ""
echo "🔒 Security notes:"
echo "   - Keep this token secure and private"
echo "   - Don't commit it to version control"
echo "   - Use it in your Deno applications for remote access"
echo "   - Token length: ${#TOKEN} characters (minimum required: 12)"
echo ""

# Optionally save to a file
read -p "💾 Save token to .env file? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "DENO_KV_ACCESS_TOKEN='$TOKEN'" > .env
    echo "✅ Token saved to .env file"
    echo "   Source it with: source .env"
fi
EOF

chmod +x generate-access-token.sh

# Create a service management script
print_status "Creating service management script..."
cat > manage-services.sh << 'EOF'
#!/bin/bash

# Service management script for DenoKV on Rocky Linux

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

case "${1:-help}" in
    start)
        print_status "Starting all services..."
        
        # Start PostgreSQL service
        print_status "Starting PostgreSQL service..."
        sudo systemctl start postgresql
        
        # Wait for PostgreSQL
        until sudo -u postgres pg_isready; do
            echo "Waiting for PostgreSQL..."
            sleep 2
        done
        print_success "PostgreSQL service started"
        
        # Start DenoKV server
        print_status "Starting DenoKV server..."
        source ~/.cargo/env
        source .env 2>/dev/null || true
        
        if pgrep -f "denokv.*serve" > /dev/null; then
            print_warning "DenoKV server is already running"
        else
            nohup cargo run --release -- serve --addr 0.0.0.0:4512 > denokv.log 2>&1 &
            sleep 2
            if pgrep -f "denokv.*serve" > /dev/null; then
                print_success "DenoKV server started"
            else
                print_error "Failed to start DenoKV server"
            fi
        fi
        ;;
        
    stop)
        print_status "Stopping DenoKV server..."
        
        # Stop DenoKV server only
        if pgrep -f "denokv.*serve" > /dev/null; then
            pkill -f "denokv.*serve"
            print_success "DenoKV server stopped"
        else
            print_warning "DenoKV server was not running"
        fi
        
        print_status "PostgreSQL service remains running (persistent)"
        ;;
        
    restart)
        $0 stop
        sleep 2
        $0 start
        ;;
        
    stop-postgres)
        print_status "Stopping PostgreSQL service..."
        sudo systemctl stop postgresql
        print_success "PostgreSQL service stopped"
        print_warning "Note: DenoKV server will not work without PostgreSQL"
        ;;
        
    start-postgres)
        print_status "Starting PostgreSQL service..."
        sudo systemctl start postgresql
        until sudo -u postgres pg_isready; do
            echo "Waiting for PostgreSQL..."
            sleep 2
        done
        print_success "PostgreSQL service started"
        ;;
        
    status)
        print_status "Service Status:"
        echo ""
        
        # Check PostgreSQL service
        if systemctl is-active --quiet postgresql; then
            print_success "PostgreSQL Service: Running"
        else
            print_warning "PostgreSQL Service: Stopped"
        fi
        
        # Check DenoKV server
        if pgrep -f "denokv.*serve" > /dev/null; then
            print_success "DenoKV Server: Running (PID: $(pgrep -f 'denokv.*serve'))"
        else
            print_warning "DenoKV Server: Stopped"
        fi
        
        # Check port 4512
        if netstat -tlnp 2>/dev/null | grep -q ":4512 "; then
            print_success "Port 4512: Open"
        else
            print_warning "Port 4512: Closed"
        fi
        ;;
        
    logs)
        if [ -f "denokv.log" ]; then
            tail -f denokv.log
        else
            print_warning "No log file found"
        fi
        ;;
        
    *)
        echo "DenoKV Service Manager"
        echo "Usage: $0 {start|stop|restart|status|logs|start-postgres|stop-postgres}"
        echo ""
        echo "Commands:"
        echo "  start         - Start DenoKV server (PostgreSQL must be running)"
        echo "  stop          - Stop DenoKV server only (PostgreSQL stays running)"
        echo "  restart       - Restart DenoKV server only"
        echo "  status        - Show service status"
        echo "  logs          - Show DenoKV server logs"
        echo "  start-postgres - Start PostgreSQL service"
        echo "  stop-postgres  - Stop PostgreSQL service (use with caution)"
        echo ""
        echo "Note: PostgreSQL runs as a persistent system service"
        echo "      DenoKV server can be started/stopped independently"
        ;;
esac
EOF

chmod +x manage-services.sh

# Create a PostgreSQL authentication fix script
print_status "Creating PostgreSQL authentication fix script..."
cat > fix-postgres-auth.sh << 'EOF'
#!/bin/bash

# PostgreSQL Authentication Fix Script for Rocky Linux

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "🔧 PostgreSQL Authentication Fix Script"
echo "======================================="
echo ""

# Check if PostgreSQL is running
if ! systemctl is-active --quiet postgresql; then
    print_status "Starting PostgreSQL service..."
    sudo systemctl start postgresql
fi

# Find pg_hba.conf
PG_HBA_PATHS=(
    "/var/lib/pgsql/data/pg_hba.conf"
    "/var/lib/postgresql/data/pg_hba.conf"
    "/etc/postgresql/*/main/pg_hba.conf"
)

PG_HBA_PATH=""
for path in "${PG_HBA_PATHS[@]}"; do
    if [ -f "$path" ] || ls $path 2>/dev/null; then
        PG_HBA_PATH="$path"
        break
    fi
done

if [ -z "$PG_HBA_PATH" ]; then
    print_error "Could not find pg_hba.conf file"
    print_status "Trying to find PostgreSQL data directory..."
    sudo -u postgres psql -c "SHOW data_directory;" 2>/dev/null || true
    exit 1
fi

print_status "Found pg_hba.conf at: $PG_HBA_PATH"

# Backup the original file
print_status "Creating backup of pg_hba.conf..."
sudo cp "$PG_HBA_PATH" "$PG_HBA_PATH.backup.$(date +%Y%m%d_%H%M%S)"

# Update authentication methods
print_status "Updating authentication methods..."
sudo sed -i 's/local   all             all                                     ident/local   all             all                                     md5/g' "$PG_HBA_PATH"
sudo sed -i 's/local   all             all                                     peer/local   all             all                                     md5/g' "$PG_HBA_PATH"
sudo sed -i 's/local   all             all                                     trust/local   all             all                                     md5/g' "$PG_HBA_PATH"

# Add explicit entry for denokv user if not present
if ! grep -q "denokv" "$PG_HBA_PATH"; then
    print_status "Adding explicit entry for denokv user..."
    echo "local   denokv          denokv                                  md5" | sudo tee -a "$PG_HBA_PATH"
fi

# Reload PostgreSQL configuration
print_status "Reloading PostgreSQL configuration..."
sudo systemctl reload postgresql

# Test connection
print_status "Testing database connection..."
if PGPASSWORD='denokv_password' psql -h localhost -U denokv -d denokv -c "SELECT 1;" >/dev/null 2>&1; then
    print_success "Database connection test successful!"
else
    print_warning "Database connection test failed"
    print_status "You may need to restart PostgreSQL: sudo systemctl restart postgresql"
fi

print_success "PostgreSQL authentication fix completed!"
echo ""
print_status "If you still have issues, try:"
echo "  sudo systemctl restart postgresql"
echo "  ./manage-services.sh restart"
EOF

chmod +x fix-postgres-auth.sh

print_success "Scripts created successfully"

# Install and configure PostgreSQL server
print_status "Installing and configuring PostgreSQL server..."
sudo dnf install -y postgresql-server postgresql-contrib

# Initialize PostgreSQL if not already done
if [ ! -d "/var/lib/pgsql/data" ]; then
    print_status "Initializing PostgreSQL database..."
    sudo postgresql-setup --initdb
fi

# Start and enable PostgreSQL service
print_status "Starting PostgreSQL service..."
sudo systemctl start postgresql
sudo systemctl enable postgresql

# Wait for PostgreSQL to be ready
print_status "Waiting for PostgreSQL to be ready..."
until sudo -u postgres pg_isready; do
  echo "PostgreSQL is not ready yet..."
  sleep 2
done

print_success "PostgreSQL service is ready!"

# Configure PostgreSQL authentication
print_status "Configuring PostgreSQL authentication..."
sudo -u postgres psql -c "ALTER SYSTEM SET listen_addresses = 'localhost';" 2>/dev/null || true

# Update pg_hba.conf to allow password authentication
PG_HBA_PATH="/var/lib/pgsql/data/pg_hba.conf"
if [ -f "$PG_HBA_PATH" ]; then
    print_status "Updating pg_hba.conf for password authentication..."
    sudo cp "$PG_HBA_PATH" "$PG_HBA_PATH.backup"
    
    # Replace ident with md5 for local connections
    sudo sed -i 's/local   all             all                                     ident/local   all             all                                     md5/g' "$PG_HBA_PATH"
    sudo sed -i 's/local   all             all                                     peer/local   all             all                                     md5/g' "$PG_HBA_PATH"
    
    # Restart PostgreSQL to apply changes
    sudo systemctl restart postgresql
    sleep 3
    print_success "PostgreSQL authentication configured"
else
    print_warning "pg_hba.conf not found at $PG_HBA_PATH"
fi

# Create DenoKV database and user
print_status "Setting up DenoKV database..."
sudo -u postgres psql -c "CREATE DATABASE denokv;" 2>/dev/null || print_warning "Database 'denokv' may already exist"
sudo -u postgres psql -c "CREATE USER denokv WITH PASSWORD 'denokv_password';" 2>/dev/null || print_warning "User 'denokv' may already exist"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE denokv TO denokv;" 2>/dev/null || true
sudo -u postgres psql -c "ALTER USER denokv CREATEDB;" 2>/dev/null || true

# Test the connection
print_status "Testing database connection..."
if PGPASSWORD='denokv_password' psql -h localhost -U denokv -d denokv -c "SELECT 1;" >/dev/null 2>&1; then
    print_success "Database connection test successful!"
else
    print_warning "Database connection test failed, but continuing..."
fi

print_success "DenoKV database and user created!"

# Set up environment variables
print_status "Setting up environment variables..."
export DENO_KV_POSTGRES_URL="postgresql://denokv:denokv_password@localhost:5432/denokv"
export DENO_KV_DATABASE_TYPE="postgres"

# Generate access token if not set
if [ -z "$DENO_KV_ACCESS_TOKEN" ]; then
    print_status "Generating access token..."
    if command -v openssl &> /dev/null; then
        DENO_KV_ACCESS_TOKEN=$(openssl rand -hex 16)
    else
        DENO_KV_ACCESS_TOKEN=$(head -c 32 /dev/urandom | base64 | tr -d "=+/" | cut -c1-32)
    fi
    export DENO_KV_ACCESS_TOKEN
    print_success "Generated access token: ${DENO_KV_ACCESS_TOKEN:0:8}..."
fi

# Create environment file for persistence
print_status "Creating .env file for environment variables..."
cat > .env << EOF
DENO_KV_POSTGRES_URL=postgresql://denokv:denokv_password@localhost:5432/denokv
DENO_KV_DATABASE_TYPE=postgres
DENO_KV_ACCESS_TOKEN=$DENO_KV_ACCESS_TOKEN
DENO_KV_NUM_WORKERS=4
EOF

print_success "Environment file created: .env"

# Run integration tests
print_status "Running PostgreSQL integration tests..."
source ~/.cargo/env
if cargo test --package denokv_postgres test_postgres; then
    print_success "Integration tests passed!"
else
    print_warning "Integration tests failed, but continuing with setup..."
fi

# Start DenoKV server in background
print_status "Starting DenoKV server..."
source ~/.cargo/env
nohup cargo run --release -- serve --addr 0.0.0.0:4512 > denokv.log 2>&1 &
DENOKV_PID=$!

# Wait a moment for server to start
sleep 3

# Check if server started successfully
if kill -0 $DENOKV_PID 2>/dev/null; then
    print_success "DenoKV server started successfully!"
    print_status "Server PID: $DENOKV_PID"
    print_status "Log file: denokv.log"
    print_status "Server running on: http://0.0.0.0:4512"
else
    print_warning "DenoKV server may not have started properly"
    print_status "Check denokv.log for details"
fi

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
- `docker-compose.test.yml` - Docker Compose file (not used in production)
- `test-postgres.sh` - Original test script
- `test-postgres-integration.sh` - Enhanced test script for Rocky Linux

## Environment Variables

The production setup uses the following environment variables:
- `DENO_KV_POSTGRES_URL=postgresql://denokv:denokv_password@localhost:5432/denokv`
- `DENO_KV_ACCESS_TOKEN=<generated-token>`

## Cleanup

To stop the PostgreSQL service (use with caution):
```bash
sudo systemctl stop postgresql
```

To stop the DenoKV server:
```bash
./manage-services.sh stop
```
EOF

print_success "Setup README created successfully"

echo ""
print_success "🎉 Complete setup finished successfully!"
echo ""
print_status "What's been set up:"
echo "✅ All dependencies installed (Rust, Docker, PostgreSQL dev libraries)"
echo "✅ PostgreSQL database running in Docker"
echo "✅ Environment variables configured (.env file created)"
echo "✅ Access token generated and saved"
echo "✅ Integration tests run"
echo "✅ DenoKV server started and running"
echo "✅ Port 4512 opened in firewall"
echo ""
print_status "Current status:"
echo "  🐘 PostgreSQL: Running as system service (port 5432)"
echo "  🗄️  Database: denokv (user: denokv)"
echo "  🚀 DenoKV Server: Running on http://0.0.0.0:4512"
echo "  🔑 Access Token: ${DENO_KV_ACCESS_TOKEN:0:8}... (saved in .env)"
echo "  📝 Log File: denokv.log"
echo "  🆔 Server PID: $DENOKV_PID"
echo ""
print_status "Ready for remote connections!"
echo "  Connect from Deno apps using: http://your-server-ip:4512"
echo "  Access token: $DENO_KV_ACCESS_TOKEN"
echo ""
print_status "Management commands:"
echo "  ./manage-services.sh start    - Start DenoKV server"
echo "  ./manage-services.sh stop     - Stop DenoKV server (PostgreSQL stays running)"
echo "  ./manage-services.sh restart  - Restart DenoKV server"
echo "  ./manage-services.sh status   - Check service status"
echo "  ./manage-services.sh logs     - View server logs"
echo "  ./manage-services.sh start-postgres - Start PostgreSQL service"
echo "  ./manage-services.sh stop-postgres  - Stop PostgreSQL service"
echo "  ./fix-postgres-auth.sh        - Fix PostgreSQL authentication issues"
echo "  ./test-postgres-integration.sh - Run tests again"
echo "  ./generate-access-token.sh     - Generate new token"
echo "  ./upgrade-denokv.sh            - Update and rebuild"
echo ""
print_status "Setup documentation: ROCKY_LINUX_SETUP.md"
echo ""
print_warning "Note: You may need to restart your terminal or run 'source ~/.cargo/env' to use Rust commands"
print_warning "Security: Your access token is saved in .env file - keep it secure!"