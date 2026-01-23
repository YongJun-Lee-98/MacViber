use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(C)]
pub enum SplitDirection {
    Horizontal = 0,
    Vertical = 1,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PaneSize {
    pub width: f64,
    pub height: f64,
}

impl PaneSize {
    pub const MINIMUM_WIDTH: f64 = 300.0;
    pub const MINIMUM_HEIGHT: f64 = 200.0;

    pub fn new(width: f64, height: f64) -> Self {
        Self { width, height }
    }

    pub fn meets_minimum(&self) -> bool {
        self.width >= Self::MINIMUM_WIDTH && self.height >= Self::MINIMUM_HEIGHT
    }

    pub fn half(&self, direction: SplitDirection) -> Self {
        match direction {
            SplitDirection::Horizontal => Self::new(self.width / 2.0, self.height),
            SplitDirection::Vertical => Self::new(self.width, self.height / 2.0),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum SplitNode {
    Terminal {
        id: Uuid,
        session_id: Uuid,
        size: Option<PaneSize>,
    },
    Split {
        id: Uuid,
        direction: SplitDirection,
        first: Box<SplitNode>,
        second: Box<SplitNode>,
        ratio: f64,
    },
}

impl SplitNode {
    pub fn terminal(session_id: Uuid) -> Self {
        Self::Terminal {
            id: Uuid::new_v4(),
            session_id,
            size: None,
        }
    }

    pub fn id(&self) -> Uuid {
        match self {
            Self::Terminal { id, .. } => *id,
            Self::Split { id, .. } => *id,
        }
    }

    pub fn all_session_ids(&self) -> Vec<Uuid> {
        match self {
            Self::Terminal { session_id, .. } => vec![*session_id],
            Self::Split { first, second, .. } => {
                let mut ids = first.all_session_ids();
                ids.extend(second.all_session_ids());
                ids
            }
        }
    }

    pub fn pane_count(&self) -> usize {
        match self {
            Self::Terminal { .. } => 1,
            Self::Split { first, second, .. } => first.pane_count() + second.pane_count(),
        }
    }

    pub fn split(
        &self,
        pane_id: Uuid,
        direction: SplitDirection,
        new_session_id: Uuid,
        split_size: PaneSize,
    ) -> Self {
        match self {
            Self::Terminal { id, session_id, .. } if *id == pane_id => Self::Split {
                id: Uuid::new_v4(),
                direction,
                first: Box::new(Self::Terminal {
                    id: *id,
                    session_id: *session_id,
                    size: Some(split_size.clone()),
                }),
                second: Box::new(Self::Terminal {
                    id: Uuid::new_v4(),
                    session_id: new_session_id,
                    size: Some(split_size),
                }),
                ratio: 0.5,
            },
            Self::Terminal { .. } => self.clone(),
            Self::Split {
                id,
                direction: dir,
                first,
                second,
                ratio,
            } => Self::Split {
                id: *id,
                direction: *dir,
                first: Box::new(first.split(
                    pane_id,
                    direction,
                    new_session_id,
                    split_size.clone(),
                )),
                second: Box::new(second.split(pane_id, direction, new_session_id, split_size)),
                ratio: *ratio,
            },
        }
    }

    pub fn removing_pane(&self, pane_id: Uuid) -> Option<Self> {
        match self {
            Self::Terminal { id, .. } => {
                if *id == pane_id {
                    None
                } else {
                    Some(self.clone())
                }
            }
            Self::Split {
                id,
                direction,
                first,
                second,
                ratio,
            } => {
                let new_first = first.removing_pane(pane_id);
                let new_second = second.removing_pane(pane_id);

                match (new_first, new_second) {
                    (Some(f), Some(s)) => Some(Self::Split {
                        id: *id,
                        direction: *direction,
                        first: Box::new(f),
                        second: Box::new(s),
                        ratio: *ratio,
                    }),
                    (Some(node), None) | (None, Some(node)) => Some(node),
                    (None, None) => None,
                }
            }
        }
    }

    pub fn all_pane_ids(&self) -> Vec<Uuid> {
        match self {
            Self::Terminal { id, .. } => vec![*id],
            Self::Split { first, second, .. } => {
                let mut ids = first.all_pane_ids();
                ids.extend(second.all_pane_ids());
                ids
            }
        }
    }

    pub fn session_id_for_pane(&self, pane_id: Uuid) -> Option<Uuid> {
        match self {
            Self::Terminal { id, session_id, .. } => {
                if *id == pane_id {
                    Some(*session_id)
                } else {
                    None
                }
            }
            Self::Split { first, second, .. } => first
                .session_id_for_pane(pane_id)
                .or_else(|| second.session_id_for_pane(pane_id)),
        }
    }

    pub fn pane_id_for_session(&self, target_session_id: Uuid) -> Option<Uuid> {
        match self {
            Self::Terminal { id, session_id, .. } => {
                if *session_id == target_session_id {
                    Some(*id)
                } else {
                    None
                }
            }
            Self::Split { first, second, .. } => first
                .pane_id_for_session(target_session_id)
                .or_else(|| second.pane_id_for_session(target_session_id)),
        }
    }

    pub fn updating_session(&self, pane_id: Uuid, new_session_id: Uuid) -> Self {
        match self {
            Self::Terminal { id, size, .. } => {
                if *id == pane_id {
                    Self::Terminal {
                        id: *id,
                        session_id: new_session_id,
                        size: size.clone(),
                    }
                } else {
                    self.clone()
                }
            }
            Self::Split {
                id,
                direction,
                first,
                second,
                ratio,
            } => Self::Split {
                id: *id,
                direction: *direction,
                first: Box::new(first.updating_session(pane_id, new_session_id)),
                second: Box::new(second.updating_session(pane_id, new_session_id)),
                ratio: *ratio,
            },
        }
    }

    pub fn parent_split_info(&self, pane_id: Uuid) -> Option<(Uuid, i32)> {
        match self {
            Self::Terminal { .. } => None,
            Self::Split {
                id, first, second, ..
            } => {
                if let Self::Terminal { id: term_id, .. } = first.as_ref() {
                    if *term_id == pane_id {
                        return Some((*id, 0));
                    }
                }
                if let Self::Terminal { id: term_id, .. } = second.as_ref() {
                    if *term_id == pane_id {
                        return Some((*id, 1));
                    }
                }
                first
                    .parent_split_info(pane_id)
                    .or_else(|| second.parent_split_info(pane_id))
            }
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SplitViewState {
    pub root_node: Option<SplitNode>,
    pub focused_pane_id: Option<Uuid>,
    pub max_pane_count: usize,
}

impl SplitViewState {
    pub fn new() -> Self {
        Self {
            root_node: None,
            focused_pane_id: None,
            max_pane_count: 9,
        }
    }

    pub fn is_active(&self) -> bool {
        self.root_node.is_some()
    }

    pub fn pane_count(&self) -> usize {
        self.root_node.as_ref().map(|n| n.pane_count()).unwrap_or(0)
    }

    pub fn can_split(&self) -> bool {
        self.pane_count() < self.max_pane_count
    }

    pub fn all_pane_ids(&self) -> Vec<Uuid> {
        self.root_node
            .as_ref()
            .map(|n| n.all_pane_ids())
            .unwrap_or_default()
    }

    pub fn next_pane_id(&self, current_id: Option<Uuid>) -> Option<Uuid> {
        let pane_ids = self.all_pane_ids();
        if pane_ids.is_empty() {
            return None;
        }

        if let Some(current) = current_id {
            if let Some(idx) = pane_ids.iter().position(|&id| id == current) {
                let next_idx = (idx + 1) % pane_ids.len();
                return Some(pane_ids[next_idx]);
            }
        }

        pane_ids.first().copied()
    }

    pub fn previous_pane_id(&self, current_id: Option<Uuid>) -> Option<Uuid> {
        let pane_ids = self.all_pane_ids();
        if pane_ids.is_empty() {
            return None;
        }

        if let Some(current) = current_id {
            if let Some(idx) = pane_ids.iter().position(|&id| id == current) {
                let prev_idx = if idx == 0 {
                    pane_ids.len() - 1
                } else {
                    idx - 1
                };
                return Some(pane_ids[prev_idx]);
            }
        }

        pane_ids.last().copied()
    }
}

impl Default for SplitViewState {
    fn default() -> Self {
        Self::new()
    }
}
