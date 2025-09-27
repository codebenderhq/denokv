#!/bin/bash

# Setup script for existing PostgreSQL installations

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

echo "🔧 DenoKV Setup for Existing PostgreSQL"
echo "========================================"
echo ""

# Check if PostgreSQL is running
if ! systemctl is-active --quiet postgresql; then
    print_status "Starting PostgreSQL service..."
    sudo systemctl start postgresql
    sleep 3
fi

# Wait for PostgreSQL to be ready
print_status "Waiting for PostgreSQL to be ready..."
until sudo -u postgres pg_isready; do
    echo "PostgreSQL is not ready yet..."
    sleep 2
done

print_success "PostgreSQL service is ready!"

# Configure PostgreSQL authentication
print_status "Configuring PostgreSQL authentication..."

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

# Create DenoKV database and user
print_status "Setting up DenoKV database..."

# Try to connect without password first (peer auth)
if sudo -u postgres psql -c "SELECT 1;" >/dev/null 2>&1; then
    print_status "Using peer authentication for postgres user"
    sudo -u postgres psql -c "CREATE DATABASE denokv;" 2>/dev/null || print_warning "Database 'denokv' may already exist"
    sudo -u postgres psql -c "CREATE USER denokv WITH PASSWORD 'denokv_password';" 2>/dev/null || print_warning "User 'denokv' may already exist"
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE denokv TO denokv;" 2>/dev/null || true
    sudo -u postgres psql -c "ALTER USER denokv CREATEDB;" 2>/dev/null || true
else
    print_warning "PostgreSQL requires password authentication"
    print_status "You may need to set a password for the postgres user first"
    print_status "Run: sudo -u postgres psql -c \"ALTER USER postgres PASSWORD 'your_password';\""
    print_status "Or use: sudo passwd postgres (to set system password)"
    
    # Try to create database with empty password
    print_status "Attempting to create database with empty password..."
    PGPASSWORD="" sudo -u postgres psql -c "CREATE DATABASE denokv;" 2>/dev/null || print_warning "Database 'denokv' may already exist"
    PGPASSWORD="" sudo -u postgres psql -c "CREATE USER denokv WITH PASSWORD 'denokv_password';" 2>/dev/null || print_warning "User 'denokv' may already exist"
    PGPASSWORD="" sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE denokv TO denokv;" 2>/dev/null || true
    PGPASSWORD="" sudo -u postgres psql -c "ALTER USER denokv CREATEDB;" 2>/dev/null || true
fi

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

# Start DenoKV server in background
print_status "Starting DenoKV server..."

# Source Rust environment for the current user
if [ -f "$HOME/.cargo/env" ]; then
    source "$HOME/.cargo/env"
elif [ -f "/home/rawkakani/.cargo/env" ]; then
    source "/home/rawkakani/.cargo/env"
else
    print_warning "Rust environment not found, trying to find cargo..."
    if ! command -v cargo &> /dev/null; then
        print_error "Cargo not found. Please install Rust first."
        exit 1
    fi
fi

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

echo ""
print_success "🎉 DenoKV setup completed successfully!"
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
echo "  ./fix-postgres-auth.sh        - Fix PostgreSQL authentication issues"
echo "  ./test-postgres-connection.sh - Test database connection"
echo ""
print_warning "Security: Your access token is saved in .env file - keep it secure!"