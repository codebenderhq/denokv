# CRITICAL: Disk Full Issue - Root Cause of PostgreSQL Crashes

## Immediate Problem

Your root filesystem is **100% full**:
```
/dev/mapper/rocky-lvroot  8.8G  8.8G   20K 100% /
```

**This is almost certainly the cause of your PostgreSQL crashes!**

When a disk is full:
- PostgreSQL cannot write to WAL (Write-Ahead Log)
- PostgreSQL cannot create temporary files
- PostgreSQL cannot write relation-cache files (explains your warnings)
- PostgreSQL processes can crash when they can't write

## Immediate Actions Required

### 1. Find What's Using Disk Space

```bash
# Find largest directories
sudo du -h --max-depth=1 / | sort -hr | head -20

# Check PostgreSQL data directory size
sudo du -sh /var/lib/pgsql/* 2>/dev/null || sudo du -sh /var/lib/postgresql/* 2>/dev/null

# Check log files
sudo du -sh /var/log/* | sort -hr | head -10

# Check for large files
sudo find / -type f -size +100M 2>/dev/null | head -20
```

### 2. Find PostgreSQL Logs

PostgreSQL logs might be in different locations:

```bash
# Check PostgreSQL configuration for log location
sudo -u postgres psql -c "SHOW log_directory;"
sudo -u postgres psql -c "SHOW log_filename;"

# Common locations:
ls -lh /var/lib/pgsql/*/data/log/ 2>/dev/null
ls -lh /var/lib/postgresql/*/log/ 2>/dev/null
ls -lh /var/log/postgresql/ 2>/dev/null
journalctl -u postgresql* -n 100
```

### 3. Free Up Disk Space Immediately

**Option A: Clean up log files**
```bash
# Check log sizes
sudo du -sh /var/log/*

# Clean old logs (be careful!)
sudo journalctl --vacuum-time=7d  # Keep only 7 days
sudo find /var/log -name "*.log" -mtime +30 -delete  # Delete logs older than 30 days
```

**Option B: Clean PostgreSQL logs**
```bash
# Find PostgreSQL log directory
PG_LOG_DIR=$(sudo -u postgres psql -t -c "SHOW log_directory;" | xargs)
echo "PostgreSQL logs at: $PG_LOG_DIR"

# Clean old PostgreSQL logs (keep last 7 days)
sudo find "$PG_LOG_DIR" -name "*.log" -mtime +7 -delete
```

**Option C: Clean package cache**
```bash
sudo dnf clean all
sudo yum clean all 2>/dev/null
```

**Option D: Remove old kernels**
```bash
# List installed kernels
rpm -qa kernel

# Remove old kernels (keep current + 1 backup)
sudo dnf remove --oldinstallonly
```

**Option E: Check for large temporary files**
```bash
sudo find /tmp -type f -size +100M -ls
sudo find /var/tmp -type f -size +100M -ls
```

### 4. Expand Disk Space (Long-term Solution)

If you're on Rocky Linux with LVM:

```bash
# Check available space in volume group
sudo vgs

# If you have free space in VG, extend the logical volume
sudo lvextend -l +100%FREE /dev/mapper/rocky-lvroot
sudo resize2fs /dev/mapper/rocky-lvroot  # For ext4
# OR
sudo xfs_growfs /dev/mapper/rocky-lvroot  # For xfs
```

### 5. Prevent Future Issues

**Set up log rotation:**
```bash
# Edit PostgreSQL log rotation
sudo vi /etc/logrotate.d/postgresql
```

**Monitor disk space:**
```bash
# Add to crontab
echo "0 * * * * df -h | grep -E '100%|9[0-9]%' && echo 'WARNING: Disk space low' | mail -s 'Disk Alert' admin@example.com" | sudo crontab -
```

## Why This Caused Your Crashes

1. **WAL writes fail** → PostgreSQL cannot commit transactions
2. **Temp file creation fails** → Queries that need temp files crash
3. **Relation-cache writes fail** → You see those warnings
4. **Process crashes** → PostgreSQL backend processes die
5. **Connection termination** → All connections get killed

## After Freeing Space

1. Restart PostgreSQL to ensure it's healthy:
   ```bash
   sudo systemctl restart postgresql
   ```

2. Verify PostgreSQL is running:
   ```bash
   sudo systemctl status postgresql
   sudo -u postgres psql -c "SELECT version();"
   ```

3. Check your DenoKV service:
   ```bash
   sudo systemctl status denokv
   sudo journalctl -u denokv -n 50
   ```

## Prevention

1. **Set up disk monitoring alerts**
2. **Configure log rotation for PostgreSQL**
3. **Regular cleanup of old logs**
4. **Consider expanding disk or adding storage**
