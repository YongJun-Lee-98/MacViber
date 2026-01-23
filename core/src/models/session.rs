use serde::{Deserialize, Serialize};
use std::time::SystemTime;
use uuid::Uuid;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(C)]
pub enum SessionStatus {
    Idle = 0,
    Running = 1,
    WaitingForInput = 2,
    Terminated = 3,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Session {
    pub id: Uuid,
    pub name: String,
    pub alias: Option<String>,
    pub working_directory: String,
    pub status: SessionStatus,
    pub created_at: SystemTime,
    pub last_activity: SystemTime,
    pub has_unread_notification: bool,
    pub is_locked: bool,
}

impl Session {
    pub fn new(id: Uuid, working_directory: String) -> Self {
        let now = SystemTime::now();
        let name = working_directory
            .split('/')
            .last()
            .unwrap_or("Terminal")
            .to_string();

        Self {
            id,
            name,
            alias: None,
            working_directory,
            status: SessionStatus::Running,
            created_at: now,
            last_activity: now,
            has_unread_notification: false,
            is_locked: false,
        }
    }

    pub fn with_name(id: Uuid, name: String, working_directory: String) -> Self {
        let now = SystemTime::now();
        Self {
            id,
            name,
            alias: None,
            working_directory,
            status: SessionStatus::Running,
            created_at: now,
            last_activity: now,
            has_unread_notification: false,
            is_locked: false,
        }
    }

    pub fn display_name(&self) -> &str {
        self.alias.as_deref().unwrap_or(&self.name)
    }

    pub fn update_activity(&mut self) {
        self.last_activity = SystemTime::now();
    }

    pub fn set_status(&mut self, status: SessionStatus) {
        self.status = status;
        self.update_activity();
    }

    pub fn set_alias(&mut self, alias: Option<String>) {
        self.alias = alias.filter(|s| !s.is_empty());
    }

    pub fn toggle_lock(&mut self) {
        self.is_locked = !self.is_locked;
    }

    pub fn rename(&mut self, new_name: String) {
        self.name = new_name;
        self.update_activity();
    }
}
