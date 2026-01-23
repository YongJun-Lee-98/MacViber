pub mod ffi;
pub mod models;
pub mod services;
pub mod terminal;

use parking_lot::RwLock;
use std::collections::HashMap;
use std::sync::Arc;
use uuid::Uuid;

pub use models::*;
pub use services::*;

pub struct Core {
    sessions: Arc<RwLock<HashMap<Uuid, Session>>>,
    #[allow(dead_code)]
    runtime: tokio::runtime::Runtime,
}

impl Core {
    pub fn new() -> Result<Self, CoreError> {
        let runtime = tokio::runtime::Builder::new_multi_thread()
            .worker_threads(4)
            .enable_all()
            .build()
            .map_err(|e| CoreError::RuntimeInit(e.to_string()))?;

        Ok(Self {
            sessions: Arc::new(RwLock::new(HashMap::new())),
            runtime,
        })
    }

    pub fn create_session(&self, working_dir: &str) -> Result<Uuid, CoreError> {
        let session_id = Uuid::new_v4();
        let session = Session::new(session_id, working_dir.to_string());

        self.sessions.write().insert(session_id, session);

        Ok(session_id)
    }

    pub fn close_session(&self, session_id: Uuid) -> Result<(), CoreError> {
        self.sessions
            .write()
            .remove(&session_id)
            .ok_or(CoreError::SessionNotFound(session_id))?;

        Ok(())
    }

    pub fn session_count(&self) -> usize {
        self.sessions.read().len()
    }
}

impl Default for Core {
    fn default() -> Self {
        Self::new().expect("Failed to initialize Core")
    }
}

#[derive(Debug, thiserror::Error)]
pub enum CoreError {
    #[error("Failed to initialize runtime: {0}")]
    RuntimeInit(String),

    #[error("Session not found: {0}")]
    SessionNotFound(Uuid),

    #[error("PTY error: {0}")]
    Pty(String),

    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),
}
