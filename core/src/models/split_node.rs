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
}
