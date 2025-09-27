#!/bin/bash

# Fresh PostgreSQL Setup Script for DenoKV
# This script completely removes PostgreSQL and sets it up fresh
# Author: Assistant
# Date: $(date '+%Y-%m-%d %H:%M:%S')

set -e  # Exit on any error

echo "🔄 Fresh PostgreSQL Setup for DenoKV"
echo "====================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
POSTGRES_VERSION="15"
DENOKV_USER="denokv"
DENOKV_PASSWORD="denokv_password"
DENOKV_DATABASE="denokv"
POSTGRES_DATA_DIR="/var/lib/pgsql/data"
POSTGRES_LOG_DIR="/var/lib/pgsql/log"

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

print_step() {
    echo -e "${PURPLE}[STEP]${NC} $1"
}

print_debug() {
    echo -e "${CYAN}[DEBUG]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to wait for service
wait_for_service() {
    local service_name=$1
    local max_attempts=${2:-30}
    local attempt=1
    
    print_status "Waiting for $service_name to be ready..."
    while [ $attempt -le $max_attempts ]; do
        if systemctl is-active --quiet "$service_name"; then
            print_success "$service_name is ready!"
            return 0
        fi
        print_debug "Attempt $attempt/$max_attempts - $service_name not ready yet..."
        sleep 2
        ((attempt++))
    done
    
    print_error "$service_name failed to start after $max_attempts attempts"
    return 1
}

# Function to backup existing configuration
backup_config() {
    local config_file=$1
    if [ -f "$config_file" ]; then
        local backup_file="${config_file}.backup.$(date +%Y%m%d_%H%M%S)"
        print_status "Backing up $config_file to $backup_file"
        sudo cp "$config_file" "$backup_file"
    fi
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   print_error "This script should not be run as root. Please run as a regular user with sudo privileges."
   exit 1
fi

# Check if sudo is available
if ! command_exists sudo; then
    print_error "sudo is required but not installed. Please install sudo first."
    exit 1
fi

# Check if dnf is available
if ! command_exists dnf; then
    print_error "dnf package manager is required but not found. This script is designed for Rocky Linux/RHEL/CentOS."
    exit 1
fi

print_status "Starting fresh PostgreSQL setup..."
print_status "Configuration: PostgreSQL $POSTGRES_VERSION, User: $DENOKV_USER, Database: $DENOKV_DATABASE"
echo ""

# Step 1: Stop and remove existing PostgreSQL
print_step "Step 1: Stopping and removing existing PostgreSQL..."

# Stop all PostgreSQL-related services
print_status "Stopping PostgreSQL services..."
sudo systemctl stop postgresql 2>/dev/null || true
sudo systemctl stop postgresql-${POSTGRES_VERSION} 2>/dev/null || true
sudo systemctl disable postgresql 2>/dev/null || true
sudo systemctl disable postgresql-${POSTGRES_VERSION} 2>/dev/null || true

# Kill any remaining PostgreSQL processes
print_status "Killing any remaining PostgreSQL processes..."
sudo pkill -f postgres 2>/dev/null || true
sleep 2

# Remove PostgreSQL packages
print_status "Removing PostgreSQL packages..."
sudo dnf remove -y postgresql* 2>/dev/null || true

# Remove PostgreSQL data directories
print_status "Removing PostgreSQL data directories..."
sudo rm -rf /var/lib/pgsql 2>/dev/null || true
sudo rm -rf /var/lib/postgresql 2>/dev/null || true
sudo rm -rf /var/lib/postgres 2>/dev/null || true

# Remove PostgreSQL configuration directories
print_status "Removing PostgreSQL configuration directories..."
sudo rm -rf /etc/postgresql 2>/dev/null || true
sudo rm -rf /etc/postgresql-common 2>/dev/null || true
sudo rm -rf /usr/lib/postgresql 2>/dev/null || true

# Remove PostgreSQL user and group
print_status "Removing PostgreSQL user and group..."
sudo userdel postgres 2>/dev/null || true
sudo groupdel postgres 2>/dev/null || true

# Clean up any remaining files
print_status "Cleaning up remaining PostgreSQL files..."
sudo rm -rf /tmp/.s.PGSQL.* 2>/dev/null || true
sudo rm -rf /var/run/postgresql 2>/dev/null || true

print_success "PostgreSQL completely removed!"

# Step 2: Install fresh PostgreSQL
print_step "Step 2: Installing fresh PostgreSQL..."

# Update system packages
print_status "Updating system packages..."
sudo dnf update -y

# Install PostgreSQL packages
print_status "Installing PostgreSQL packages..."
sudo dnf install -y postgresql${POSTGRES_VERSION} postgresql${POSTGRES_VERSION}-server postgresql${POSTGRES_VERSION}-contrib postgresql${POSTGRES_VERSION}-devel

# Install additional useful packages
print_status "Installing additional packages..."
sudo dnf install -y postgresql${POSTGRES_VERSION}-plpython3 postgresql${POSTGRES_VERSION}-plperl 2>/dev/null || true

print_success "PostgreSQL packages installed!"

# Step 3: Initialize PostgreSQL
print_step "Step 3: Initializing PostgreSQL database..."

# Create PostgreSQL directories with proper permissions
print_status "Creating PostgreSQL directories..."
sudo mkdir -p "$POSTGRES_DATA_DIR"
sudo mkdir -p "$POSTGRES_LOG_DIR"
sudo mkdir -p /var/run/postgresql

# Set proper ownership and permissions
print_status "Setting directory permissions..."
sudo chown -R postgres:postgres /var/lib/pgsql
sudo chown -R postgres:postgres /var/run/postgresql
sudo chmod 700 "$POSTGRES_DATA_DIR"
sudo chmod 755 "$POSTGRES_LOG_DIR"
sudo chmod 755 /var/run/postgresql

# Initialize the database
print_status "Initializing PostgreSQL database..."
sudo -u postgres /usr/pgsql-${POSTGRES_VERSION}/bin/initdb -D "$POSTGRES_DATA_DIR" --auth-local=trust --auth-host=trust

print_success "PostgreSQL database initialized!"

# Step 4: Configure PostgreSQL
print_step "Step 4: Configuring PostgreSQL..."

# Backup existing configuration files
backup_config "$POSTGRES_DATA_DIR/pg_hba.conf"
backup_config "$POSTGRES_DATA_DIR/postgresql.conf"

# Configure pg_hba.conf for local connections
print_status "Configuring authentication (pg_hba.conf)..."
sudo tee "$POSTGRES_DATA_DIR/pg_hba.conf" > /dev/null << 'EOF'
# PostgreSQL Client Authentication Configuration File
# ===================================================
#
# TYPE  DATABASE        USER            ADDRESS                 METHOD

# "local" is for Unix domain socket connections only
local   all             all                                     trust
# IPv4 local connections:
host    all             all             127.0.0.1/32            trust
host    all             all             0.0.0.0/0               trust
# IPv6 local connections:
host    all             all             ::1/128                 trust
host    all             all             ::/0                    trust
# Allow replication connections from localhost, by a user with the
# replication privilege.
local   replication     all                                     trust
host    replication     all             127.0.0.1/32            trust
host    replication     all             ::1/128                 trust
EOF

# Configure postgresql.conf
print_status "Configuring PostgreSQL settings..."
sudo tee /var/lib/pgsql/data/postgresql.conf > /dev/null << 'EOF'
# PostgreSQL configuration for DenoKV

# Connection settings
listen_addresses = 'localhost'
port = 5432
max_connections = 100

# Memory settings
shared_buffers = 128MB
effective_cache_size = 512MB

# Logging
log_destination = 'stderr'
logging_collector = on
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_rotation_age = 1d
log_rotation_size = 10MB
log_min_duration_statement = 1000

# Locale
lc_messages = 'en_US.UTF-8'
lc_monetary = 'en_US.UTF-8'
lc_numeric = 'en_US.UTF-8'
lc_time = 'en_US.UTF-8'

# Default locale for this database
default_text_search_config = 'pg_catalog.english'
EOF

# Step 5: Start PostgreSQL
print_status "Step 5: Starting PostgreSQL service..."
sudo systemctl enable postgresql
sudo systemctl start postgresql

# Wait for PostgreSQL to be ready
print_status "Waiting for PostgreSQL to be ready..."
for i in {1..30}; do
    if sudo -u postgres psql -c "SELECT 1;" >/dev/null 2>&1; then
        print_success "PostgreSQL is ready!"
        break
    fi
    if [ $i -eq 30 ]; then
        print_error "PostgreSQL failed to start after 30 seconds"
        exit 1
    fi
    sleep 1
done

# Step 6: Create DenoKV database and user
print_status "Step 6: Creating DenoKV database and user..."

# Create denokv user
sudo -u postgres psql -c "CREATE USER denokv WITH PASSWORD 'denokv_password';" 2>/dev/null || print_warning "User denokv may already exist"

# Create denokv database
sudo -u postgres psql -c "CREATE DATABASE denokv OWNER denokv;" 2>/dev/null || print_warning "Database denokv may already exist"

# Grant privileges
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE denokv TO denokv;"

# Step 7: Test connection
print_status "Step 7: Testing database connection..."
if sudo -u postgres psql -d denokv -c "SELECT current_database(), current_user;" >/dev/null 2>&1; then
    print_success "Database connection test passed!"
else
    print_error "Database connection test failed"
    exit 1
fi

# Step 8: Display connection information
print_success "PostgreSQL setup completed successfully!"
echo ""
echo "📋 Connection Information:"
echo "========================="
echo "Host: localhost"
echo "Port: 5432"
echo "Database: denokv"
echo "Username: denokv"
echo "Password: denokv_password"
echo ""
echo "🔧 Test connection with:"
echo "psql -h localhost -p 5432 -U denokv -d denokv"
echo ""
echo "🚀 You can now run your DenoKV setup script!"
echo ""

# Step 9: Optional - Enable password authentication
read -p "Do you want to enable password authentication? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_status "Enabling password authentication..."
    
    # Update pg_hba.conf to use md5
    sudo sed -i 's/trust/md5/g' /var/lib/pgsql/data/pg_hba.conf
    
    # Reload PostgreSQL
    sudo systemctl reload postgresql
    
    print_success "Password authentication enabled!"
    print_warning "You will now need to use passwords for database connections"
else
    print_status "Password authentication remains disabled (trust mode)"
    print_warning "This is less secure but easier for development"
fi

print_success "Fresh PostgreSQL setup completed! 🎉"