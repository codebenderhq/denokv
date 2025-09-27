#!/bin/bash

# PostgreSQL Connection Test Script for DenoKV

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

echo "🔍 PostgreSQL Connection Test for DenoKV"
echo "=========================================="
echo ""

# Default environment variables
DEFAULT_POSTGRES_URL="postgresql://denokv:denokv_password@localhost:5432/denokv"
DEFAULT_DENO_KV_POSTGRES_URL="postgresql://denokv:denokv_password@localhost:5432/denokv"

# Check if .env file exists and source it
if [ -f ".env" ]; then
    print_status "Loading environment variables from .env file..."
    source .env
fi

# Use environment variables or defaults
POSTGRES_URL=${POSTGRES_URL:-$DEFAULT_POSTGRES_URL}
DENO_KV_POSTGRES_URL=${DENO_KV_POSTGRES_URL:-$DEFAULT_DENO_KV_POSTGRES_URL}

echo "📋 Environment Variables:"
echo "  POSTGRES_URL: $POSTGRES_URL"
echo "  DENO_KV_POSTGRES_URL: $DENO_KV_POSTGRES_URL"
echo ""

# Test 1: Check if PostgreSQL service is running
print_status "Test 1: Checking PostgreSQL service status..."
if systemctl is-active --quiet postgresql; then
    print_success "PostgreSQL service is running"
else
    print_error "PostgreSQL service is not running"
    print_status "Start it with: sudo systemctl start postgresql"
    exit 1
fi

# Test 2: Check if PostgreSQL is accepting connections
print_status "Test 2: Checking PostgreSQL connection..."
if sudo -u postgres pg_isready; then
    print_success "PostgreSQL is accepting connections"
else
    print_error "PostgreSQL is not accepting connections"
    exit 1
fi

# Test 3: Test connection with psql
print_status "Test 3: Testing database connection with psql..."

# Extract connection details from URL
# Format: postgresql://user:password@host:port/database
if [[ $DENO_KV_POSTGRES_URL =~ postgresql://([^:]+):([^@]+)@([^:]+):([^/]+)/(.+) ]]; then
    DB_USER="${BASH_REMATCH[1]}"
    DB_PASSWORD="${BASH_REMATCH[2]}"
    DB_HOST="${BASH_REMATCH[3]}"
    DB_PORT="${BASH_REMATCH[4]}"
    DB_NAME="${BASH_REMATCH[5]}"
    
    echo "  User: $DB_USER"
    echo "  Host: $DB_HOST"
    echo "  Port: $DB_PORT"
    echo "  Database: $DB_NAME"
    echo ""
    
    # Test connection
    if PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1 as test_connection;" >/dev/null 2>&1; then
        print_success "Database connection successful!"
    else
        print_error "Database connection failed"
        print_status "Trying to diagnose the issue..."
        
        # Check if user exists
        if sudo -u postgres psql -c "SELECT 1 FROM pg_user WHERE usename='$DB_USER';" | grep -q "1 row"; then
            print_status "User '$DB_USER' exists"
        else
            print_error "User '$DB_USER' does not exist"
            print_status "Create user with: sudo -u postgres psql -c \"CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';\""
        fi
        
        # Check if database exists
        if sudo -u postgres psql -c "SELECT 1 FROM pg_database WHERE datname='$DB_NAME';" | grep -q "1 row"; then
            print_status "Database '$DB_NAME' exists"
        else
            print_error "Database '$DB_NAME' does not exist"
            print_status "Create database with: sudo -u postgres psql -c \"CREATE DATABASE $DB_NAME;\""
        fi
        
        exit 1
    fi
else
    print_error "Could not parse PostgreSQL URL: $DENO_KV_POSTGRES_URL"
    exit 1
fi

# Test 4: Test DenoKV specific operations
print_status "Test 4: Testing DenoKV specific database operations..."

# Test creating a simple table (if it doesn't exist)
PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
CREATE TABLE IF NOT EXISTS test_table (
    id SERIAL PRIMARY KEY,
    test_data TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);" >/dev/null 2>&1

if [ $? -eq 0 ]; then
    print_success "DenoKV database operations test successful"
else
    print_warning "DenoKV database operations test failed (may need permissions)"
fi

# Test 5: Check port 4512 (DenoKV server port)
print_status "Test 5: Checking DenoKV server port (4512)..."
if netstat -tlnp 2>/dev/null | grep -q ":4512 "; then
    print_success "Port 4512 is open (DenoKV server may be running)"
else
    print_warning "Port 4512 is closed (DenoKV server not running)"
    print_status "Start DenoKV server with: ./manage-services.sh start"
fi

echo ""
print_success "🎉 PostgreSQL connection test completed!"
echo ""
print_status "Summary:"
echo "  ✅ PostgreSQL service: Running"
echo "  ✅ PostgreSQL connection: Working"
echo "  ✅ Database access: Working"
echo "  ✅ DenoKV operations: Working"
echo ""
print_status "Your PostgreSQL URL is ready for DenoKV:"
echo "  $DENO_KV_POSTGRES_URL"
echo ""
print_status "To start DenoKV server:"
echo "  ./manage-services.sh start"