# Postgres 500 Error Diagnosis Guide

## What I Found

After reviewing the Postgres implementation, here's what could be causing your 500 errors:

### Error Flow
1. Postgres errors occur in `postgres/backend.rs:atomic_write()`
2. Errors are converted to `JsErrorBox` in `postgres/lib.rs:109-113`
3. `JsErrorBox` → `ApiError::InternalServerError` in `denokv/main.rs:754-758`
4. Returns HTTP 500 with generic message

**⚠️ Previously**: Errors were NOT logged, making debugging impossible
**✅ Now Fixed**: Errors are now logged with `log::error!()` before returning 500

## Immediate Actions to Take

### 1. Check Server Logs (MOST IMPORTANT)

The server now logs detailed error messages. Check your server logs:

```bash
# If running directly
RUST_LOG=error ./denokv --postgres-url <url> serve --access-token <token>

# If running in Docker
docker logs <container-id> 2>&1 | grep -i error

# For more detail
RUST_LOG=debug ./denokv --postgres-url <url> serve --access-token <token>
```

Look for messages like:
- `Database error: <error details>`
- `atomic_write failed: <error details>`

### 2. Check Postgres Server Logs

```bash
# Find Postgres log location
sudo -u postgres psql -c "SHOW log_directory;"
sudo -u postgres psql -c "SHOW log_filename;"

# View recent errors
sudo tail -f /var/log/postgresql/postgresql-*.log | grep -i error
```

### 3. Check Connection Pool Status

```sql
-- Connect to your database
psql -h <host> -U <user> -d <database>

-- Check active connections
SELECT count(*) as active_connections,
       count(*) FILTER (WHERE state = 'active') as active_queries,
       count(*) FILTER (WHERE state = 'idle in transaction') as idle_in_transaction
FROM pg_stat_activity 
WHERE datname = current_database();

-- Check max connections
SHOW max_connections;
```

**If you see many `idle in transaction` connections**, you have a connection leak.

### 4. Check for Deadlocks

```sql
-- Check for locks
SELECT 
    locktype, 
    relation::regclass, 
    mode, 
    granted,
    pid,
    pg_stat_activity.query
FROM pg_locks
JOIN pg_stat_activity ON pg_locks.pid = pg_stat_activity.pid
WHERE NOT granted
ORDER BY pid;
```

### 5. Check Transaction Timeouts

```sql
-- Check timeout settings
SHOW statement_timeout;
SHOW idle_in_transaction_session_timeout;
SHOW lock_timeout;
```

### 6. Verify Schema is Correct

```sql
-- Check if tables exist
SELECT tablename FROM pg_tables 
WHERE schemaname = 'public' 
AND tablename IN ('kv_store', 'queue_messages', 'queue_running');

-- Check table structure
\d kv_store
\d queue_messages
\d queue_running

-- Check indexes
\di
```

## Most Likely Causes (Based on Code Review)

### 1. **Connection Pool Exhaustion** (Most Likely)
- **Symptom**: Errors increase with load
- **Check**: Active connections vs. pool size
- **Fix**: Increase `max_connections` in PostgresConfig or check for leaks

### 2. **Transaction Deadlocks**
- **Symptom**: Intermittent errors, especially with concurrent writes
- **Check**: `pg_locks` table for blocking queries
- **Fix**: Add retry logic or optimize transaction scope

### 3. **Transaction Timeout**
- **Symptom**: Errors after specific duration
- **Check**: `statement_timeout` and `idle_in_transaction_session_timeout`
- **Fix**: Increase timeouts or optimize slow queries

### 4. **Schema Issues**
- **Symptom**: Consistent errors on specific operations
- **Check**: Table existence and structure
- **Fix**: Ensure `initialize_schema()` was called successfully

### 5. **Connection Failures**
- **Symptom**: Intermittent "connection refused" or "connection reset"
- **Check**: Postgres server status, network connectivity
- **Fix**: Verify Postgres is running, check firewall, verify credentials

## Code Locations to Review

1. **Atomic Write Implementation**: `postgres/backend.rs:170-271`
   - Transaction creation: line 175
   - Checks: lines 178-193
   - Mutations: lines 200-251
   - Enqueues: lines 255-266
   - Commit: line 268

2. **Error Handling**: `postgres/lib.rs:105-116`
   - Connection acquisition: line 109
   - Error conversion: lines 110, 113

3. **Error Types**: `postgres/error.rs`
   - All error variants and their conversions

## Quick Diagnostic Script

Run this to get a comprehensive view:

```bash
#!/bin/bash
echo "=== Connection Pool Status ==="
psql -h <host> -U <user> -d <database> -c "
SELECT 
    count(*) as total_connections,
    count(*) FILTER (WHERE state = 'active') as active,
    count(*) FILTER (WHERE state = 'idle') as idle,
    count(*) FILTER (WHERE state = 'idle in transaction') as idle_in_tx
FROM pg_stat_activity 
WHERE datname = current_database();
"

echo -e "\n=== Locks ==="
psql -h <host> -U <user> -d <database> -c "
SELECT count(*) as blocked_locks 
FROM pg_locks 
WHERE NOT granted;
"

echo -e "\n=== Table Status ==="
psql -h <host> -U <user> -d <database> -c "
SELECT tablename, 
       pg_size_pretty(pg_total_relation_size(quote_ident(tablename)::regclass)) as size
FROM pg_tables 
WHERE schemaname = 'public' 
AND tablename IN ('kv_store', 'queue_messages', 'queue_running');
"

echo -e "\n=== Recent Errors (from Postgres logs) ==="
sudo tail -100 /var/log/postgresql/postgresql-*.log | grep -i error | tail -10
```

## Next Steps

1. **Enable error logging** on your server (already done in code)
2. **Check server logs** for the actual error messages
3. **Run diagnostic queries** above to identify the issue
4. **Check Postgres server logs** for database-level errors
5. **Monitor connection pool** usage over time

## What Was Changed

I've improved error logging in the codebase:
- Added `log::error!()` in `atomic_write_endpoint` to log errors before conversion
- Added `log::error!()` in `From<JsErrorBox>` implementation to log all database errors

This means you'll now see detailed error messages in your server logs, which will tell you exactly what's failing.
