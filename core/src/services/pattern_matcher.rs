use regex::Regex;
use std::collections::HashMap;
use uuid::Uuid;

pub struct CustomPattern {
    pub id: Uuid,
    pub name: String,
    pub pattern: String,
    pub is_regex: bool,
    pub is_enabled: bool,
    pub auto_pin: bool,
}

pub struct PatternMatcher {
    patterns: Vec<CustomPattern>,
    regex_cache: HashMap<Uuid, Regex>,
}

impl PatternMatcher {
    pub fn new() -> Self {
        Self {
            patterns: Vec::new(),
            regex_cache: HashMap::new(),
        }
    }

    pub fn add_pattern(&mut self, pattern: CustomPattern) {
        if pattern.is_regex {
            if let Ok(regex) = Regex::new(&pattern.pattern) {
                self.regex_cache.insert(pattern.id, regex);
            }
        }
        self.patterns.push(pattern);
    }

    pub fn remove_pattern(&mut self, pattern_id: Uuid) {
        self.patterns.retain(|p| p.id != pattern_id);
        self.regex_cache.remove(&pattern_id);
    }

    pub fn match_text(&self, text: &str) -> Option<&CustomPattern> {
        for pattern in &self.patterns {
            if !pattern.is_enabled {
                continue;
            }

            let matched = if pattern.is_regex {
                self.regex_cache
                    .get(&pattern.id)
                    .map(|r| r.is_match(text))
                    .unwrap_or(false)
            } else {
                text.to_lowercase()
                    .contains(&pattern.pattern.to_lowercase())
            };

            if matched {
                return Some(pattern);
            }
        }
        None
    }

    pub fn invalidate_cache(&mut self) {
        self.regex_cache.clear();
        for pattern in &self.patterns {
            if pattern.is_regex {
                if let Ok(regex) = Regex::new(&pattern.pattern) {
                    self.regex_cache.insert(pattern.id, regex);
                }
            }
        }
    }
}

impl Default for PatternMatcher {
    fn default() -> Self {
        Self::new()
    }
}
