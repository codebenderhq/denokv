#!/bin/bash
# Script to safely free up PostgreSQL-related disk space

echo "=== Freeing Up PostgreSQL Disk Space ==="
echo ""

# Find PostgreSQL data directory
PG_DATA_DIR="/var/lib/pgsql/data"
if [ ! -d "$PG_DATA_DIR" ]; then
    PG_DATA_DIR="/var/lib/postgresql/*/data"
fi

# Show current disk usage
echo "Current disk usage:"
df -h /
echo ""

# 1. Clean old PostgreSQL log files (keep last 7 days)
echo "1. Cleaning PostgreSQL log files older than 7 days..."
LOG_COUNT=$(sudo find $PG_DATA_DIR/log -name "*.log" -mtime +7 2>/dev/null | wc -l)
if [ "$LOG_COUNT" -gt 0 ]; then
    echo "  Found $LOG_COUNT log files to clean"
    sudo find $PG_DATA_DIR/log -name "*.log" -mtime +7 -delete 2>/dev/null
    echo "  PostgreSQL log files cleaned"
else
    echo "  No old log files found in $PG_DATA_DIR/log"
fi

# Try alternative log location
LOG_COUNT2=$(sudo find $PG_DATA_DIR/pg_log -name "*.log" -mtime +7 2>/dev/null | wc -l)
if [ "$LOG_COUNT2" -gt 0 ]; then
    echo "  Found $LOG_COUNT2 log files to clean in pg_log"
    sudo find $PG_DATA_DIR/pg_log -name "*.log" -mtime +7 -delete 2>/dev/null
    echo "  PostgreSQL pg_log files cleaned"
fi
echo ""

# 2. Clean system journal logs (keep last 3 days)
echo "2. Cleaning system journal logs (keeping last 3 days)..."
BEFORE=$(sudo journalctl --disk-usage 2>/dev/null | grep -oP '\d+\.\d+[GM]' || echo "0")
sudo journalctl --vacuum-time=3d
AFTER=$(sudo journalctl --disk-usage 2>/dev/null | grep -oP '\d+\.\d+[GM]' || echo "0")
echo "  Journal logs cleaned (before: $BEFORE, after: $AFTER)"
echo ""

# 3. Clean package cache
echo "3. Cleaning package cache..."
sudo dnf clean all 2>/dev/null || sudo yum clean all 2>/dev/null
echo "  Package cache cleaned"
echo ""

# 4. Show new disk usage
echo "New disk usage:"
df -h /
echo ""

# 5. Show space freed
echo "=== Space Cleanup Complete ==="
echo ""
echo "To see what's still using space:"
echo "  sudo du -h --max-depth=1 / | sort -hr | head -10"




  Run these commands on your server to find which PostgreSQL files are using space:

  Check What's Using Space


     1 │# 1. Check PostgreSQL data directory size
     2 │sudo du -sh /var/lib/pgsql/data
     3 │
     4 │# 2. Find largest PostgreSQL files/directories
     5 │sudo du -h --max-depth=2 /var/lib/pgsql/data | sort -hr | head -20
     6 │
     7 │# 3. Check PostgreSQL log files
     8 │sudo du -sh /var/lib/pgsql/data/log/* 2>/dev/null
     9 │sudo du -sh /var/lib/pgsql/data/pg_log/* 2>/dev/null
    10 │
    11 │# 4. List log files by size
    12 │sudo find /var/lib/pgsql/data -name "*.log" -type f -exec du -h {} \; | sort -hr | head -10
    13 │
    14 │# 5. Check WAL files (Write-Ahead Log)
    15 │sudo du -sh /var/lib/pgsql/data/pg_wal
    16 │sudo ls -lh /var/lib/pgsql/data/pg_wal/* | tail -20
    17 │
    18 │# 6. Check system journal (often the biggest)
    19 │sudo journalctl --disk-usage
    20 │
    21 │# 7. Top 10 largest directories on root
    22 │sudo du -h --max-depth=1 / | sort -hr | head -10


  Free Up Space Safely


     1 │# 1. Clean old PostgreSQL logs (keep last 7 days)
     2 │sudo find /var/lib/pgsql/data/log -name "*.log" -mtime +7 -delete
     3 │sudo find /var/lib/pgsql/data/pg_log -name "*.log" -mtime +7 -delete
     4 │
     5 │# 2. Clean system journal (keep last 3 days) - usually frees the most space
     6 │sudo journalctl --vacuum-time=3d
     7 │
     8 │# 3. Clean package cache
     9 │sudo dnf clean all
    10 │
    11 │# 4. Check space freed
    12 │df -h /


  Quick One-Liner to See Biggest PostgreSQL Files


  sudo du -h /var/lib/pgsql/data | sort -hr | head -20

  Start with the check commands to see what's using space, then run the cleanup commands. The system journal (journalctl) is often the largest consumer.
  After freeing space, restart PostgreSQL:

  sudo systemctl restart postgresq