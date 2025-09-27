// Copyright 2023 rawkakani. All rights reserved. MIT license.

use denokv_postgres::{Postgres, PostgresConfig};
use denokv_proto::{
    AtomicWrite, Check, Database, KvValue, Mutation, MutationKind, ReadRange, SnapshotReadOptions,
};
use std::num::NonZeroU32;

#[tokio::test]
async fn test_postgres_basic_operations() {
    // Skip test if no PostgreSQL is available
    if std::env::var("POSTGRES_URL").is_err() {
        println!("Skipping PostgreSQL test - POSTGRES_URL not set");
        return;
    }

    let postgres_url = std::env::var("POSTGRES_URL").unwrap();
    let config = PostgresConfig::new(postgres_url);
    let postgres = Postgres::new(config).await.expect("Failed to create PostgreSQL instance");

    // Test basic set operation
    let key = b"test_key".to_vec();
    let value = KvValue::Bytes(b"test_value".to_vec());

    let atomic_write = AtomicWrite {
        checks: vec![],
        mutations: vec![Mutation {
            key: key.clone(),
            kind: MutationKind::Set(value),
            expire_at: None,
        }],
        enqueues: vec![],
    };

    let result = postgres.atomic_write(atomic_write).await.expect("Atomic write failed");
    assert!(result.is_some());

    // Test read operation
    let read_range = ReadRange {
        start: key.clone(),
        end: key.iter().copied().chain(Some(0)).collect(),
        limit: NonZeroU32::new(1).unwrap(),
        reverse: false,
    };

    let options = SnapshotReadOptions {
        consistency: denokv_proto::Consistency::Strong,
    };

    let results = postgres
        .snapshot_read(vec![read_range], options.clone())
        .await
        .expect("Snapshot read failed");

    assert_eq!(results.len(), 1);
    assert_eq!(results[0].entries.len(), 1);
    assert_eq!(results[0].entries[0].key, key);
    match &results[0].entries[0].value {
        KvValue::Bytes(bytes) => assert_eq!(bytes, b"test_value"),
        _ => panic!("Expected Bytes value"),
    }

    // Test delete operation
    let delete_write = AtomicWrite {
        checks: vec![],
        mutations: vec![Mutation {
            key: key.clone(),
            kind: MutationKind::Delete,
            expire_at: None,
        }],
        enqueues: vec![],
    };

    let result = postgres.atomic_write(delete_write).await.expect("Delete failed");
    assert!(result.is_some());

    // Verify deletion
    let read_range = ReadRange {
        start: key.clone(),
        end: key.iter().copied().chain(Some(0)).collect(),
        limit: NonZeroU32::new(1).unwrap(),
        reverse: false,
    };

    let results = postgres
        .snapshot_read(vec![read_range], options.clone())
        .await
        .expect("Snapshot read failed");

    assert_eq!(results.len(), 1);
    assert_eq!(results[0].entries.len(), 0);
}

#[tokio::test]
async fn test_postgres_sum_operations() {
    // Skip test if no PostgreSQL is available
    if std::env::var("POSTGRES_URL").is_err() {
        println!("Skipping PostgreSQL test - POSTGRES_URL not set");
        return;
    }

    let postgres_url = std::env::var("POSTGRES_URL").unwrap();
    let config = PostgresConfig::new(postgres_url);
    let postgres = Postgres::new(config).await.expect("Failed to create PostgreSQL instance");

    let key = b"counter".to_vec();
    let initial_value = KvValue::U64(10);

    // Set initial value
    let set_write = AtomicWrite {
        checks: vec![],
        mutations: vec![Mutation {
            key: key.clone(),
            kind: MutationKind::Set(initial_value),
            expire_at: None,
        }],
        enqueues: vec![],
    };

    postgres.atomic_write(set_write).await.expect("Set failed");

    // Test sum operation
    let sum_value = KvValue::U64(5);
    let sum_write = AtomicWrite {
        checks: vec![],
        mutations: vec![Mutation {
            key: key.clone(),
            kind: MutationKind::Sum {
                value: sum_value,
                min_v8: vec![],
                max_v8: vec![],
                clamp: false,
            },
            expire_at: None,
        }],
        enqueues: vec![],
    };

    postgres.atomic_write(sum_write).await.expect("Sum failed");

    // Verify result
    let read_range = ReadRange {
        start: key.clone(),
        end: key.iter().copied().chain(Some(0)).collect(),
        limit: NonZeroU32::new(1).unwrap(),
        reverse: false,
    };

    let options = SnapshotReadOptions {
        consistency: denokv_proto::Consistency::Strong,
    };

    let results = postgres
        .snapshot_read(vec![read_range], options.clone())
        .await
        .expect("Snapshot read failed");

    assert_eq!(results.len(), 1);
    assert_eq!(results[0].entries.len(), 1);
    match &results[0].entries[0].value {
        KvValue::U64(value) => assert_eq!(*value, 15),
        _ => panic!("Expected U64 value"),
    }
}