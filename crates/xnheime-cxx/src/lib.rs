use xnheime_core::{
    CandidateItem as CoreCandidate, CompositionEffect as CoreEffect, CompositionEvent as CoreEvent,
    CompositionMode as CoreMode, CompositionSession as CoreSession,
    DictionaryMode as CoreDictionaryMode,
};

#[cxx::bridge(namespace = "xnheime")]
mod ffi {
    #[derive(Clone, Copy, Debug, Eq, PartialEq)]
    enum DictionaryMode {
        Expert,
        Regular,
        Beginner,
    }

    #[derive(Clone, Copy, Debug, Eq, PartialEq)]
    enum CompositionMode {
        Idle,
        Converting,
        Inline,
    }

    #[derive(Clone, Copy, Debug, Eq, PartialEq)]
    enum EffectKind {
        InsertText,
        InsertPairedText,
        SetMarkedText,
        ShowCandidates,
        HideCandidates,
        DeleteBackward,
        ShowAddEntry,
    }

    #[derive(Clone, Copy, Debug, Eq, PartialEq)]
    enum CandidateKind {
        Text,
        Action,
    }

    #[derive(Clone, Copy, Debug, Eq, PartialEq)]
    enum CandidateAction {
        None,
        AddUserEntry,
    }

    struct ExternalText {
        has_selected_text: bool,
        selected_text: String,
        has_clipboard_text: bool,
        clipboard_text: String,
    }

    struct Candidate {
        kind: CandidateKind,
        text: String,
        code: String,
        label: String,
        action: CandidateAction,
    }

    struct Effect {
        kind: EffectKind,
        text: String,
        secondary_text: String,
        candidates: Vec<Candidate>,
        selected_index: u32,
        character_index: u32,
    }

    struct DispatchResult {
        effects: Vec<Effect>,
        mode: CompositionMode,
        candidate_count: u32,
    }

    extern "Rust" {
        type Session;

        fn new_session() -> Box<Session>;
        fn set_dictionary_mode(self: &mut Session, mode: DictionaryMode);
        fn load_user_dictionary(self: &mut Session, directory: &str) -> Result<()>;
        fn input_text(
            self: &mut Session,
            text: &str,
            external_text: &ExternalText,
        ) -> DispatchResult;
        fn insert_direct(self: &mut Session, text: &str) -> DispatchResult;
        fn enter_inline(self: &mut Session, text: &str) -> DispatchResult;
        fn commit(self: &mut Session) -> DispatchResult;
        fn commit_code(self: &mut Session) -> DispatchResult;
        fn cancel(self: &mut Session, clear_marked_text: bool) -> DispatchResult;
        fn move_candidate(self: &mut Session, offset: i32) -> DispatchResult;
        fn select_candidate(self: &mut Session, index: u32) -> DispatchResult;
    }
}

pub struct Session(CoreSession);

fn new_session() -> Box<Session> {
    Box::new(Session(CoreSession::new()))
}

impl Session {
    fn set_dictionary_mode(&mut self, mode: ffi::DictionaryMode) {
        self.0.set_dictionary_mode(match mode {
            ffi::DictionaryMode::Expert => CoreDictionaryMode::Expert,
            ffi::DictionaryMode::Regular => CoreDictionaryMode::Regular,
            ffi::DictionaryMode::Beginner => CoreDictionaryMode::Beginner,
            _ => CoreDictionaryMode::Expert,
        });
    }

    fn load_user_dictionary(&mut self, directory: &str) -> Result<(), String> {
        self.0
            .load_user_dictionary_directory(std::path::Path::new(directory))
            .map(|_| ())
            .map_err(|error| error.to_string())
    }

    fn input_text(&mut self, text: &str, external_text: &ffi::ExternalText) -> ffi::DispatchResult {
        let effects = self.0.dispatch_with_external_text(
            CoreEvent::InputText { text: text.into() },
            external_text
                .has_selected_text
                .then(|| external_text.selected_text.clone()),
            external_text
                .has_clipboard_text
                .then(|| external_text.clipboard_text.clone()),
        );
        self.finish_dispatch(effects)
    }

    fn insert_direct(&mut self, text: &str) -> ffi::DispatchResult {
        self.dispatch(CoreEvent::InsertDirect { text: text.into() })
    }

    fn enter_inline(&mut self, text: &str) -> ffi::DispatchResult {
        self.dispatch(CoreEvent::EnterInline { text: text.into() })
    }

    fn commit(&mut self) -> ffi::DispatchResult {
        self.dispatch(CoreEvent::Commit)
    }

    fn commit_code(&mut self) -> ffi::DispatchResult {
        self.dispatch(CoreEvent::CommitCode)
    }

    fn cancel(&mut self, clear_marked_text: bool) -> ffi::DispatchResult {
        self.dispatch(CoreEvent::Cancel { clear_marked_text })
    }

    fn move_candidate(&mut self, offset: i32) -> ffi::DispatchResult {
        self.dispatch(CoreEvent::MoveCandidate { offset })
    }

    fn select_candidate(&mut self, index: u32) -> ffi::DispatchResult {
        self.dispatch(CoreEvent::SelectCandidate { index })
    }

    fn dispatch(&mut self, event: CoreEvent) -> ffi::DispatchResult {
        let effects = self.0.dispatch(event);
        self.finish_dispatch(effects)
    }

    fn finish_dispatch(&self, effects: Vec<CoreEffect>) -> ffi::DispatchResult {
        let mode = self.0.mode();
        ffi::DispatchResult {
            effects: effects.into_iter().map(Into::into).collect(),
            mode: match mode {
                CoreMode::Idle => ffi::CompositionMode::Idle,
                CoreMode::Converting { .. } => ffi::CompositionMode::Converting,
                CoreMode::Inline => ffi::CompositionMode::Inline,
            },
            candidate_count: match mode {
                CoreMode::Converting { candidate_count } => candidate_count,
                CoreMode::Idle | CoreMode::Inline => 0,
            },
        }
    }
}

impl From<CoreCandidate> for ffi::Candidate {
    fn from(candidate: CoreCandidate) -> Self {
        match candidate {
            CoreCandidate::Candidate { text, code } => Self {
                kind: ffi::CandidateKind::Text,
                text: text.into(),
                code: code.map(Into::into).unwrap_or_default(),
                label: String::new(),
                action: ffi::CandidateAction::None,
            },
            CoreCandidate::ActionHint {
                text,
                label,
                action: xnheime_core::CandidateAction::AddUserEntry,
            } => Self {
                kind: ffi::CandidateKind::Action,
                text: text.into(),
                code: String::new(),
                label: label.into(),
                action: ffi::CandidateAction::AddUserEntry,
            },
        }
    }
}

impl From<CoreEffect> for ffi::Effect {
    fn from(effect: CoreEffect) -> Self {
        let mut result = Self {
            kind: ffi::EffectKind::HideCandidates,
            text: String::new(),
            secondary_text: String::new(),
            candidates: Vec::new(),
            selected_index: 0,
            character_index: 0,
        };
        match effect {
            CoreEffect::InsertText { text } => {
                result.kind = ffi::EffectKind::InsertText;
                result.text = text.into();
            }
            CoreEffect::InsertPairedText { before, after } => {
                result.kind = ffi::EffectKind::InsertPairedText;
                result.text = before.into();
                result.secondary_text = after.into();
            }
            CoreEffect::SetMarkedText { text } => {
                result.kind = ffi::EffectKind::SetMarkedText;
                result.text = text.into();
            }
            CoreEffect::ShowCandidates {
                candidates,
                selected_index,
                character_index,
            } => {
                result.kind = ffi::EffectKind::ShowCandidates;
                result.candidates = candidates.iter().cloned().map(Into::into).collect();
                result.selected_index = selected_index;
                result.character_index = character_index;
            }
            CoreEffect::HideCandidates => {}
            CoreEffect::DeleteBackward => result.kind = ffi::EffectKind::DeleteBackward,
            CoreEffect::ShowAddEntryDialog { code } => {
                result.kind = ffi::EffectKind::ShowAddEntry;
                result.text = code.into();
            }
        }
        result
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dispatch_returns_owned_candidates() {
        let mut session = new_session();
        let result = session.input_text(
            "n",
            &ffi::ExternalText {
                has_selected_text: false,
                selected_text: String::new(),
                has_clipboard_text: false,
                clipboard_text: String::new(),
            },
        );
        assert_eq!(result.mode, ffi::CompositionMode::Converting);
        assert_eq!(result.effects.len(), 2);
        assert!(!result.effects[1].candidates.is_empty());
        assert!(!result.effects[1].candidates[0].text.is_empty());
    }

    #[test]
    fn external_text_reaches_core_translators() {
        let mut session = new_session();
        let external_text = ffi::ExternalText {
            has_selected_text: true,
            selected_text: "好".into(),
            has_clipboard_text: false,
            clipboard_text: String::new(),
        };
        for input in ["o", "f"] {
            session.input_text(input, &external_text);
        }
        let result = session.input_text("i", &external_text);
        let candidates = &result
            .effects
            .iter()
            .find(|effect| effect.kind == ffi::EffectKind::ShowCandidates)
            .unwrap()
            .candidates;
        assert!(!candidates.is_empty());
        assert!(candidates.iter().all(|candidate| candidate.text == "好"));
    }
}
