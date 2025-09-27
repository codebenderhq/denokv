// Copyright 2023 rawkakani. All rights reserved. MIT license.

mod backend;
mod config;
mod error;
mod message_handle;
mod notifier;

use std::collections::HashMap;
use std::pin::Pin;
use std::sync::Arc;

use async_stream::try_stream;
use async_trait::async_trait;
use chrono::DateTime;
use chrono::Utc;
use deadpool_postgres::{Config, Pool, Runtime, Manager};
use deno_error::JsErrorBox;
use denokv_proto::{
    AtomicWrite, CommitResult, Database, KvEntry, KvValue, QueueMessageHandle,
    ReadRange, ReadRangeOutput, SnapshotReadOptions, Versionstamp, WatchKeyOutput,
};
use futures::Stream;
use tokio::sync::{watch, RwLock};
use tokio_postgres::NoTls;

pub use config::PostgresConfig;
pub use error::{PostgresError, PostgresResult};

use backend::PostgresBackend;
use message_handle::PostgresMessageHandle;
use notifier::PostgresNotifier;

/// PostgreSQL implementation of the DenoKV Database trait
#[derive(Clone)]
pub struct Postgres {
    pool: Pool,
    notifier: PostgresNotifier,
    backend: Arc<PostgresBackend>,
}

impl Postgres {
    /// Create a new PostgreSQL database instance
    pub async fn new(config: PostgresConfig) -> PostgresResult<Self> {
        // Parse the connection string
        let pg_config = config.url.parse::<tokio_postgres::Config>()
            .map_err(|e| PostgresError::InvalidConfig(format!("Invalid PostgreSQL URL: {}", e)))?;

        // Create deadpool manager
        let manager = Manager::new(pg_config, NoTls);
        
        // Create the connection pool
        let pool = Pool::builder(manager)
            .max_size(config.max_connections)
            .build()
            .map_err(|e| PostgresError::ConnectionFailed(format!("Failed to create connection pool: {}", e)))?;

        // Test the connection
        let conn = pool.get().await
            .map_err(|e| PostgresError::ConnectionFailed(format!("Failed to get connection: {}", e)))?;

        // Initialize the database schema
        let backend = Arc::new(PostgresBackend::new(pool.clone()));
        backend.initialize_schema().await?;

        // Create notifier
        let notifier = PostgresNotifier::new();

        Ok(Postgres {
            pool,
            notifier,
            backend,
        })
    }

    /// Get a connection from the pool
    async fn get_connection(&self) -> PostgresResult<deadpool_postgres::Client> {
        self.pool.get().await
            .map_err(|e| PostgresError::ConnectionFailed(format!("Failed to get connection: {}", e)))
    }
}

#[async_trait]
impl Database for Postgres {
    type QMH = PostgresMessageHandle;

    async fn snapshot_read(
        &self,
        requests: Vec<ReadRange>,
        options: SnapshotReadOptions,
    ) -> Result<Vec<ReadRangeOutput>, JsErrorBox> {
        let conn = self.get_connection().await
            .map_err(JsErrorBox::from_err)?;

        let mut outputs = Vec::new();
        for request in requests {
            let entries = self.backend.read_range(&conn, &request).await
                .map_err(JsErrorBox::from_err)?;
            outputs.push(ReadRangeOutput { entries });
        }

        Ok(outputs)
    }

    async fn atomic_write(
        &self,
        write: AtomicWrite,
    ) -> Result<Option<CommitResult>, JsErrorBox> {
        let mut conn = self.get_connection().await
            .map_err(JsErrorBox::from_err)?;

        let result = self.backend.atomic_write(&mut conn, write).await
            .map_err(JsErrorBox::from_err)?;

        Ok(result)
    }

    async fn dequeue_next_message(&self) -> Result<Option<Self::QMH>, JsErrorBox> {
        let mut conn = self.get_connection().await
            .map_err(JsErrorBox::from_err)?;

        let message_handle = self.backend.dequeue_next_message(&mut conn).await
            .map_err(JsErrorBox::from_err)?;

        Ok(message_handle)
    }

    fn watch(&self, keys: Vec<Vec<u8>>) -> Pin<Box<dyn Stream<Item = Result<Vec<WatchKeyOutput>, JsErrorBox>> + Send>> {
        let backend = self.backend.clone();
        let notifier = self.notifier.clone();

        let stream = try_stream! {
            // Subscribe to key changes
            let mut subscriptions = Vec::new();
            for key in &keys {
                subscriptions.push(notifier.subscribe(key.clone()));
            }

            loop {
                // Get current values
                let conn = backend.pool.get().await
                    .map_err(|e| JsErrorBox::generic(format!("Failed to get connection: {}", e)))?;

                let mut outputs = Vec::new();
                for key in &keys {
                    let request = ReadRange {
                        start: key.clone(),
                        end: key.iter().copied().chain(Some(0)).collect(),
                        limit: std::num::NonZeroU32::new(1).unwrap(),
                        reverse: false,
                    };

                    let entries = backend.read_range(&conn, &request).await
                        .map_err(JsErrorBox::from_err)?;
                    
                    let entry = entries.into_iter().next();
                    outputs.push(WatchKeyOutput::Changed { entry });
                }

                yield outputs;

                // Wait for changes
                for subscription in &mut subscriptions {
                    subscription.wait_for_change().await;
                }
            }
        };

        Box::pin(stream)
    }

    fn close(&self) {
        // PostgreSQL connections are managed by the pool
        // No explicit close needed
    }
}