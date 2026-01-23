use serde::{Deserialize, Serialize};
use std::time::SystemTime;
use uuid::Uuid;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(C)]
pub enum NotificationType {
    Question = 0,
    PermissionRequest = 1,
    Completion = 2,
    Error = 3,
    Custom = 4,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Notification {
    pub id: Uuid,
    pub session_id: Uuid,
    pub notification_type: NotificationType,
    pub message: String,
    pub context: String,
    pub is_read: bool,
    pub is_pinned: bool,
    pub created_at: SystemTime,
    pub pinned_at: Option<SystemTime>,
}

impl Notification {
    pub fn new(
        session_id: Uuid,
        notification_type: NotificationType,
        message: String,
        context: String,
    ) -> Self {
        Self {
            id: Uuid::new_v4(),
            session_id,
            notification_type,
            message,
            context,
            is_read: false,
            is_pinned: false,
            created_at: SystemTime::now(),
            pinned_at: None,
        }
    }

    pub fn mark_as_read(&mut self) {
        self.is_read = true;
    }

    pub fn toggle_pin(&mut self) {
        if self.is_pinned {
            self.is_pinned = false;
            self.pinned_at = None;
        } else {
            self.is_pinned = true;
            self.pinned_at = Some(SystemTime::now());
        }
    }
}
