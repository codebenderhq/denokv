# Troubleshooting 500 Errors with Postgres Backend

## Error Flow

When using the Postgres backend, errors flow like this:

1. **PostgresError** (in `postgres/error.rs`) → converted to **JsErrorBox** (in `postgres/lib.rs:109-113`)
2. **JsErrorBox** → converted to **ApiError::InternalServerError** (in `denokv/main.rs:754-758`)
3. **ApiError::InternalServerError** → HTTP 500 response

**⚠️ IMPORTANT**: Unlike SQLite errors, Postgres errors are NOT currently logged before being converted to InternalServerError. This makes debugging harder.

## Common Postgres-Specific Causes

### 1. Connection Pool Exhaustion

**Symptoms:**
- Errors under high load
- Errors become more frequent as load increases
- May see "connection pool timeout" or "no connections available"

**Diagnosis:**
```sql
-- Check active connections
SELECT count(*) FROM pg_stat_activity WHERE datname = 'your_database';

-- Check connection pool settings
SHOW max_connections;
```

**Solutions:**
- Increase `max_connections` in PostgresConfig
- Check for connection leaks (connections not being returned to pool)
- Increase Postgres server's `max_connections` setting
- Use connection pooling at the Postgres level (PgBouncer)

### 2. Transaction Deadlocks

**Symptoms:**
- Intermittent 500 errors
- Errors occur with concurrent writes to same keys
- May see "deadlock detected" in Postgres logs

**Diagnosis:**
```sql
-- Check for locks
SELECT * FROM pg_locks WHERE NOT granted;

-- Check for blocking queries
SELECT 
    blocked_locks.pid AS blocked_pid,
    blocking_locks.pid AS blocking_pid,
    blocked_activity.usename AS blocked_user,
    blocking_activity.usename AS blocking_user,
    blocked_activity.query AS blocked_statement,
    blocking_activity.query AS blocking_statement
FROM pg_catalog.pg_locks blocked_locks
JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
JOIN pg_catalog.pg_locks blocking_locks 
    ON blocking_locks.locktype = blocked_locks.locktype
    AND blocking_locks.database IS NOT DISTINCT FROM blocked_locks.database
    AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
    AND blocking_locks.page IS NOT DISTINCT FROM blocked_locks.page
    AND blocking_locks.tuple IS NOT DISTINCT FROM blocked_locks.tuple
    AND blocking_locks.virtualxid IS NOT DISTINCT FROM blocked_locks.virtualxid
    AND blocking_locks.transactionid IS NOT DISTINCT FROM blocked_locks.transactionid
    AND blocking_locks.classid IS NOT DISTINCT FROM blocked_locks.classid
    AND blocking_locks.objid IS NOT DISTINCT FROM blocked_locks.objid
    AND blocking_locks.objsubid IS NOT DISTINCT FROM blocked_locks.objsubid
    AND blocking_locks.pid != blocked_locks.pid
JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.granted;
```

**Solutions:**
- Ensure transactions are kept short
- Use appropriate isolation levels
- Add retry logic for deadlock errors
- Consider using advisory locks for critical sections

### 3. Transaction Timeout

**Symptoms:**
- Errors after a specific duration
- Long-running transactions fail

**Diagnosis:**
- Check `statement_timeout` setting in PostgresConfig
- Check Postgres server's `statement_timeout` and `idle_in_transaction_session_timeout`

**Solutions:**
- Increase timeout values if needed
- Optimize slow queries
- Break large transactions into smaller ones

### 4. Schema/Table Issues

**Symptoms:**
- Consistent errors on specific operations
- "relation does not exist" or "column does not exist" errors

**Diagnosis:**
```sql
-- Check if tables exist
SELECT tablename FROM pg_tables WHERE schemaname = 'public';

-- Check table structure
\d kv_store
\d queue_messages
\d queue_running

-- Check indexes
\di
```

**Solutions:**
- Ensure schema is initialized: `backend.initialize_schema().await?`
- Check for missing migrations
- Verify table structure matches expected schema

### 5. Data Type Mismatches

**Symptoms:**
- Errors on specific mutations (Sum/Min/Max)
- "invalid input syntax" errors

**Diagnosis:**
- Check value encoding in database:
```sql
SELECT key, value_encoding, length(value) FROM kv_store WHERE key = $1;
```

**Solutions:**
- Ensure mutations match value types (Sum/Min/Max only work with U64)
- Check for data corruption

### 6. Serialization Errors

**Symptoms:**
- Errors when enqueueing messages
- "invalid json" errors

**Diagnosis:**
- Check `keys_if_undelivered` and `backoff_schedule` serialization
- Look for invalid JSON in queue_messages table

**Solutions:**
- Verify enqueue payload structure
- Check JSON serialization of complex types

### 7. Connection Failures

**Symptoms:**
- Intermittent connection errors
- "connection refused" or "connection reset"

**Diagnosis:**
```bash
# Check Postgres is running
pg_isready -h localhost -p 5432

# Check network connectivity
telnet <postgres_host> 5432

# Check Postgres logs
tail -f /var/log/postgresql/postgresql-*.log
```

**Solutions:**
- Verify Postgres server is running
- Check network connectivity
- Verify connection string is correct
- Check firewall rules
- Verify authentication credentials

### 8. Query Performance Issues

**Symptoms:**
- Slow responses leading to timeouts
- Errors under load

**Diagnosis:**
```sql
-- Check for slow queries
SELECT pid, now() - pg_stat_activity.query_start AS duration, query 
FROM pg_stat_activity 
WHERE (now() - pg_stat_activity.query_start) > interval '5 seconds';

-- Check index usage
SELECT schemaname, tablename, indexname, idx_scan, idx_tup_read, idx_tup_fetch
FROM pg_stat_user_indexes
WHERE schemaname = 'public';
```

**Solutions:**
- Add missing indexes
- Analyze and optimize slow queries
- Consider partitioning for large tables
- Update table statistics: `ANALYZE kv_store;`

## How to Get Detailed Error Information

### Enable Debug Logging

```bash
RUST_LOG=debug ./denokv --postgres-url <url> serve --access-token <token>
```

### Check Postgres Server Logs

```bash
# On most Linux systems
tail -f /var/log/postgresql/postgresql-*.log

# Or check the configured log location
SHOW log_directory;
SHOW log_filename;
```

### Enable Postgres Query Logging

Add to `postgresql.conf`:
```
log_statement = 'all'
log_duration = on
log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '
```

### Monitor Active Queries

```sql
-- See what queries are running
SELECT pid, usename, application_name, client_addr, state, query, query_start
FROM pg_stat_activity
WHERE datname = current_database()
AND state != 'idle';
```

## Code Locations to Check

1. **Error Conversion**: `postgres/lib.rs:109-113` - where PostgresError → JsErrorBox
2. **Atomic Write**: `postgres/backend.rs:170-271` - main atomic_write implementation
3. **Transaction Handling**: `postgres/backend.rs:175` - transaction creation
4. **Error Types**: `postgres/error.rs` - all PostgresError variants

## Recommended Improvements

1. **Add Error Logging**: Log Postgres errors before converting to InternalServerError
2. **Add Metrics**: Track connection pool usage, transaction durations, error rates
3. **Add Retry Logic**: Retry on transient errors (deadlocks, connection failures)
4. **Better Error Messages**: Include more context in error responses (for debugging)

## Quick Diagnostic Checklist

- [ ] Check Postgres server is running and accessible
- [ ] Verify connection string is correct
- [ ] Check connection pool size vs. actual connections
- [ ] Review Postgres server logs for errors
- [ ] Check for deadlocks in pg_locks
- [ ] Verify schema is initialized correctly
- [ ] Check table/index existence
- [ ] Monitor query performance
- [ ] Check for long-running transactions
- [ ] Verify data types match expectations
