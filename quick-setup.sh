#!/bin/bash

# Quick setup script for DenoKV with PostgreSQL

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

echo "🚀 Quick DenoKV Setup"
echo "===================="
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

# Create DenoKV database and user using peer authentication
print_status "Creating DenoKV database and user..."

# Create database
sudo -u postgres psql -c "CREATE DATABASE denokv;" 2>/dev/null || print_warning "Database 'denokv' may already exist"

# Create user
sudo -u postgres psql -c "CREATE USER denokv WITH PASSWORD 'denokv_password';" 2>/dev/null || print_warning "User 'denokv' may already exist"

# Grant privileges
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE denokv TO denokv;" 2>/dev/null || true
sudo -u postgres psql -c "ALTER USER denokv CREATEDB;" 2>/dev/null || true

print_success "Database and user created!"

# Test connection
print_status "Testing database connection..."
if PGPASSWORD='denokv_password' psql -h localhost -U denokv -d denokv -c "SELECT 1;" >/dev/null 2>&1; then
    print_success "Database connection test successful!"
else
    print_warning "Database connection test failed - may need authentication fix"
    print_status "Run: ./fix-postgres-auth.sh"
fi

# Set up environment variables
print_status "Setting up environment variables..."
export DENO_KV_POSTGRES_URL="postgresql://denokv:denokv_password@localhost:5432/denokv"
export DENO_KV_DATABASE_TYPE="postgres"

# Generate access token
print_status "Generating access token..."
if command -v openssl &> /dev/null; then
    DENO_KV_ACCESS_TOKEN=$(openssl rand -hex 16)
else
    DENO_KV_ACCESS_TOKEN=$(head -c 32 /dev/urandom | base64 | tr -d "=+/" | cut -c1-32)
fi
export DENO_KV_ACCESS_TOKEN

print_success "Generated access token: ${DENO_KV_ACCESS_TOKEN:0:8}..."

# Create environment file
print_status "Creating .env file..."
cat > .env << EOF
DENO_KV_POSTGRES_URL=postgresql://denokv:denokv_password@localhost:5432/denokv
DENO_KV_DATABASE_TYPE=postgres
DENO_KV_ACCESS_TOKEN=$DENO_KV_ACCESS_TOKEN
DENO_KV_NUM_WORKERS=4
EOF

print_success "Environment file created: .env"

# Start DenoKV server
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

# Wait for server to start
sleep 3

# Check if server started
if kill -0 $DENOKV_PID 2>/dev/null; then
    print_success "DenoKV server started successfully!"
    print_status "Server PID: $DENOKV_PID"
    print_status "Server running on: http://0.0.0.0:4512"
    print_status "Access token: $DENO_KV_ACCESS_TOKEN"
else
    print_warning "DenoKV server may not have started properly"
    print_status "Check denokv.log for details"
fi

echo ""
print_success "🎉 Quick setup completed!"
echo ""
print_status "Your DenoKV server is ready!"
echo "  URL: http://your-server-ip:4512"
echo "  Token: $DENO_KV_ACCESS_TOKEN"
echo ""
print_status "Management commands:"
echo "  ./manage-services.sh status  - Check status"
echo "  ./manage-services.sh logs    - View logs"
echo "  ./manage-services.sh restart - Restart server"