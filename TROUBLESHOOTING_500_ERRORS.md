# Troubleshooting 500 Internal Server Errors on `/v2/atomic_write`

## Overview

When the `/v2/atomic_write` endpoint returns a 500 Internal Server Error, it means the server encountered an unexpected error while processing the atomic write operation. The error message "An internal server error occurred." is generic, but the actual error details are logged by the server.

## How Errors Are Handled

Looking at the code in `denokv/main.rs`, the following error types are converted to `InternalServerError` (500 status):

1. **SQLite Errors** (`SqliteBackendError::SqliteError`):
   - Database corruption
   - Disk I/O errors (disk full, permissions)
   - Locking issues (database locked, timeout)
   - Transaction failures
   - SQL syntax errors (shouldn't happen in normal operation)

2. **Generic Backend Errors** (`SqliteBackendError::GenericError`):
   - Any other unexpected backend error

3. **Postgres Errors** (if using Postgres backend):
   - Connection pool exhaustion
   - Transaction failures
   - Database connection errors
   - Query execution errors

4. **JavaScript Error Box Errors** (`JsErrorBox`):
   - Any error from the JS error handling layer

## How to Diagnose

### 1. Check Server Logs

The server logs detailed error information using `log::error!()`. To see these logs:

**If running directly:**
```bash
RUST_LOG=error ./denokv --sqlite-path /data/denokv.sqlite serve --access-token <token>
```

**If running in Docker:**
```bash
docker logs <container-id> 2>&1 | grep -i error
```

**For more detailed logging:**
```bash
RUST_LOG=debug ./denokv --sqlite-path /data/denokv.sqlite serve --access-token <token>
```

The logs will show messages like:
- `Sqlite error: <detailed error message>`
- `Generic error: <detailed error message>`

### 2. Common Causes and Solutions

#### A. Database Locking Issues (SQLite)

**Symptoms:**
- Intermittent 500 errors
- Errors occur under high concurrency
- Logs show "database is locked" or timeout errors

**Solutions:**
- Check if multiple processes are accessing the database
- Ensure the database file has proper permissions
- Consider using WAL mode (should be enabled by default)
- Increase SQLite timeout if needed
- Check for long-running transactions

#### B. Disk Space Issues

**Symptoms:**
- Consistent 500 errors
- Logs show "disk I/O error" or "no space left on device"

**Solutions:**
```bash
# Check disk space
df -h /data

# Check database file size
ls -lh /data/denokv.sqlite
```

- Free up disk space
- Consider database cleanup/compaction
- Move database to a location with more space

#### C. Database Corruption

**Symptoms:**
- Consistent 500 errors
- Logs show "database disk image is malformed" or similar

**Solutions:**
```bash
# Check database integrity
sqlite3 /data/denokv.sqlite "PRAGMA integrity_check;"

# If corrupted, restore from backup
```

- Restore from a known good backup
- If no backup, attempt recovery using SQLite tools

#### D. Connection Pool Exhaustion (Postgres)

**Symptoms:**
- Errors under high load
- Logs show connection timeout or pool exhaustion

**Solutions:**
- Increase connection pool size in Postgres configuration
- Check for connection leaks
- Monitor active connections: `SELECT count(*) FROM pg_stat_activity;`

#### E. Transaction Failures

**Symptoms:**
- Intermittent errors
- May occur with specific operations

**Solutions:**
- Check for constraint violations
- Verify data types match expected formats
- Check for deadlocks (Postgres)

#### F. Resource Exhaustion

**Symptoms:**
- Errors under high load
- System resource limits reached

**Solutions:**
```bash
# Check system resources
free -h
ulimit -a
```

- Increase system limits
- Add more memory/CPU
- Optimize queries/operations

### 3. Enable Debug Logging

To get more detailed information about what's happening:

```bash
RUST_LOG=debug ./denokv --sqlite-path /data/denokv.sqlite serve --access-token <token>
```

This will show:
- Detailed error stack traces
- Transaction details
- Database operation logs

### 4. Check Database Health

**For SQLite:**
```bash
sqlite3 /data/denokv.sqlite <<EOF
PRAGMA integrity_check;
PRAGMA quick_check;
.schema
.tables
EOF
```

**For Postgres:**
```sql
-- Check connection count
SELECT count(*) FROM pg_stat_activity;

-- Check for locks
SELECT * FROM pg_locks WHERE NOT granted;

-- Check database size
SELECT pg_size_pretty(pg_database_size(current_database()));
```

### 5. Monitor System Resources

```bash
# CPU and memory
top

# Disk I/O
iostat -x 1

# Network connections
netstat -an | grep 4512
```

## Prevention

1. **Regular Backups**: Ensure you have regular backups of your database
2. **Monitoring**: Set up monitoring for:
   - Disk space
   - Database size
   - Error rates
   - Connection counts
3. **Resource Limits**: Ensure adequate resources (disk, memory, CPU)
4. **Database Maintenance**: Periodically run VACUUM (SQLite) or VACUUM ANALYZE (Postgres)

## Getting Help

When reporting issues, include:
1. Full error logs with `RUST_LOG=error` or `RUST_LOG=debug`
2. Database backend (SQLite or Postgres)
3. Database size and disk space
4. System resources (CPU, memory)
5. Concurrency level (how many concurrent requests)
6. Steps to reproduce

## Code References

- Error handling: `denokv/main.rs:690-711` (SqliteBackendError conversion)
- Endpoint handler: `denokv/main.rs:543-552` (atomic_write_endpoint)
- SQLite implementation: `sqlite/backend.rs:341-500` (atomic_write_once)
- Postgres implementation: `postgres/backend.rs:170-268` (atomic_write)
