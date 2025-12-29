// Copyright 2023 rawkakani. All rights reserved. MIT license.

use deno_error::{JsErrorBox, JsErrorClass};
use thiserror::Error;

/// PostgreSQL-specific errors
#[derive(Error, Debug)]
pub enum PostgresError {
    #[error("Invalid configuration: {0}")]
    InvalidConfig(String),

    #[error("Connection failed: {0}")]
    ConnectionFailed(String),

    #[error("Database error: {0}")]
    DatabaseError(String),

    #[error("Transaction error: {0}")]
    TransactionError(String),

    #[error("Query error: {0}")]
    QueryError(String),

    #[error("Serialization error: {0}")]
    SerializationError(String),

    #[error("Deserialization error: {0}")]
    DeserializationError(String),

    #[error("Invalid data: {0}")]
    InvalidData(String),

    #[error("Timeout: {0}")]
    Timeout(String),

    #[error("Pool error: {0}")]
    PoolError(String),
}

impl From<tokio_postgres::Error> for PostgresError {
    fn from(err: tokio_postgres::Error) -> Self {
        PostgresError::DatabaseError(err.to_string())
    }
}

impl From<deadpool_postgres::PoolError> for PostgresError {
    fn from(err: deadpool_postgres::PoolError) -> Self {
        PostgresError::PoolError(err.to_string())
    }
}

impl From<serde_json::Error> for PostgresError {
    fn from(err: serde_json::Error) -> Self {
        PostgresError::SerializationError(err.to_string())
    }
}

impl From<uuid::Error> for PostgresError {
    fn from(err: uuid::Error) -> Self {
        PostgresError::InvalidData(err.to_string())
    }
}

impl JsErrorClass for PostgresError {
    fn get_class(&self) -> std::borrow::Cow<'static, str> {
        std::borrow::Cow::Borrowed("PostgresError")
    }

    fn get_message(&self) -> std::borrow::Cow<'static, str> {
        std::borrow::Cow::Owned(self.to_string())
    }

    fn get_additional_properties(&self) -> Box<dyn std::iter::Iterator<Item = (std::borrow::Cow<'static, str>, deno_error::PropertyValue)> + 'static> {
        Box::new(std::iter::empty())
    }

    fn get_ref(&self) -> &(dyn std::error::Error + Send + Sync + 'static) {
        self
    }
}

impl From<PostgresError> for JsErrorBox {
    fn from(err: PostgresError) -> Self {
        JsErrorBox::generic(err.to_string())
    }
}

/// Result type for PostgreSQL operations
pub type PostgresResult<T> = Result<T, PostgresError>;