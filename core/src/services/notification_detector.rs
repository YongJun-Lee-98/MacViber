use crate::models::{Notification, NotificationType};
use regex::Regex;
use std::time::{Duration, Instant};
use uuid::Uuid;

pub struct NotificationDetector {
    patterns: Vec<(Regex, NotificationType)>,
    ansi_strip_regex: Regex,
    last_detection_time: Option<Instant>,
    debounce_interval: Duration,
    last_matched_key: Option<String>,
}

impl NotificationDetector {
    pub fn new() -> Self {
        let patterns = vec![
            (r"\?\s*$", NotificationType::Question),
            (r"\(y/n\)", NotificationType::Question),
            (r"\[Y/n\]", NotificationType::Question),
            (r"\[yes/no\]", NotificationType::Question),
            (r"Press Enter to continue", NotificationType::Question),
            (r"Allow\s+.*\?", NotificationType::PermissionRequest),
            (r"Do you want to", NotificationType::PermissionRequest),
            (r"Proceed\?", NotificationType::PermissionRequest),
            (r"\(approve/deny\)", NotificationType::PermissionRequest),
            (r"✓.*completed", NotificationType::Completion),
            (r"Done\.", NotificationType::Completion),
            (r"Successfully", NotificationType::Completion),
            (r"Error:", NotificationType::Error),
            (r"Failed:", NotificationType::Error),
            (r"FAILED", NotificationType::Error),
        ];

        let compiled_patterns: Vec<_> = patterns
            .into_iter()
            .filter_map(|(p, t)| Regex::new(p).ok().map(|r| (r, t)))
            .collect();

        let ansi_strip_regex = Regex::new(
            r"(?x)
            \x1b\[[0-9;]*[A-Za-z] |
            \x1b\[\?[0-9;]*[A-Za-z] |
            \x1b\][^\x07]*\x07 |
            \x1b[()][AB012]
            ",
        )
        .unwrap();

        Self {
            patterns: compiled_patterns,
            ansi_strip_regex,
            last_detection_time: None,
            debounce_interval: Duration::from_millis(500),
            last_matched_key: None,
        }
    }

    pub fn detect(&mut self, text: &str, session_id: Uuid) -> Option<Notification> {
        if let Some(last_time) = self.last_detection_time {
            if last_time.elapsed() < self.debounce_interval {
                return None;
            }
        }

        let clean_text = self.strip_ansi(text);

        for (regex, notification_type) in &self.patterns {
            if regex.is_match(&clean_text) {
                let match_key = format!("{:?}:{}", notification_type, session_id);

                if self.last_matched_key.as_ref() == Some(&match_key) {
                    return None;
                }

                self.last_matched_key = Some(match_key);
                self.last_detection_time = Some(Instant::now());

                let message = self.extract_message(&clean_text);

                return Some(Notification::new(
                    session_id,
                    *notification_type,
                    message,
                    String::new(),
                ));
            }
        }

        None
    }

    pub fn reset(&mut self) {
        self.last_detection_time = None;
        self.last_matched_key = None;
    }

    fn strip_ansi(&self, text: &str) -> String {
        self.ansi_strip_regex.replace_all(text, "").to_string()
    }

    fn extract_message(&self, text: &str) -> String {
        text.lines()
            .rev()
            .find(|line| {
                let trimmed = line.trim();
                !trimmed.is_empty() && trimmed.len() > 5
            })
            .map(|s| s.chars().take(200).collect())
            .unwrap_or_else(|| text.chars().take(200).collect())
    }
}

impl Default for NotificationDetector {
    fn default() -> Self {
        Self::new()
    }
}
