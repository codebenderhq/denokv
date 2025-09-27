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
    sleep 2
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