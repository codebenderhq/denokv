// Copyright 2023 rawkakani. All rights reserved. MIT license.

use serde::{Deserialize, Serialize};

/// Configuration for PostgreSQL backend
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PostgresConfig {
    /// PostgreSQL connection URL
    /// Example: postgresql://user:password@localhost:5432/denokv
    pub url: String,
    
    /// Maximum number of connections in the pool
    pub max_connections: usize,
    
    /// Connection timeout in seconds
    pub connection_timeout: u64,
    
    /// Statement timeout in seconds
    pub statement_timeout: u64,
}

impl Default for PostgresConfig {
    fn default() -> Self {
        Self {
            url: "postgresql://postgres:password@localhost:5432/denokv".to_string(),
            max_connections: 10,
            connection_timeout: 30,
            statement_timeout: 60,
        }
    }
}

impl PostgresConfig {
    /// Create a new PostgreSQL configuration
    pub fn new(url: String) -> Self {
        Self {
            url,
            ..Default::default()
        }
    }

    /// Set the maximum number of connections
    pub fn with_max_connections(mut self, max_connections: usize) -> Self {
        self.max_connections = max_connections;
        self
    }

    /// Set the connection timeout
    pub fn with_connection_timeout(mut self, timeout: u64) -> Self {
        self.connection_timeout = timeout;
        self
    }

    /// Set the statement timeout
    pub fn with_statement_timeout(mut self, timeout: u64) -> Self {
        self.statement_timeout = timeout;
        self
    }
}