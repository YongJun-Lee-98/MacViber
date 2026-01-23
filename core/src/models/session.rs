use serde::{Deserialize, Serialize};
use std::time::SystemTime;
use uuid::Uuid;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(C)]
pub enum SessionStatus {
    Running = 0,
    Stopped = 1,
    WaitingForInput = 2,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Session {
    pub id: Uuid,
    pub name: String,
    pub working_directory: String,
    pub status: SessionStatus,
    pub created_at: SystemTime,
    pub last_activity: SystemTime,
    pub has_unread_notification: bool,
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
            working_directory,
            status: SessionStatus::Running,
            created_at: now,
            last_activity: now,
            has_unread_notification: false,
        }
    }

    pub fn update_activity(&mut self) {
        self.last_activity = SystemTime::now();
    }

    pub fn set_status(&mut self, status: SessionStatus) {
        self.status = status;
        self.update_activity();
    }
}
