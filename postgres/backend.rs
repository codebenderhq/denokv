// Copyright 2023 rawkakani. All rights reserved. MIT license.

use std::collections::HashMap;
use std::num::NonZeroU32;

use chrono::{DateTime, Utc};
use deadpool_postgres::{Client, Pool};
use denokv_proto::{
    AtomicWrite, Check, CommitResult, Enqueue, KvEntry, KvValue, Mutation, MutationKind,
    ReadRange, Versionstamp,
};
use rand::RngCore;
use serde_json::Value;
use tokio_postgres::Row;

use crate::error::{PostgresError, PostgresResult};
use crate::message_handle::PostgresMessageHandle;

/// PostgreSQL backend implementation
pub struct PostgresBackend {
    pub pool: Pool,
}

impl PostgresBackend {
    pub fn new(pool: Pool) -> Self {
        Self { pool }
    }

    /// Initialize the database schema
    pub async fn initialize_schema(&self) -> PostgresResult<()> {
        let conn = self.pool.get().await?;


        // Create the main KV table
        conn.execute(
            r#"
            CREATE TABLE IF NOT EXISTS kv_store (
                key BYTEA PRIMARY KEY,
                value BYTEA NOT NULL,
                value_encoding INTEGER NOT NULL,
                versionstamp BYTEA NOT NULL,
                created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
                updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
                expires_at BIGINT
            )
            "#,
            &[],
        ).await?;

        // Create indexes for performance
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_kv_versionstamp ON kv_store(versionstamp)",
            &[],
        ).await?;

        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_kv_expires_at ON kv_store(expires_at) WHERE expires_at IS NOT NULL",
            &[],
        ).await?;

        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_kv_updated_at ON kv_store(updated_at)",
            &[],
        ).await?;

        // Create queue tables
        conn.execute(
            r#"
            CREATE TABLE IF NOT EXISTS queue_messages (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                payload BYTEA NOT NULL,
                deadline BIGINT NOT NULL,
                keys_if_undelivered BYTEA[] NOT NULL,
                backoff_schedule INTEGER[],
                created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
                retry_count INTEGER DEFAULT 0
            )
            "#,
            &[],
        ).await?;

        conn.execute(
            r#"
            CREATE TABLE IF NOT EXISTS queue_running (
                message_id UUID PRIMARY KEY REFERENCES queue_messages(id),
                deadline BIGINT NOT NULL,
                started_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
                updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
            )
            "#,
            &[],
        ).await?;

        // Create indexes for queue
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_queue_deadline ON queue_messages(deadline)",
            &[],
        ).await?;

        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_queue_running_deadline ON queue_running(deadline)",
            &[],
        ).await?;

        Ok(())
    }

    /// Read a range of keys
    pub async fn read_range(
        &self,
        conn: &Client,
        request: &ReadRange,
    ) -> PostgresResult<Vec<KvEntry>> {
        let query = if request.reverse {
            r#"
            SELECT key, value, value_encoding, versionstamp
            FROM kv_store
            WHERE key >= $1 AND key < $2
            ORDER BY key DESC
            LIMIT $3
            "#
        } else {
            r#"
            SELECT key, value, value_encoding, versionstamp
            FROM kv_store
            WHERE key >= $1 AND key < $2
            ORDER BY key ASC
            LIMIT $3
            "#
        };

        let rows = conn.query(query, &[
            &request.start,
            &request.end,
            &(request.limit.get() as i64),
        ]).await?;

        let mut entries = Vec::new();
        for row in rows {
            let key: Vec<u8> = row.get("key");
            let value: Vec<u8> = row.get("value");
            let encoding: i32 = row.get("value_encoding");
            let versionstamp: Vec<u8> = row.get("versionstamp");

            let kv_value = match encoding {
                1 => KvValue::V8(value),
                2 => {
                    let mut buf = [0; 8];
                    buf.copy_from_slice(&value);
                    KvValue::U64(u64::from_le_bytes(buf))
                }
                3 => KvValue::Bytes(value),
                _ => return Err(PostgresError::InvalidData(format!("Unknown encoding: {}", encoding))),
            };

            let mut versionstamp_array = [0; 10];
            versionstamp_array.copy_from_slice(&versionstamp);

            entries.push(KvEntry {
                key,
                value: kv_value,
                versionstamp: versionstamp_array,
            });
        }

        Ok(entries)
    }

    /// Perform an atomic write operation
    pub async fn atomic_write(
        &self,
        conn: &mut Client,
        write: AtomicWrite,
    ) -> PostgresResult<Option<CommitResult>> {
        let tx = conn.transaction().await?;

        // Perform checks
        for check in &write.checks {
            let row = tx.query_opt(
                "SELECT versionstamp FROM kv_store WHERE key = $1",
                &[&check.key],
            ).await?;

            let current_versionstamp = row.map(|r| r.get::<_, Vec<u8>>("versionstamp"));
            
            if let Some(expected) = &check.versionstamp {
                if current_versionstamp.as_ref().map(|v| v.as_slice()) != Some(expected.as_slice()) {
                    return Ok(None); // Check failed
                }
            } else if current_versionstamp.is_some() {
                return Ok(None); // Expected key to not exist, but it does
            }
        }

        // Generate new versionstamp
        let mut versionstamp = [0; 10];
        rand::thread_rng().fill_bytes(&mut versionstamp);

        // Perform mutations
        for mutation in &write.mutations {
            match &mutation.kind {
                MutationKind::Set(value) => {
                    let (value_bytes, encoding) = self.encode_value(value);
                    let expires_at = mutation.expire_at;

                    tx.execute(
                        r#"
                        INSERT INTO kv_store (key, value, value_encoding, versionstamp, expires_at, updated_at)
                        VALUES ($1, $2, $3, $4, $5, NOW())
                        ON CONFLICT (key) DO UPDATE SET
                            value = EXCLUDED.value,
                            value_encoding = EXCLUDED.value_encoding,
                            versionstamp = EXCLUDED.versionstamp,
                            expires_at = EXCLUDED.expires_at,
                            updated_at = NOW()
                        "#,
                        &[&mutation.key, &value_bytes, &(encoding as i32), &versionstamp.as_slice(), &expires_at.map(|dt| dt.timestamp_millis())],
                    ).await?;
                }
                MutationKind::Delete => {
                    tx.execute(
                        "DELETE FROM kv_store WHERE key = $1",
                        &[&mutation.key],
                    ).await?;
                }
                MutationKind::Sum { value, .. } => {
                    self.handle_sum_mutation(&tx, &mutation.key, value, &versionstamp).await?;
                }
                MutationKind::Min(value) => {
                    self.handle_min_mutation(&tx, &mutation.key, value, &versionstamp).await?;
                }
                MutationKind::Max(value) => {
                    self.handle_max_mutation(&tx, &mutation.key, value, &versionstamp).await?;
                }
                MutationKind::SetSuffixVersionstampedKey(value) => {
                    // This is a special case - we need to generate a new key with the versionstamp
                    let mut new_key = mutation.key.clone();
                    new_key.extend_from_slice(&versionstamp);
                    
                    let (value_bytes, encoding) = self.encode_value(value);
                    let expires_at = mutation.expire_at;

                    tx.execute(
                        r#"
                        INSERT INTO kv_store (key, value, value_encoding, versionstamp, expires_at, updated_at)
                        VALUES ($1, $2, $3, $4, $5, NOW())
                        "#,
                        &[&new_key, &value_bytes, &(encoding as i32), &versionstamp.as_slice(), &expires_at.map(|dt| dt.timestamp_millis())],
                    ).await?;
                }
            }
        }

        // Handle enqueues
        for enqueue in &write.enqueues {
            let keys_json = serde_json::to_string(&enqueue.keys_if_undelivered)?;
            let backoff_json = enqueue.backoff_schedule.as_ref().map(|b| serde_json::to_string(b)).transpose()?;

            tx.execute(
                r#"
                INSERT INTO queue_messages (payload, deadline, keys_if_undelivered, backoff_schedule)
                VALUES ($1, $2, $3, $4)
                "#,
                &[&enqueue.payload, &enqueue.deadline.timestamp_millis(), &keys_json, &backoff_json],
            ).await?;
        }

        tx.commit().await?;

        Ok(Some(CommitResult { versionstamp }))
    }

    /// Handle sum mutation
    async fn handle_sum_mutation(
        &self,
        tx: &tokio_postgres::Transaction<'_>,
        key: &[u8],
        value: &KvValue,
        versionstamp: &Versionstamp,
    ) -> PostgresResult<()> {
        let (value_bytes, encoding) = self.encode_value(value);
        
        if encoding != 2 {
            return Err(PostgresError::InvalidData("Sum operation only supports U64 values".to_string()));
        }

        let sum_value = match value {
            KvValue::U64(v) => *v as i64,
            _ => return Err(PostgresError::InvalidData("Sum operation only supports U64 values".to_string())),
        };

        // First, try to get the current value
        let current_row = tx.query_opt(
            "SELECT value FROM kv_store WHERE key = $1 AND value_encoding = 2",
            &[&key],
        ).await?;

        let new_value = if let Some(row) = current_row {
            // Parse current value as i64 and add sum_value
            let current_bytes: Vec<u8> = row.get(0);
            if current_bytes.len() == 8 {
                let mut bytes_array = [0u8; 8];
                bytes_array.copy_from_slice(&current_bytes);
                let current_int = i64::from_le_bytes(bytes_array);
                current_int + sum_value
            } else {
                sum_value
            }
        } else {
            sum_value
        };

        let new_value_bytes = new_value.to_le_bytes().to_vec();

        tx.execute(
            r#"
            INSERT INTO kv_store (key, value, value_encoding, versionstamp, updated_at)
            VALUES ($1, $2, 2, $3, NOW())
            ON CONFLICT (key) DO UPDATE SET
                value = $2,
                versionstamp = EXCLUDED.versionstamp,
                updated_at = NOW()
            WHERE kv_store.value_encoding = 2
            "#,
            &[&key, &new_value_bytes, &versionstamp.as_slice()],
        ).await?;

        Ok(())
    }

    /// Handle min mutation
    async fn handle_min_mutation(
        &self,
        tx: &tokio_postgres::Transaction<'_>,
        key: &[u8],
        value: &KvValue,
        versionstamp: &Versionstamp,
    ) -> PostgresResult<()> {
        let (value_bytes, encoding) = self.encode_value(value);
        
        if encoding != 2 {
            return Err(PostgresError::InvalidData("Min operation only supports U64 values".to_string()));
        }

        let min_value = match value {
            KvValue::U64(v) => *v as i64,
            _ => return Err(PostgresError::InvalidData("Min operation only supports U64 values".to_string())),
        };

        // First, try to get the current value
        let current_row = tx.query_opt(
            "SELECT value FROM kv_store WHERE key = $1 AND value_encoding = 2",
            &[&key],
        ).await?;

        let new_value = if let Some(row) = current_row {
            // Parse current value as i64 and take minimum
            let current_bytes: Vec<u8> = row.get(0);
            if current_bytes.len() == 8 {
                let mut bytes_array = [0u8; 8];
                bytes_array.copy_from_slice(&current_bytes);
                let current_int = i64::from_le_bytes(bytes_array);
                current_int.min(min_value)
            } else {
                min_value
            }
        } else {
            min_value
        };

        let new_value_bytes = new_value.to_le_bytes().to_vec();

        tx.execute(
            r#"
            INSERT INTO kv_store (key, value, value_encoding, versionstamp, updated_at)
            VALUES ($1, $2, 2, $3, NOW())
            ON CONFLICT (key) DO UPDATE SET
                value = $2,
                versionstamp = EXCLUDED.versionstamp,
                updated_at = NOW()
            WHERE kv_store.value_encoding = 2
            "#,
            &[&key, &new_value_bytes, &versionstamp.as_slice()],
        ).await?;

        Ok(())
    }

    /// Handle max mutation
    async fn handle_max_mutation(
        &self,
        tx: &tokio_postgres::Transaction<'_>,
        key: &[u8],
        value: &KvValue,
        versionstamp: &Versionstamp,
    ) -> PostgresResult<()> {
        let (value_bytes, encoding) = self.encode_value(value);
        
        if encoding != 2 {
            return Err(PostgresError::InvalidData("Max operation only supports U64 values".to_string()));
        }

        let max_value = match value {
            KvValue::U64(v) => *v as i64,
            _ => return Err(PostgresError::InvalidData("Max operation only supports U64 values".to_string())),
        };

        // First, try to get the current value
        let current_row = tx.query_opt(
            "SELECT value FROM kv_store WHERE key = $1 AND value_encoding = 2",
            &[&key],
        ).await?;

        let new_value = if let Some(row) = current_row {
            // Parse current value as i64 and take maximum
            let current_bytes: Vec<u8> = row.get(0);
            if current_bytes.len() == 8 {
                let mut bytes_array = [0u8; 8];
                bytes_array.copy_from_slice(&current_bytes);
                let current_int = i64::from_le_bytes(bytes_array);
                current_int.max(max_value)
            } else {
                max_value
            }
        } else {
            max_value
        };

        let new_value_bytes = new_value.to_le_bytes().to_vec();

        tx.execute(
            r#"
            INSERT INTO kv_store (key, value, value_encoding, versionstamp, updated_at)
            VALUES ($1, $2, 2, $3, NOW())
            ON CONFLICT (key) DO UPDATE SET
                value = $2,
                versionstamp = EXCLUDED.versionstamp,
                updated_at = NOW()
            WHERE kv_store.value_encoding = 2
            "#,
            &[&key, &new_value_bytes, &versionstamp.as_slice()],
        ).await?;

        Ok(())
    }

    /// Dequeue the next message from the queue
    pub async fn dequeue_next_message(
        &self,
        conn: &mut Client,
    ) -> PostgresResult<Option<PostgresMessageHandle>> {
        let tx = conn.transaction().await?;

        // Find the next message to process
        let row = tx.query_opt(
            r#"
            SELECT id, payload, deadline, keys_if_undelivered, backoff_schedule
            FROM queue_messages
            WHERE deadline <= NOW()
            AND id NOT IN (SELECT message_id FROM queue_running)
            ORDER BY deadline ASC
            LIMIT 1
            FOR UPDATE SKIP LOCKED
            "#,
            &[],
        ).await?;

        if let Some(row) = row {
            let id_str: String = row.get("id");
            let id = uuid::Uuid::parse_str(&id_str)?;
            let payload: Vec<u8> = row.get("payload");
            let deadline_str: String = row.get("deadline");
            let deadline_naive = chrono::NaiveDateTime::parse_from_str(&deadline_str, "%Y-%m-%d %H:%M:%S%.f")
                .map_err(|e| PostgresError::InvalidData(format!("Invalid deadline format: {}", e)))?;
            let deadline: DateTime<Utc> = DateTime::from_naive_utc_and_offset(deadline_naive, Utc);
            let keys_json: String = row.get("keys_if_undelivered");
            let keys_if_undelivered: Vec<Vec<u8>> = serde_json::from_str(&keys_json)?;
            let backoff_json: Option<String> = row.get("backoff_schedule");
            let backoff_schedule: Option<Vec<u32>> = if let Some(json) = backoff_json {
                Some(serde_json::from_str(&json)?)
            } else {
                None
            };

            // Move to running table
            tx.execute(
                r#"
                INSERT INTO queue_running (message_id, deadline, started_at, updated_at)
                VALUES ($1, $2, NOW(), NOW())
                "#,
                &[&id_str, &deadline_str],
            ).await?;

            tx.commit().await?;

            Ok(Some(PostgresMessageHandle {
                id,
                payload: Some(payload),
                pool: self.pool.clone(),
            }))
        } else {
            Ok(None)
        }
    }

    /// Encode a value for storage
    fn encode_value(&self, value: &KvValue) -> (Vec<u8>, i32) {
        match value {
            KvValue::V8(v) => (v.clone(), 1),
            KvValue::Bytes(v) => (v.clone(), 3),
            KvValue::U64(v) => {
                let mut buf = [0; 8];
                buf.copy_from_slice(&v.to_le_bytes());
                (buf.to_vec(), 2)
            }
        }
    }
}