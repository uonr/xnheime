use std::sync::{Arc, Mutex};
use xnheime_core::{
    CandidateItem as CoreCandidateItem, CompositionEffect as CoreEffect,
    CompositionEvent as CoreEvent, CompositionMode as CoreMode, CompositionSession as CoreSession,
};

#[derive(Clone, Debug, Eq, PartialEq, uniffi::Enum)]
pub enum CandidateAction {
    AddUserEntry,
}

#[derive(Clone, Debug, Eq, PartialEq, uniffi::Enum)]
pub enum CandidateItem {
    Candidate {
        text: String,
        code: Option<String>,
    },
    ActionHint {
        text: String,
        label: String,
        action: CandidateAction,
    },
}

#[derive(Clone, Debug, Eq, PartialEq, uniffi::Enum)]
pub enum CompositionEvent {
    InputText {
        text: String,
    },
    InsertDirect {
        text: String,
    },
    EnterInline {
        text: String,
    },
    Commit,
    CommitCode,
    Cancel {
        clear_marked_text: bool,
    },
    MoveCandidate {
        offset: i32,
    },
    SelectCandidate {
        index: u32,
    },
    InputMergedKey {
        letters: String,
    },
    InputWeightedMergedKey {
        letters: String,
        primary_weight: u16,
    },
}

#[derive(Clone, Debug, Eq, PartialEq, uniffi::Enum)]
pub enum CompositionEffect {
    InsertText {
        text: String,
    },
    InsertPairedText {
        before: String,
        after: String,
    },
    SetMarkedText {
        text: String,
    },
    ShowCandidates {
        candidates: Vec<CandidateItem>,
        selected_index: u32,
        character_index: u32,
    },
    HideCandidates,
    DeleteBackward,
    ShowAddEntryDialog {
        code: String,
    },
}

#[derive(Clone, Debug, Eq, PartialEq, uniffi::Enum)]
pub enum CompositionMode {
    Idle,
    Converting { candidate_count: u32 },
    Inline,
}

#[derive(Clone, Debug, Eq, PartialEq, uniffi::Record)]
pub struct CompositionDispatchResult {
    pub effects: Vec<CompositionEffect>,
    pub mode: CompositionMode,
    pub candidate_count: u32,
}

#[derive(Clone, Debug, Eq, PartialEq, uniffi::Record)]
pub struct UserDictionaryLoadResult {
    pub loaded_entries: u32,
    pub ignored_lines: u32,
    pub loaded_files: Vec<String>,
    pub error: Option<String>,
}

#[derive(uniffi::Object)]
pub struct CompositionSession {
    inner: Mutex<CoreSession>,
}

#[uniffi::export]
impl CompositionSession {
    #[uniffi::constructor]
    pub fn new() -> Arc<Self> {
        Arc::new(Self {
            inner: Mutex::new(CoreSession::new()),
        })
    }

    pub fn mode(&self) -> CompositionMode {
        self.inner
            .lock()
            .expect("composition session lock poisoned")
            .mode()
            .into()
    }

    pub fn candidates(&self) -> Vec<CandidateItem> {
        self.inner
            .lock()
            .expect("composition session lock poisoned")
            .candidates()
            .into_iter()
            .map(Into::into)
            .collect()
    }

    pub fn candidate_page(&self, offset: u32, limit: u32) -> Vec<CandidateItem> {
        self.inner
            .lock()
            .expect("composition session lock poisoned")
            .candidates_range(offset as usize, limit as usize)
            .into_iter()
            .map(Into::into)
            .collect()
    }

    pub fn load_user_dictionary_directory(&self, path: String) -> UserDictionaryLoadResult {
        match self
            .inner
            .lock()
            .expect("composition session lock poisoned")
            .load_user_dictionary_directory(std::path::Path::new(&path))
        {
            Ok(result) => UserDictionaryLoadResult {
                loaded_entries: result.loaded_entries,
                ignored_lines: result.ignored_lines,
                loaded_files: result.loaded_files,
                error: None,
            },
            Err(error) => UserDictionaryLoadResult {
                loaded_entries: 0,
                ignored_lines: 0,
                loaded_files: Vec::new(),
                error: Some(error.to_string()),
            },
        }
    }

    /// Moves a dictionary prepared in a background session into this live session.
    /// The live composition state is intentionally left untouched.
    pub fn adopt_user_dictionary(&self, source: Arc<CompositionSession>) {
        let dictionary = source
            .inner
            .lock()
            .expect("source composition session lock poisoned")
            .take_user_dictionary();
        self.inner
            .lock()
            .expect("composition session lock poisoned")
            .replace_user_dictionary(dictionary);
    }

    pub fn dispatch(
        &self,
        event: CompositionEvent,
        selected_text: Option<String>,
        clipboard_text: Option<String>,
    ) -> Vec<CompositionEffect> {
        self.inner
            .lock()
            .expect("composition session lock poisoned")
            .dispatch_with_external_text(event.into(), selected_text, clipboard_text)
            .into_iter()
            .map(Into::into)
            .collect()
    }

    pub fn dispatch_paged(
        &self,
        event: CompositionEvent,
        selected_text: Option<String>,
        clipboard_text: Option<String>,
        candidate_limit: u32,
    ) -> CompositionDispatchResult {
        let mut session = self
            .inner
            .lock()
            .expect("composition session lock poisoned");
        let effects =
            session.dispatch_with_external_text(event.into(), selected_text, clipboard_text);
        let mode: CompositionMode = session.mode().into();
        let candidate_count = match mode {
            CompositionMode::Converting { candidate_count } => candidate_count,
            CompositionMode::Idle | CompositionMode::Inline => 0,
        };
        CompositionDispatchResult {
            effects: effects
                .into_iter()
                .map(|effect| {
                    CompositionEffect::from_core_limited(effect, candidate_limit as usize)
                })
                .collect(),
            mode,
            candidate_count,
        }
    }
}

impl CompositionEffect {
    fn from_core_limited(effect: CoreEffect, limit: usize) -> Self {
        match effect {
            CoreEffect::ShowCandidates {
                candidates,
                selected_index,
                character_index,
            } => Self::ShowCandidates {
                candidates: candidates.iter().take(limit).map(Into::into).collect(),
                selected_index,
                character_index,
            },
            other => other.into(),
        }
    }
}

impl From<xnheime_core::CandidateAction> for CandidateAction {
    fn from(action: xnheime_core::CandidateAction) -> Self {
        match action {
            xnheime_core::CandidateAction::AddUserEntry => Self::AddUserEntry,
        }
    }
}

impl From<CoreCandidateItem> for CandidateItem {
    fn from(candidate: CoreCandidateItem) -> Self {
        match candidate {
            CoreCandidateItem::Candidate { text, code } => Self::Candidate {
                text: text.into(),
                code: code.map(Into::into),
            },
            CoreCandidateItem::ActionHint {
                text,
                label,
                action,
            } => Self::ActionHint {
                text: text.into(),
                label: label.into(),
                action: action.into(),
            },
        }
    }
}

impl From<&CoreCandidateItem> for CandidateItem {
    fn from(candidate: &CoreCandidateItem) -> Self {
        match candidate {
            CoreCandidateItem::Candidate { text, code } => Self::Candidate {
                text: text.to_string(),
                code: code.as_ref().map(ToString::to_string),
            },
            CoreCandidateItem::ActionHint {
                text,
                label,
                action,
            } => Self::ActionHint {
                text: text.to_string(),
                label: label.to_string(),
                action: (*action).into(),
            },
        }
    }
}

impl From<CompositionEvent> for CoreEvent {
    fn from(event: CompositionEvent) -> Self {
        match event {
            CompositionEvent::InputText { text } => Self::InputText { text },
            CompositionEvent::InsertDirect { text } => Self::InsertDirect { text },
            CompositionEvent::EnterInline { text } => Self::EnterInline { text },
            CompositionEvent::Commit => Self::Commit,
            CompositionEvent::CommitCode => Self::CommitCode,
            CompositionEvent::Cancel { clear_marked_text } => Self::Cancel { clear_marked_text },
            CompositionEvent::MoveCandidate { offset } => Self::MoveCandidate { offset },
            CompositionEvent::SelectCandidate { index } => Self::SelectCandidate { index },
            CompositionEvent::InputMergedKey { letters } => Self::InputMergedKey { letters },
            CompositionEvent::InputWeightedMergedKey {
                letters,
                primary_weight,
            } => Self::InputWeightedMergedKey {
                letters,
                primary_weight,
            },
        }
    }
}

impl From<CoreEffect> for CompositionEffect {
    fn from(effect: CoreEffect) -> Self {
        match effect {
            CoreEffect::InsertText { text } => Self::InsertText { text: text.into() },
            CoreEffect::InsertPairedText { before, after } => Self::InsertPairedText {
                before: before.into(),
                after: after.into(),
            },
            CoreEffect::SetMarkedText { text } => Self::SetMarkedText { text: text.into() },
            CoreEffect::ShowCandidates {
                candidates,
                selected_index,
                character_index,
            } => Self::ShowCandidates {
                candidates: candidates.iter().map(Into::into).collect(),
                selected_index,
                character_index,
            },
            CoreEffect::HideCandidates => Self::HideCandidates,
            CoreEffect::DeleteBackward => Self::DeleteBackward,
            CoreEffect::ShowAddEntryDialog { code } => {
                Self::ShowAddEntryDialog { code: code.into() }
            }
        }
    }
}

impl From<CoreMode> for CompositionMode {
    fn from(mode: CoreMode) -> Self {
        match mode {
            CoreMode::Idle => Self::Idle,
            CoreMode::Converting { candidate_count } => Self::Converting { candidate_count },
            CoreMode::Inline => Self::Inline,
        }
    }
}

uniffi::setup_scaffolding!();
