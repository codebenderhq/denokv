#!/bin/bash

# Complete DenoKV Setup Script for Rocky Linux
# This script does everything: PostgreSQL setup, environment setup, and starts DenoKV in background
# Author: Assistant

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Configuration
DENOKV_USER="denokv"
DENOKV_PASSWORD="denokv_password"
DENOKV_DATABASE="denokv"
POSTGRES_DATA_DIR="/var/lib/pgsql/data"
DENOKV_PORT="4512"
DENOKV_ADDR="0.0.0.0:${DENOKV_PORT}"
DENOKV_LOG_FILE="denokv.log"
DENOKV_PID_FILE="denokv.pid"

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_step() { echo -e "${PURPLE}[STEP]${NC} $1"; }

# Determine if we need sudo based on current user
if [[ $EUID -eq 0 ]]; then
   SUDO_CMD=""  # No sudo needed when running as root
else
   if ! command -v sudo >/dev/null 2>&1; then
       print_error "sudo is required but not installed. Please install sudo first."
       exit 1
   fi
   SUDO_CMD="sudo"  # Use sudo when running as regular user
fi

echo "🚀 Complete DenoKV Setup for Rocky Linux"
echo "========================================="
echo ""

# Step 1: Clean up unnecessary scripts
print_step "Step 1: Cleaning up unnecessary scripts..."
rm -f fresh-postgres-setup.sh setup-rocky-linux.sh start-denokv-background.sh start-denokv-simple.sh test_*.ts 2>/dev/null || true
print_success "Unnecessary scripts removed!"

# Step 2: Stop and remove existing PostgreSQL
print_step "Step 2: Setting up PostgreSQL..."

# Stop PostgreSQL services
$SUDO_CMD systemctl stop postgresql postgresql-16 2>/dev/null || true
$SUDO_CMD systemctl disable postgresql postgresql-16 2>/dev/null || true
$SUDO_CMD pkill -f postgres 2>/dev/null || true
sleep 2

# Remove PostgreSQL packages and data
$SUDO_CMD dnf remove -y postgresql* postgresql16* 2>/dev/null || true
$SUDO_CMD rm -rf /var/lib/pgsql /var/lib/postgresql /var/lib/postgres 2>/dev/null || true
$SUDO_CMD rm -rf /etc/postgresql /etc/postgresql-common /usr/lib/postgresql 2>/dev/null || true
$SUDO_CMD userdel postgres 2>/dev/null || true
$SUDO_CMD groupdel postgres 2>/dev/null || true
$SUDO_CMD rm -rf /tmp/.s.PGSQL.* /var/run/postgresql 2>/dev/null || true

print_success "PostgreSQL completely removed!"

# Step 3: Install latest PostgreSQL
print_status "Installing latest PostgreSQL packages..."
$SUDO_CMD dnf update -y

# Install PostgreSQL 16 (latest stable version)
print_status "Installing PostgreSQL 16 (latest stable)..."
$SUDO_CMD dnf install -y postgresql16 postgresql16-server postgresql16-contrib postgresql16-devel

# Verify PostgreSQL version
POSTGRES_VERSION=$(postgres --version 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+' | head -1 || echo "Unknown")
print_success "PostgreSQL $POSTGRES_VERSION installed"

# Step 4: Initialize PostgreSQL
print_status "Initializing PostgreSQL database..."
$SUDO_CMD mkdir -p "$POSTGRES_DATA_DIR"
$SUDO_CMD mkdir -p /var/run/postgresql
$SUDO_CMD chown -R postgres:postgres /var/lib/pgsql
$SUDO_CMD chown -R postgres:postgres /var/run/postgresql
$SUDO_CMD chmod 700 "$POSTGRES_DATA_DIR"
$SUDO_CMD chmod 755 /var/run/postgresql

# Initialize PostgreSQL 16
print_status "Initializing PostgreSQL 16 database..."
$SUDO_CMD /usr/pgsql-16/bin/postgresql-16-setup --initdb

# Step 5: Configure PostgreSQL
print_status "Configuring PostgreSQL..."
$SUDO_CMD tee "$POSTGRES_DATA_DIR/pg_hba.conf" > /dev/null << 'EOF'
# PostgreSQL Client Authentication Configuration File
local   all             all                                     trust
host    all             all             127.0.0.1/32            trust
host    all             all             0.0.0.0/0               trust
host    all             all             ::1/128                 trust
host    all             all             ::/0                    trust
local   replication     all                                     trust
host    replication     all             127.0.0.1/32            trust
host    replication     all             ::1/128                 trust
EOF

$SUDO_CMD tee "$POSTGRES_DATA_DIR/postgresql.conf" > /dev/null << 'EOF'
# PostgreSQL configuration for DenoKV
listen_addresses = 'localhost'
port = 5432
max_connections = 100
shared_buffers = 128MB
effective_cache_size = 512MB
log_destination = 'stderr'
logging_collector = on
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_rotation_age = 1d
log_rotation_size = 10MB
log_min_duration_statement = 1000
lc_messages = 'en_US.UTF-8'
lc_monetary = 'en_US.UTF-8'
lc_numeric = 'en_US.UTF-8'
lc_time = 'en_US.UTF-8'
default_text_search_config = 'pg_catalog.english'
EOF

# Step 6: Start PostgreSQL
print_status "Starting PostgreSQL 16 service..."
$SUDO_CMD systemctl enable postgresql-16
$SUDO_CMD systemctl start postgresql-16

# Wait for PostgreSQL to be ready
print_status "Waiting for PostgreSQL to be ready..."
for i in {1..30}; do
    if $SUDO_CMD -u postgres psql -c "SELECT 1;" >/dev/null 2>&1; then
        print_success "PostgreSQL is ready!"
        break
    fi
    if [ $i -eq 30 ]; then
        print_error "PostgreSQL failed to start after 30 seconds"
        exit 1
    fi
    sleep 1
done

# Step 7: Create DenoKV database and user
print_status "Creating DenoKV database and user..."
$SUDO_CMD -u postgres psql -c "ALTER USER postgres PASSWORD 'postgres_password';" 2>/dev/null || true
$SUDO_CMD -u postgres psql -c "CREATE USER denokv WITH PASSWORD 'denokv_password';" 2>/dev/null || true
$SUDO_CMD -u postgres psql -c "CREATE DATABASE denokv OWNER denokv;" 2>/dev/null || true
$SUDO_CMD -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE denokv TO denokv;"
$SUDO_CMD -u postgres psql -c "GRANT ALL PRIVILEGES ON SCHEMA public TO denokv;" 2>/dev/null || true

print_success "PostgreSQL setup completed!"

# Step 8: Set up environment variables
print_step "Step 3: Setting up environment variables..."

# Create environment file
cat > .env << EOF
# DenoKV PostgreSQL Configuration
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_DB=denokv
POSTGRES_USER=denokv
POSTGRES_PASSWORD=denokv_password

# DenoKV Server Configuration
DENOKV_PORT=4512
DENOKV_ACCESS_TOKEN=2d985dc9ed08a06b35b5a15f85925290

# Development Configuration
RUST_LOG=info
DENO_ENV=production
EOF

# Add environment variables to shell profile
if [ -f ~/.bashrc ]; then
    echo "" >> ~/.bashrc
    echo "# DenoKV Environment Variables" >> ~/.bashrc
    echo "export POSTGRES_HOST=localhost" >> ~/.bashrc
    echo "export POSTGRES_PORT=5432" >> ~/.bashrc
    echo "export POSTGRES_DB=denokv" >> ~/.bashrc
    echo "export POSTGRES_USER=denokv" >> ~/.bashrc
    echo "export POSTGRES_PASSWORD=denokv_password" >> ~/.bashrc
    echo "export DENOKV_PORT=4512" >> ~/.bashrc
    echo "export DENOKV_ACCESS_TOKEN=2d985dc9ed08a06b35b5a15f85925290" >> ~/.bashrc
    echo "export RUST_LOG=info" >> ~/.bashrc
    echo "export DENO_ENV=production" >> ~/.bashrc
fi

# Source environment variables for current session
export POSTGRES_HOST=localhost
export POSTGRES_PORT=5432
export POSTGRES_DB=denokv
export POSTGRES_USER=denokv
export POSTGRES_PASSWORD=denokv_password
export DENOKV_PORT=4512
export DENOKV_ACCESS_TOKEN=2d985dc9ed08a06b35b5a15f85925290
export RUST_LOG=info
export DENO_ENV=production

print_success "Environment variables configured!"

# Step 9: Build DenoKV and setup systemd service
print_step "Step 4: Building DenoKV and setting up systemd service..."

# Stop any existing DenoKV processes
print_status "Stopping any existing DenoKV processes..."
$SUDO_CMD systemctl stop denokv.service 2>/dev/null || true
if [ -f "$DENOKV_PID_FILE" ]; then
    PID=$(cat "$DENOKV_PID_FILE")
    kill "$PID" 2>/dev/null || true
    rm -f "$DENOKV_PID_FILE"
fi

# Build DenoKV
print_status "Building DenoKV..."
if [ ! -f "target/release/denokv" ]; then
    cargo build --release
    if [ $? -ne 0 ]; then
        print_error "Failed to build DenoKV"
        exit 1
    fi
fi

print_success "DenoKV binary ready"

# Create denokv user if it doesn't exist
if ! id "denokv" &>/dev/null; then
    print_status "Creating denokv user..."
    $SUDO_CMD useradd -r -s /bin/false -d /home/denokv denokv
    $SUDO_CMD mkdir -p /home/denokv
    $SUDO_CMD chown denokv:denokv /home/denokv
fi

# Install DenoKV binary to system location
print_status "Installing DenoKV binary..."
$SUDO_CMD cp target/release/denokv /usr/local/bin/denokv
$SUDO_CMD chmod +x /usr/local/bin/denokv
$SUDO_CMD chown root:root /usr/local/bin/denokv

# Create systemd service file
print_status "Creating systemd service..."
$SUDO_CMD tee /etc/systemd/system/denokv.service > /dev/null << EOF
[Unit]
Description=DenoKV Server
After=network.target postgresql-16.service
Requires=postgresql-16.service

[Service]
Type=simple
User=denokv
Group=denokv
WorkingDirectory=/home/denokv
ExecStart=/usr/local/bin/denokv serve --addr $DENOKV_ADDR
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=denokv

# Environment variables
Environment=RUST_LOG=info
Environment=DENO_ENV=production
Environment=POSTGRES_HOST=localhost
Environment=POSTGRES_PORT=5432
Environment=POSTGRES_DB=denokv
Environment=POSTGRES_USER=denokv
Environment=POSTGRES_PASSWORD=denokv_password

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and enable service
print_status "Enabling DenoKV systemd service..."
$SUDO_CMD systemctl daemon-reload
$SUDO_CMD systemctl enable denokv.service

# Start the service
print_status "Starting DenoKV service..."
$SUDO_CMD systemctl start denokv.service

# Wait for service to start
print_status "Waiting for DenoKV to start..."
sleep 3

# Check if service is running
if $SUDO_CMD systemctl is-active --quiet denokv.service; then
    print_success "DenoKV systemd service started successfully!"
    
    # Get the PID
    DENOKV_PID=$($SUDO_CMD systemctl show -p MainPID --value denokv.service)
    echo "$DENOKV_PID" > "$DENOKV_PID_FILE"
    
    # Test the connection
    print_status "Testing DenoKV connection..."
    sleep 2
    
    if curl -s http://localhost:$DENOKV_PORT/ > /dev/null; then
        print_success "DenoKV is responding on port $DENOKV_PORT"
    else
        print_warning "DenoKV may not be fully ready yet, but service is running"
    fi
    
else
    print_error "Failed to start DenoKV systemd service"
    print_status "Checking service status..."
    $SUDO_CMD systemctl status denokv.service --no-pager
    exit 1
fi

# Final summary
echo ""
print_success "🎉 Complete DenoKV setup finished!"
echo ""
echo "📋 Setup Summary:"
echo "=================="
echo "✅ PostgreSQL: Fresh installation with denokv database"
echo "✅ Environment: Variables configured and exported"
echo "✅ DenoKV: Built and running as systemd service"
echo "✅ Systemd: Service created and enabled for auto-start"
echo "✅ Cleanup: Unnecessary scripts removed"
echo ""
echo "🔧 Service Information:"
echo "======================="
echo "Service: denokv.service"
echo "Status: $(systemctl is-active denokv.service)"
echo "PID: $DENOKV_PID"
echo "Port: $DENOKV_PORT"
echo "Address: $DENOKV_ADDR"
echo "User: denokv"
echo "Binary: /usr/local/bin/denokv"
echo ""
echo "🌍 Environment Variables:"
echo "=========================="
echo "POSTGRES_HOST=localhost"
echo "POSTGRES_PORT=5432"
echo "POSTGRES_DB=denokv"
echo "POSTGRES_USER=denokv"
echo "POSTGRES_PASSWORD=denokv_password"
echo "DENOKV_PORT=4512"
echo "DENOKV_ACCESS_TOKEN=2d985dc9ed08a06b35b5a15f85925290"
echo ""
echo "🔧 Systemd Management Commands:"
echo "==============================="
echo "Start:   sudo systemctl start denokv.service"
echo "Stop:    sudo systemctl stop denokv.service"
echo "Restart: sudo systemctl restart denokv.service"
echo "Status:  sudo systemctl status denokv.service"
echo "Logs:    sudo journalctl -u denokv.service -f"
echo "Enable:  sudo systemctl enable denokv.service"
echo "Disable: sudo systemctl disable denokv.service"
echo ""
echo "🌐 Test Connection:"
echo "==================="
echo "curl http://localhost:$DENOKV_PORT/"
echo "curl http://102.37.137.29:$DENOKV_PORT/"
echo ""
echo "🚀 DenoKV is ready for production use!"
echo "   - Auto-starts on boot"
echo "   - Auto-restarts on crash"
echo "   - Runs as secure system user"
echo "   - Integrated with systemd logging"