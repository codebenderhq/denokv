// Copyright 2023 rawkakani. All rights reserved. MIT license.

use async_trait::async_trait;
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
    /// Finish processing a message
    pub async fn finish(&self, success: bool) -> PostgresResult<()> {
        let conn = self.pool.get().await?;

        if success {
            // Remove from running table and delete the message
            conn.execute(
                "DELETE FROM queue_messages WHERE id = $1",
                &[&self.id.to_string()],
            ).await?;
        } else {
            // Remove from running table but keep the message for retry
            conn.execute(
                "DELETE FROM queue_running WHERE message_id = $1",
                &[&self.id.to_string()],
            ).await?;
        }

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