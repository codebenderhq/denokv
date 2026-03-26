// Copyright 2023 rawkakani. All rights reserved. MIT license.

use async_trait::async_trait;
use chrono::Utc;
use deadpool_postgres::Pool;
use deno_error::JsErrorBox;
use denokv_proto::QueueMessageHandle;
use uuid::Uuid;

use crate::error::{PostgresError, PostgresResult};

/// PostgreSQL message handle for queue operations
pub struct PostgresMessageHandle {
    pub id: Uuid,
    pub payload: Option<Vec<u8>>,
    pub pool: Pool,
}

impl PostgresMessageHandle {
    /// Finish processing a message.
    ///
    /// On success: remove from queue_running and delete the message.
    /// On failure: apply backoff schedule and requeue, or write
    /// keys_if_undelivered when retries are exhausted (matching SQLite).
    pub async fn finish(&self, success: bool) -> PostgresResult<()> {
        let mut conn = self.pool.get().await?;
        let tx = conn.transaction().await?;
        let id_str = self.id.to_string();

        if success {
            // Remove from running and delete the original message
            tx.execute("DELETE FROM queue_running WHERE message_id = $1", &[&id_str]).await?;
            tx.execute("DELETE FROM queue_messages WHERE id = $1", &[&id_str]).await?;
        } else {
            // Fetch the message metadata for requeue decisions
            let row = tx.query_opt(
                r#"SELECT payload, deadline, keys_if_undelivered, backoff_schedule, retry_count
                   FROM queue_messages WHERE id = $1"#,
                &[&id_str],
            ).await?;

            if let Some(row) = row {
                let payload: Vec<u8> = row.get("payload");
                let keys_json: String = row.get("keys_if_undelivered");
                let backoff_json: Option<String> = row.get("backoff_schedule");
                let retry_count: i32 = row.get("retry_count");

                let backoff_schedule: Vec<u64> = backoff_json
                    .and_then(|j| serde_json::from_str(&j).ok())
                    .unwrap_or_default();

                // Remove from running table
                tx.execute("DELETE FROM queue_running WHERE message_id = $1", &[&id_str]).await?;

                if !backoff_schedule.is_empty() {
                    // Requeue with next backoff delay
                    let delay_ms = backoff_schedule[0] as i64;
                    let new_deadline = Utc::now().timestamp_millis() + delay_ms;
                    let remaining_backoff = serde_json::to_string(&backoff_schedule[1..])
                        .unwrap_or_else(|_| "[]".to_string());

                    tx.execute(
                        r#"UPDATE queue_messages
                           SET deadline = $1, backoff_schedule = $2, retry_count = $3
                           WHERE id = $4"#,
                        &[&new_deadline, &remaining_backoff, &(retry_count + 1), &id_str],
                    ).await?;
                } else {
                    // No more retries — handle keys_if_undelivered, then delete
                    let keys_if_undelivered: Vec<Vec<u8>> = serde_json::from_str(&keys_json)
                        .unwrap_or_default();

                    if !keys_if_undelivered.is_empty() {
                        // Write a tombstone value to each key so watchers are notified
                        for key in &keys_if_undelivered {
                            let empty_value: Vec<u8> = Vec::new();
                            tx.execute(
                                r#"INSERT INTO kv_store (key, value, value_encoding, versionstamp, updated_at)
                                   VALUES ($1, $2, 1, $3, NOW())
                                   ON CONFLICT (key) DO UPDATE SET
                                       value = EXCLUDED.value,
                                       value_encoding = EXCLUDED.value_encoding,
                                       versionstamp = EXCLUDED.versionstamp,
                                       updated_at = NOW()"#,
                                &[key, &empty_value, &payload.as_slice()],
                            ).await?;
                        }
                    }

                    // Delete the exhausted message
                    tx.execute("DELETE FROM queue_messages WHERE id = $1", &[&id_str]).await?;
                }
            } else {
                // Message was already removed — just clean up running entry
                tx.execute("DELETE FROM queue_running WHERE message_id = $1", &[&id_str]).await?;
            }
        }

        tx.commit().await?;
        Ok(())
    }

    /// Take the payload from the message
    pub async fn take_payload(&mut self) -> PostgresResult<Vec<u8>> {
        self.payload.take()
            .ok_or_else(|| PostgresError::InvalidData("Payload already taken".to_string()))
    }
}

#[async_trait]
impl QueueMessageHandle for PostgresMessageHandle {
    async fn finish(&self, success: bool) -> Result<(), JsErrorBox> {
        self.finish(success).await.map_err(JsErrorBox::from_err)
    }

    async fn take_payload(&mut self) -> Result<Vec<u8>, JsErrorBox> {
        self.take_payload().await.map_err(JsErrorBox::from_err)
    }
}
