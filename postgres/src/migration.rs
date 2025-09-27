// Copyright 2023 rawkakani. All rights reserved. MIT license.

use std::collections::HashMap;
use std::path::Path;

use chrono::{DateTime, Utc};
use rusqlite::{Connection, Row};
use serde_json::Value;

use crate::error::{PostgresError, PostgresResult};
use crate::PostgresConfig;

/// Migration tool for moving data from SQLite to PostgreSQL
pub struct MigrationTool {
    sqlite_path: String,
    postgres_config: PostgresConfig,
}

impl MigrationTool {
    /// Create a new migration tool
    pub fn new(sqlite_path: String, postgres_config: PostgresConfig) -> Self {
        Self {
            sqlite_path,
            postgres_config,
        }
    }

    /// Migrate all data from SQLite to PostgreSQL
    pub async fn migrate_all(&self) -> PostgresResult<()> {
        println!("Starting migration from SQLite to PostgreSQL...");

        // Open SQLite database
        let sqlite_conn = Connection::open(&self.sqlite_path)
            .map_err(|e| PostgresError::DatabaseError(format!("Failed to open SQLite: {}", e)))?;

        // Create PostgreSQL instance
        let postgres = crate::Postgres::new(self.postgres_config.clone()).await?;

        // Migrate KV data
        self.migrate_kv_data(&sqlite_conn, &postgres).await?;

        // Migrate queue data
        self.migrate_queue_data(&sqlite_conn, &postgres).await?;

        println!("Migration completed successfully!");
        Ok(())
    }

    /// Migrate KV data from SQLite to PostgreSQL
    async fn migrate_kv_data(
        &self,
        sqlite_conn: &Connection,
        postgres: &crate::Postgres,
    ) -> PostgresResult<()> {
        println!("Migrating KV data...");

        let mut stmt = sqlite_conn.prepare(
            "SELECT key, value, value_encoding, versionstamp, expires_at FROM kv_store"
        )?;

        let rows = stmt.query_map([], |row| {
            Ok(KvRow {
                key: row.get("key")?,
                value: row.get("value")?,
                value_encoding: row.get("value_encoding")?,
                versionstamp: row.get("versionstamp")?,
                expires_at: row.get("expires_at")?,
            })
        })?;

        let mut batch = Vec::new();
        let mut count = 0;

        for row in rows {
            let row = row?;
            batch.push(row);

            // Process in batches of 1000
            if batch.len() >= 1000 {
                self.process_kv_batch(&postgres, &batch).await?;
                count += batch.len();
                println!("Migrated {} KV entries...", count);
                batch.clear();
            }
        }

        // Process remaining entries
        if !batch.is_empty() {
            self.process_kv_batch(&postgres, &batch).await?;
            count += batch.len();
        }

        println!("Migrated {} KV entries total", count);
        Ok(())
    }

    /// Migrate queue data from SQLite to PostgreSQL
    async fn migrate_queue_data(
        &self,
        sqlite_conn: &Connection,
        postgres: &crate::Postgres,
    ) -> PostgresResult<()> {
        println!("Migrating queue data...");

        let mut stmt = sqlite_conn.prepare(
            "SELECT id, payload, deadline, keys_if_undelivered, backoff_schedule FROM queue_messages"
        )?;

        let rows = stmt.query_map([], |row| {
            Ok(QueueRow {
                id: row.get("id")?,
                payload: row.get("payload")?,
                deadline: row.get("deadline")?,
                keys_if_undelivered: row.get("keys_if_undelivered")?,
                backoff_schedule: row.get("backoff_schedule")?,
            })
        })?;

        let mut count = 0;
        for row in rows {
            let row = row?;
            self.process_queue_row(&postgres, &row).await?;
            count += 1;
        }

        println!("Migrated {} queue messages", count);
        Ok(())
    }

    /// Process a batch of KV rows
    async fn process_kv_batch(
        &self,
        postgres: &crate::Postgres,
        batch: &[KvRow],
    ) -> PostgresResult<()> {
        // Get a connection from the pool
        let conn = postgres.pool.get().await?;

        for row in batch {
            let value_encoding = match row.value_encoding {
                1 => "V8",
                2 => "LE64",
                3 => "BYTES",
                _ => return Err(PostgresError::InvalidData(format!("Unknown encoding: {}", row.value_encoding))),
            };

            conn.execute(
                r#"
                INSERT INTO kv_store (key, value, value_encoding, versionstamp, expires_at, created_at, updated_at)
                VALUES ($1, $2, $3, $4, $5, NOW(), NOW())
                ON CONFLICT (key) DO UPDATE SET
                    value = EXCLUDED.value,
                    value_encoding = EXCLUDED.value_encoding,
                    versionstamp = EXCLUDED.versionstamp,
                    expires_at = EXCLUDED.expires_at,
                    updated_at = NOW()
                "#,
                &[
                    &row.key,
                    &row.value,
                    &row.value_encoding,
                    &row.versionstamp,
                    &row.expires_at,
                ],
            ).await?;
        }

        Ok(())
    }

    /// Process a single queue row
    async fn process_queue_row(
        &self,
        postgres: &crate::Postgres,
        row: &QueueRow,
    ) -> PostgresResult<()> {
        let conn = postgres.pool.get().await?;

        // Parse JSON fields
        let keys_json: Value = serde_json::from_str(&row.keys_if_undelivered)?;
        let backoff_json: Option<Value> = if let Some(backoff) = &row.backoff_schedule {
            Some(serde_json::from_str(backoff)?)
        } else {
            None
        };

        conn.execute(
            r#"
            INSERT INTO queue_messages (id, payload, deadline, keys_if_undelivered, backoff_schedule, created_at)
            VALUES ($1, $2, $3, $4, $5, NOW())
            ON CONFLICT (id) DO UPDATE SET
                payload = EXCLUDED.payload,
                deadline = EXCLUDED.deadline,
                keys_if_undelivered = EXCLUDED.keys_if_undelivered,
                backoff_schedule = EXCLUDED.backoff_schedule
            "#,
            &[
                &row.id,
                &row.payload,
                &row.deadline,
                &keys_json,
                &backoff_json,
            ],
        ).await?;

        Ok(())
    }
}

#[derive(Debug)]
struct KvRow {
    key: Vec<u8>,
    value: Vec<u8>,
    value_encoding: i32,
    versionstamp: Vec<u8>,
    expires_at: Option<DateTime<Utc>>,
}

#[derive(Debug)]
struct QueueRow {
    id: String,
    payload: Vec<u8>,
    deadline: DateTime<Utc>,
    keys_if_undelivered: String,
    backoff_schedule: Option<String>,
}

/// CLI tool for migration
pub async fn run_migration_cli() -> PostgresResult<()> {
    use clap::Parser;

    #[derive(Parser)]
    struct Args {
        /// Path to SQLite database
        #[clap(long)]
        sqlite_path: String,

        /// PostgreSQL connection URL
        #[clap(long)]
        postgres_url: String,

        /// Maximum number of connections
        #[clap(long, default_value = "10")]
        max_connections: usize,
    }

    let args = Args::parse();

    let postgres_config = PostgresConfig::new(args.postgres_url)
        .with_max_connections(args.max_connections);

    let migration_tool = MigrationTool::new(args.sqlite_path, postgres_config);
    migration_tool.migrate_all().await?;

    Ok(())
}