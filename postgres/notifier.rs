// Copyright 2023 rawkakani. All rights reserved. MIT license.

use std::collections::HashMap;
use std::sync::{Arc, RwLock};
use tokio::sync::watch;

/// PostgreSQL notifier for key change events
#[derive(Clone, Default)]
pub struct PostgresNotifier {
    inner: Arc<PostgresNotifierInner>,
}

impl PostgresNotifier {
    pub fn new() -> Self {
        Self::default()
    }
}

#[derive(Default)]
struct PostgresNotifierInner {
    key_watchers: RwLock<HashMap<Vec<u8>, watch::Sender<()>>>,
}

impl PostgresNotifier {
    /// Subscribe to changes for a specific key
    pub fn subscribe(&self, key: Vec<u8>) -> PostgresKeySubscription {
        let mut key_watchers = self.inner.key_watchers.write().unwrap();
        let receiver = match key_watchers.entry(key.clone()) {
            std::collections::hash_map::Entry::Occupied(entry) => entry.get().subscribe(),
            std::collections::hash_map::Entry::Vacant(entry) => {
                let (sender, receiver) = watch::channel(());
                entry.insert(sender);
                receiver
            }
        };
        PostgresKeySubscription {
            notifier: Arc::downgrade(&self.inner),
            key: Some(key),
            receiver,
        }
    }

    /// Notify that a key has changed
    pub fn notify_key_update(&self, key: &[u8]) {
        let key_watchers = self.inner.key_watchers.read().unwrap();
        if let Some(sender) = key_watchers.get(key) {
            sender.send(()).ok(); // Ignore if no receivers
        }
    }
}

pub struct PostgresKeySubscription {
    notifier: std::sync::Weak<PostgresNotifierInner>,
    key: Option<Vec<u8>>,
    receiver: watch::Receiver<()>,
}

impl PostgresKeySubscription {
    /// Wait for a change to the key
    pub async fn wait_for_change(&mut self) {
        let _ = self.receiver.changed().await;
    }
}

impl Drop for PostgresKeySubscription {
    fn drop(&mut self) {
        if let Some(notifier) = self.notifier.upgrade() {
            let key = self.key.take().unwrap();
            let mut key_watchers = notifier.key_watchers.write().unwrap();
            match key_watchers.entry(key) {
                std::collections::hash_map::Entry::Occupied(entry) => {
                    // If there is only one subscriber left (this struct), then remove
                    // the entry from the map.
                    if entry.get().receiver_count() == 1 {
                        entry.remove();
                    }
                }
                std::collections::hash_map::Entry::Vacant(_) => unreachable!("the entry should still exist"),
            }
        }
    }
}