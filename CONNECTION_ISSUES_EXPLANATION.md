# Why PostgreSQL Connection Issues Are Happening

## Summary of the Issue

Based on your logs from Dec 28, 2025, you're experiencing PostgreSQL connection failures that occur when:

1. **PostgreSQL server process crashes or restarts**
2. **Connection pool tries to use dead connections**
3. **PostgreSQL cannot create relation-cache files**

## Root Causes

### 1. **PostgreSQL Server Process Crash** (Primary Cause)

**Log Evidence:**
```
WARNING: terminating connection because of crash of another server process
```

**What This Means:**
- Another PostgreSQL backend process crashed (not your DenoKV process)
- PostgreSQL automatically terminates all connections when a backend process crashes
- This is a **safety mechanism** to prevent data corruption

**Why This Happens:**
- **Memory issues**: PostgreSQL process ran out of memory (OOM killer)
- **Disk I/O errors**: Storage problems causing process crashes
- **PostgreSQL bugs**: Rare but possible in certain versions
- **Resource exhaustion**: CPU/memory limits reached
- **System instability**: Hardware or OS issues

**How to Diagnose:**
```bash
# Check PostgreSQL logs for crash details
sudo tail -100 /var/log/postgresql/postgresql-*.log | grep -i "crash\|fatal\|panic"

# Check system logs for OOM kills
sudo dmesg | grep -i "out of memory\|killed process"

# Check PostgreSQL process status
sudo systemctl status postgresql
```

### 2. **Connection Pool Using Dead Connections**

**Log Evidence:**
```
WARN deadpool.postgres] Connection error: connection closed
INFO deadpool.postgres] Connection could not be recycled: Connection closed
```

**What This Means:**
- The connection pool (deadpool) had connections that were **already dead**
- When PostgreSQL crashed, it closed all connections
- deadpool tried to reuse these dead connections
- deadpool detected they were closed and tried to recycle them
- But recycling failed because the connection was already terminated

**Why This Happens:**
- **No connection health checks**: The pool doesn't validate connections before use
- **Stale connections**: Connections remain in pool after server crash
- **No automatic recovery**: Pool doesn't automatically recreate dead connections

**The Fix (Already Implemented):**
- Added connection validation before use (`SELECT 1` query)
- Added retry logic with exponential backoff
- Added automatic connection recreation on failure

### 3. **Relation-Cache Initialization File Errors**

**Log Evidence:**
```
WARNING: could not create relation-cache initialization file "base/16385/pg_internal.init"
WARNING: could not create relation-cache initialization file "global/pg_internal.init"
```

**What This Means:**
- PostgreSQL tries to create cache files for faster query planning
- These files are **optional performance optimizations**
- Failure to create them is **not critical** - PostgreSQL works without them
- This is a **warning**, not an error

**Why This Happens:**
- **File system permissions**: PostgreSQL user doesn't have write access
- **Disk space issues**: No space to create cache files
- **Read-only file system**: Database directory mounted read-only
- **PostgreSQL recovery mode**: Server in recovery and can't write cache

**Impact:**
- **Minimal**: Queries work but may be slightly slower
- **No data loss**: This doesn't affect data integrity
- **Can be ignored**: This is a non-critical warning

## Why It Happened on Dec 28 (11 Days After Startup)

The server started successfully on **Dec 17** and ran fine for 11 days. Then on **Dec 28**, you saw these errors. This suggests:

1. **PostgreSQL server restarted/crashed** on Dec 28
2. **All existing connections were terminated** by PostgreSQL
3. **Connection pool had stale connections** that were no longer valid
4. **Application tried to use dead connections** → errors occurred

## What Happens Now (After Our Fixes)

With the improvements we've implemented:

1. **Connection Validation**: Every connection is tested with `SELECT 1` before use
2. **Automatic Retry**: Transient errors trigger automatic retries (up to 3 attempts)
3. **Exponential Backoff**: Retries wait progressively longer (100ms, 200ms, 400ms)
4. **Better Error Detection**: We detect transient vs permanent errors
5. **Connection Recreation**: Dead connections are automatically replaced

**Result**: The application will now automatically recover from PostgreSQL crashes without user intervention.

## Recommendations

### 1. **Investigate PostgreSQL Crashes**

Find out why PostgreSQL crashed:

```bash
# Check PostgreSQL error log
sudo tail -200 /var/log/postgresql/postgresql-*.log

# Check for OOM kills
sudo dmesg | grep -i "killed process.*postgres"

# Check system resources
free -h
df -h
```

### 2. **Monitor PostgreSQL Health**

Set up monitoring for:
- PostgreSQL process crashes
- Memory usage
- Disk space
- Connection counts

### 3. **Configure PostgreSQL for Stability**

```sql
-- Increase shared_buffers if you have enough RAM
ALTER SYSTEM SET shared_buffers = '256MB';

-- Set connection limits
ALTER SYSTEM SET max_connections = 100;

-- Enable connection timeouts
ALTER SYSTEM SET idle_in_transaction_session_timeout = '10min';
```

### 4. **Set Up Automatic Restart**

Ensure PostgreSQL auto-restarts on crash:

```bash
# For systemd
sudo systemctl enable postgresql
sudo systemctl edit postgresql
# Add:
# [Service]
# Restart=always
# RestartSec=5
```

### 5. **Fix Relation-Cache Warnings (Optional)**

If you want to eliminate the warnings:

```bash
# Check PostgreSQL data directory permissions
sudo ls -la /var/lib/postgresql/*/base/

# Ensure PostgreSQL user can write
sudo chown -R postgres:postgres /var/lib/postgresql/
sudo chmod 700 /var/lib/postgresql/*/base/
```

## Conclusion

**The connection issues are caused by:**
1. PostgreSQL server process crashing (primary)
2. Connection pool not detecting dead connections (secondary - now fixed)
3. PostgreSQL cache file warnings (cosmetic - can be ignored)

**The application will now handle these gracefully** with automatic retries and connection recovery. However, you should still investigate why PostgreSQL is crashing to prevent future issues.
