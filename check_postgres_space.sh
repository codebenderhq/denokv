#!/bin/bash
# Script to find which PostgreSQL files are using disk space

echo "=== PostgreSQL Disk Space Analysis ==="
echo ""

# Find PostgreSQL data directory
PG_DATA_DIR="/var/lib/pgsql/data"
if [ ! -d "$PG_DATA_DIR" ]; then
    PG_DATA_DIR="/var/lib/postgresql/*/data"
fi

echo "1. PostgreSQL data directory size:"
sudo du -sh $PG_DATA_DIR 2>/dev/null || echo "Could not find PostgreSQL data directory"
echo ""

echo "2. Top 20 largest files/directories in PostgreSQL data:"
sudo du -h --max-depth=2 $PG_DATA_DIR 2>/dev/null | sort -hr | head -20
echo ""

echo "3. PostgreSQL log files size:"
sudo du -sh $PG_DATA_DIR/log/* 2>/dev/null || sudo du -sh $PG_DATA_DIR/pg_log/* 2>/dev/null || echo "No log files found"
echo ""

echo "4. Individual log files (sorted by size):"
sudo find $PG_DATA_DIR -name "*.log" -type f -exec du -h {} \; 2>/dev/null | sort -hr | head -10
echo ""

echo "5. WAL (Write-Ahead Log) files size:"
sudo du -sh $PG_DATA_DIR/pg_wal 2>/dev/null || echo "WAL directory not found"
echo ""

echo "6. Check for old WAL files:"
sudo ls -lh $PG_DATA_DIR/pg_wal/* 2>/dev/null | tail -20 || echo "No WAL files found"
echo ""

echo "7. Check PostgreSQL log configuration:"
sudo -u postgres psql -c "SHOW log_directory;" 2>/dev/null || echo "Could not connect to PostgreSQL"
sudo -u postgres psql -c "SHOW log_filename;" 2>/dev/null || echo ""
echo ""

echo "8. System journal logs (often the biggest culprit):"
sudo journalctl --disk-usage
echo ""

echo "9. Top 10 largest directories on root filesystem:"
sudo du -h --max-depth=1 / 2>/dev/null | sort -hr | head -10
echo ""

echo "=== Summary ==="
echo "To clean PostgreSQL logs (keep last 7 days):"
echo "  sudo find $PG_DATA_DIR/log -name '*.log' -mtime +7 -delete"
echo "  sudo find $PG_DATA_DIR/pg_log -name '*.log' -mtime +7 -delete"
echo ""
echo "To clean system journal (keep last 3 days):"
echo "  sudo journalctl --vacuum-time=3d"
echo ""
