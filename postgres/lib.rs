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
        let mut pg_config = config.url.parse::<tokio_postgres::Config>()
            .map_err(|e| PostgresError::InvalidConfig(format!("Invalid PostgreSQL URL: {}", e)))?;

        // Set connection timeouts
        pg_config.connect_timeout(std::time::Duration::from_secs(config.connection_timeout));
        pg_config.options(&format!("statement_timeout={}", config.statement_timeout * 1000));

        // Create deadpool manager
        let manager = Manager::new(pg_config, NoTls);
        
        // Create the connection pool
        let pool = Pool::builder(manager)
            .max_size(config.max_connections)
            .build()
            .map_err(|e| PostgresError::ConnectionFailed(format!("Failed to create connection pool: {}", e)))?;

        // Test the connection with retry
        let conn = Self::get_connection_with_retry(&pool, 3).await
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

    /// Get a connection from the pool with retry logic for transient failures
    async fn get_connection_with_retry(
        pool: &Pool,
        max_retries: u32,
    ) -> PostgresResult<deadpool_postgres::Client> {
        let mut last_error = None;
        for attempt in 0..max_retries {
            match pool.get().await {
                Ok(conn) => {
                    // Validate the connection is still alive with a simple query
                    match conn.query_one("SELECT 1", &[]).await {
                        Ok(_) => return Ok(conn),
                        Err(e) => {
                            log::warn!("Connection validation failed: {}, retrying...", e);
                            if Self::is_transient_error(&e) && attempt < max_retries - 1 {
                                tokio::time::sleep(std::time::Duration::from_millis(
                                    100 * (attempt + 1) as u64,
                                )).await;
                                last_error = Some(PostgresError::ConnectionFailed(e.to_string()));
                                continue;
                            }
                            return Err(PostgresError::ConnectionFailed(e.to_string()));
                        }
                    }
                }
                Err(e) => {
                    let error_str = e.to_string();
                    log::warn!("Failed to get connection (attempt {}/{}): {}", attempt + 1, max_retries, error_str);
                    last_error = Some(PostgresError::ConnectionFailed(error_str));
                    if attempt < max_retries - 1 {
                        // Exponential backoff: 100ms, 200ms, 400ms
                        tokio::time::sleep(std::time::Duration::from_millis(
                            100 * (1 << attempt) as u64,
                        )).await;
                    }
                }
            }
        }
        Err(last_error.unwrap_or_else(|| PostgresError::ConnectionFailed("Failed to get connection after retries".to_string())))
    }

    /// Get a connection from the pool with automatic retry for transient failures
    async fn get_connection(&self) -> PostgresResult<deadpool_postgres::Client> {
        Self::get_connection_with_retry(&self.pool, 3).await
    }

    /// Check if an error is transient and should be retried
    fn is_transient_error(error: &tokio_postgres::Error) -> bool {
        // Check for connection-related errors that are likely transient
        if let Some(code) = error.code() {
            // PostgreSQL error codes that indicate transient issues
            return matches!(
                code.code(),
                "08003" | // connection_does_not_exist
                "08006" | // connection_failure
                "08001" | // sqlclient_unable_to_establish_sqlconnection
                "08004" | // sqlserver_rejected_establishment_of_sqlconnection
                "57P01" | // admin_shutdown
                "57P02" | // crash_shutdown
                "57P03" | // cannot_connect_now
                "53300"   // too_many_connections
            );
        }
        
        // If no error code, check error message for connection-related keywords
        let msg = error.to_string().to_lowercase();
        msg.contains("connection closed") ||
        msg.contains("connection terminated") ||
        msg.contains("connection reset") ||
        msg.contains("broken pipe") ||
        msg.contains("server closed the connection") ||
        msg.contains("terminating connection because of crash")
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
        // Retry logic for transient connection failures
        let mut last_error = None;
        for attempt in 0..3 {
            match self.get_connection().await {
                Ok(conn) => {
                    let mut outputs = Vec::new();
                    let mut all_succeeded = true;
                    
                    for request in &requests {
                        match self.backend.read_range(&conn, request).await {
                            Ok(entries) => {
                                outputs.push(ReadRangeOutput { entries });
                            }
                            Err(e) => {
                                // Check if it's a transient error
                                if e.is_transient() && attempt < 2 {
                                    log::warn!("Transient error during read_range (attempt {}), retrying: {}", attempt + 1, e);
                                    all_succeeded = false;
                                    last_error = Some(JsErrorBox::from_err(e));
                                    break;
                                }
                                return Err(JsErrorBox::from_err(e));
                            }
                        }
                    }
                    
                    if all_succeeded {
                        return Ok(outputs);
                    }
                    
                    // If we had transient errors, wait before retrying
                    if attempt < 2 {
                        tokio::time::sleep(std::time::Duration::from_millis(
                            100 * (1 << attempt) as u64,
                        )).await;
                    }
                }
                Err(e) => {
                    if e.is_transient() && attempt < 2 {
                        log::warn!("Transient connection error (attempt {}), retrying: {}", attempt + 1, e);
                        last_error = Some(JsErrorBox::from_err(e));
                        tokio::time::sleep(std::time::Duration::from_millis(
                            100 * (1 << attempt) as u64,
                        )).await;
                    } else {
                        return Err(JsErrorBox::from_err(e));
                    }
                }
            }
        }
        
        Err(last_error.unwrap_or_else(|| JsErrorBox::generic("Failed to read after retries".to_string())))
    }

    async fn atomic_write(
        &self,
        write: AtomicWrite,
    ) -> Result<Option<CommitResult>, JsErrorBox> {
        // Retry logic for transient connection failures
        let mut last_error = None;
        for attempt in 0..3 {
            match self.get_connection().await {
                Ok(mut conn) => {
                    match self.backend.atomic_write(&mut conn, write.clone()).await {
                        Ok(result) => return Ok(result),
                        Err(e) => {
                            // Check if it's a transient error
                            if e.is_transient() && attempt < 2 {
                                log::warn!("Transient error during atomic_write (attempt {}), retrying: {}", attempt + 1, e);
                                last_error = Some(JsErrorBox::from_err(e));
                                tokio::time::sleep(std::time::Duration::from_millis(
                                    100 * (1 << attempt) as u64,
                                )).await;
                                continue;
                            }
                            // For non-transient errors or final attempt, return the error
                            return Err(JsErrorBox::from_err(e));
                        }
                    }
                }
                Err(e) => {
                    if e.is_transient() && attempt < 2 {
                        log::warn!("Transient connection error (attempt {}), retrying: {}", attempt + 1, e);
                        last_error = Some(JsErrorBox::from_err(e));
                        tokio::time::sleep(std::time::Duration::from_millis(
                            100 * (1 << attempt) as u64,
                        )).await;
                    } else {
                        return Err(JsErrorBox::from_err(e));
                    }
                }
            }
        }
        
        Err(last_error.unwrap_or_else(|| JsErrorBox::generic("Failed to write after retries".to_string())))
    }

    async fn dequeue_next_message(&self) -> Result<Option<Self::QMH>, JsErrorBox> {
        // Retry logic for transient connection failures
        let mut last_error = None;
        for attempt in 0..3 {
            match self.get_connection().await {
                Ok(mut conn) => {
                    match self.backend.dequeue_next_message(&mut conn).await {
                        Ok(result) => return Ok(result),
                        Err(e) => {
                            // Check if it's a transient error
                            if e.is_transient() && attempt < 2 {
                                log::warn!("Transient error during dequeue_next_message (attempt {}), retrying: {}", attempt + 1, e);
                                last_error = Some(JsErrorBox::from_err(e));
                                tokio::time::sleep(std::time::Duration::from_millis(
                                    100 * (1 << attempt) as u64,
                                )).await;
                                continue;
                            }
                            return Err(JsErrorBox::from_err(e));
                        }
                    }
                }
                Err(e) => {
                    if e.is_transient() && attempt < 2 {
                        log::warn!("Transient connection error (attempt {}), retrying: {}", attempt + 1, e);
                        last_error = Some(JsErrorBox::from_err(e));
                        tokio::time::sleep(std::time::Duration::from_millis(
                            100 * (1 << attempt) as u64,
                        )).await;
                    } else {
                        return Err(JsErrorBox::from_err(e));
                    }
                }
            }
        }
        
        Err(last_error.unwrap_or_else(|| JsErrorBox::generic("Failed to dequeue after retries".to_string())))
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