mod candidates;
mod code_buffer;
mod punctuation;
#[cfg(test)]
mod tests;

use crate::{has_code_prefix, DictionaryMode, UserDictionary, UserDictionaryLoadResult};
use candidates::{
    candidate_display_effects, candidates_for_buffer, inline_candidate_display_effects,
    is_addable_code,
};
use chrono::{DateTime, FixedOffset, Local};
use code_buffer::CodeBuffer;
use compact_str::{format_compact, CompactString};
use punctuation::{localized_punctuation, paired_fast_symbol};
use std::path::Path;
use std::sync::Arc;

const MAXIMUM_CODE_LENGTH: usize = 4;
const CANDIDATES_PER_ROW: usize = 9;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CandidateAction {
    AddUserEntry,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum CandidateItem {
    Candidate {
        text: CompactString,
        code: Option<CompactString>,
    },
    ActionHint {
        text: CompactString,
        label: CompactString,
        action: CandidateAction,
    },
}

impl CandidateItem {
    pub fn text(&self) -> &str {
        match self {
            Self::Candidate { text, .. } | Self::ActionHint { text, .. } => text,
        }
    }

    pub fn code(&self) -> Option<&str> {
        match self {
            Self::Candidate { code, .. } => code.as_deref(),
            Self::ActionHint { .. } => None,
        }
    }

    pub fn selection_label(&self) -> Option<&str> {
        match self {
            Self::ActionHint { label, .. } => Some(label),
            Self::Candidate { .. } => None,
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
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

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum CompositionEffect {
    InsertText {
        text: CompactString,
    },
    InsertPairedText {
        before: CompactString,
        after: CompactString,
    },
    SetMarkedText {
        text: CompactString,
    },
    ShowCandidates {
        candidates: Arc<[CandidateItem]>,
        selected_index: u32,
        character_index: u32,
    },
    HideCandidates,
    DeleteBackward,
    ShowAddEntryDialog {
        code: CompactString,
    },
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CompositionMode {
    Idle,
    Converting { candidate_count: u32 },
    Inline,
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct ConversionState {
    code: CodeBuffer,
    candidates: Arc<[CandidateItem]>,
    selected_index: usize,
}

impl ConversionState {
    /// A merged key does not say which of its letters was meant, so show the code
    /// of the candidate that would commit instead of the keys pressed.
    fn display_code(&self) -> CompactString {
        if self.code.is_ambiguous() {
            if let Some(code) = self
                .candidates
                .get(self.selected_index)
                .and_then(CandidateItem::code)
            {
                return CompactString::new(code);
            }
        }
        CompactString::new(self.code.primary())
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum InlineKind {
    UnmatchedCode,
    ExplicitAscii,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum CommitKind {
    Candidate,
    Code,
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct InlineState {
    buffer: CompactString,
    kind: InlineKind,
}

impl InlineState {
    fn can_add_entry(&self) -> bool {
        self.kind == InlineKind::UnmatchedCode && is_addable_code(&self.buffer)
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
enum Mode {
    Idle,
    Converting(ConversionState),
    Inline(InlineState),
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct CompositionState {
    mode: Mode,
    next_double_quote_is_opening: bool,
    next_single_quote_is_opening: bool,
    last_committed_text: Option<CompactString>,
}

impl Default for CompositionState {
    fn default() -> Self {
        Self {
            mode: Mode::Idle,
            next_double_quote_is_opening: true,
            next_single_quote_is_opening: true,
            last_committed_text: None,
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct DispatchContext {
    now: DateTime<FixedOffset>,
    selected_text: Option<String>,
    clipboard_text: Option<String>,
    dictionary_mode: DictionaryMode,
}

impl DispatchContext {
    fn now() -> Self {
        Self {
            now: Local::now().fixed_offset(),
            selected_text: None,
            clipboard_text: None,
            dictionary_mode: DictionaryMode::Expert,
        }
    }
}

#[derive(Default)]
pub struct CompositionSession {
    state: CompositionState,
    user_dictionary: UserDictionary,
    dictionary_mode: DictionaryMode,
}

impl CompositionSession {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn mode(&self) -> CompositionMode {
        match &self.state.mode {
            Mode::Idle => CompositionMode::Idle,
            Mode::Converting(conversion) => CompositionMode::Converting {
                candidate_count: conversion.candidates.len() as u32,
            },
            Mode::Inline(_) => CompositionMode::Inline,
        }
    }

    pub fn dictionary_mode(&self) -> DictionaryMode {
        self.dictionary_mode
    }

    pub fn set_dictionary_mode(&mut self, mode: DictionaryMode) {
        if mode == self.dictionary_mode {
            return;
        }
        self.dictionary_mode = mode;
        self.state.mode = Mode::Idle;
    }

    pub fn candidates(&self) -> Vec<CandidateItem> {
        match &self.state.mode {
            Mode::Converting(conversion) => conversion.candidates.to_vec(),
            Mode::Idle | Mode::Inline(_) => Vec::new(),
        }
    }

    pub fn candidates_range(&self, offset: usize, limit: usize) -> Vec<CandidateItem> {
        match &self.state.mode {
            Mode::Converting(conversion) => conversion
                .candidates
                .iter()
                .skip(offset)
                .take(limit)
                .cloned()
                .collect(),
            Mode::Idle | Mode::Inline(_) => Vec::new(),
        }
    }

    pub fn load_user_dictionary_directory(
        &mut self,
        path: &Path,
    ) -> std::io::Result<UserDictionaryLoadResult> {
        let (dictionary, result) = UserDictionary::load_directory(path)?;
        self.user_dictionary = dictionary;
        Ok(result)
    }

    /// Replaces only dictionary data, preserving composition history and punctuation state.
    pub fn replace_user_dictionary(&mut self, dictionary: UserDictionary) {
        self.user_dictionary = dictionary;
    }

    pub fn take_user_dictionary(&mut self) -> UserDictionary {
        std::mem::take(&mut self.user_dictionary)
    }

    pub fn dispatch(&mut self, event: CompositionEvent) -> Vec<CompositionEffect> {
        let mut context = DispatchContext::now();
        context.dictionary_mode = self.dictionary_mode;
        self.dispatch_with_context(event, &context)
    }

    pub fn dispatch_with_external_text(
        &mut self,
        event: CompositionEvent,
        selected_text: Option<String>,
        clipboard_text: Option<String>,
    ) -> Vec<CompositionEffect> {
        let mut context = DispatchContext::now();
        context.selected_text = selected_text;
        context.clipboard_text = clipboard_text;
        context.dictionary_mode = self.dictionary_mode;
        self.dispatch_with_context(event, &context)
    }

    fn dispatch_with_context(
        &mut self,
        event: CompositionEvent,
        context: &DispatchContext,
    ) -> Vec<CompositionEffect> {
        let previous_state = std::mem::take(&mut self.state);
        let (state, effects) = reduce(previous_state, event, context, &self.user_dictionary);
        self.state = state;
        effects
    }
}

fn reduce(
    state: CompositionState,
    event: CompositionEvent,
    context: &DispatchContext,
    user_dictionary: &UserDictionary,
) -> (CompositionState, Vec<CompositionEffect>) {
    match event {
        CompositionEvent::InputText { text } => input_text(state, text, context, user_dictionary),
        CompositionEvent::InsertDirect { text } => {
            let (state, mut effects) = commit(state, CommitKind::Code);
            effects.push(CompositionEffect::InsertText { text: text.into() });
            (state, effects)
        }
        CompositionEvent::EnterInline { text } => enter_inline_mode(state, text),
        CompositionEvent::Commit => commit(state, CommitKind::Candidate),
        CompositionEvent::CommitCode => commit(state, CommitKind::Code),
        CompositionEvent::Cancel { clear_marked_text } => {
            let mut state = state;
            state.mode = Mode::Idle;
            let mut effects = vec![CompositionEffect::HideCandidates];
            if clear_marked_text {
                effects.push(CompositionEffect::SetMarkedText {
                    text: CompactString::new(""),
                });
            }
            (state, effects)
        }
        CompositionEvent::MoveCandidate { offset } => move_candidate(state, offset),
        CompositionEvent::SelectCandidate { index } => select_candidate(state, index as usize),
        CompositionEvent::InputMergedKey { letters } => {
            input_merged_key(state, letters, None, context, user_dictionary)
        }
        CompositionEvent::InputWeightedMergedKey {
            letters,
            primary_weight,
        } => input_merged_key(
            state,
            letters,
            Some(primary_weight),
            context,
            user_dictionary,
        ),
    }
}

fn input_text(
    state: CompositionState,
    text: String,
    context: &DispatchContext,
    user_dictionary: &UserDictionary,
) -> (CompositionState, Vec<CompositionEffect>) {
    if text.chars().count() != 1 {
        let (state, mut effects) = commit(state, CommitKind::Candidate);
        effects.push(CompositionEffect::InsertText { text: text.into() });
        return (state, effects);
    }

    let character = text.chars().next().expect("single-character input");
    if character == '\u{7f}' || character == '\u{8}' {
        return delete_backward(state, context, user_dictionary);
    }
    if character.is_ascii() && !character.is_ascii_control() {
        return input_ascii(state, text, context, user_dictionary);
    }

    let (state, mut effects) = commit(state, CommitKind::Candidate);
    effects.push(CompositionEffect::InsertText { text: text.into() });
    (state, effects)
}

fn input_ascii(
    mut state: CompositionState,
    text: String,
    context: &DispatchContext,
    user_dictionary: &UserDictionary,
) -> (CompositionState, Vec<CompositionEffect>) {
    if let Mode::Inline(inline) = &mut state.mode {
        if text == "+" && inline.can_add_entry() {
            let code = inline.buffer.clone();
            return (state, vec![CompositionEffect::ShowAddEntryDialog { code }]);
        }
        inline.buffer.push_str(&text);
        let value = inline.buffer.clone();
        let can_add_entry = inline.can_add_entry();
        let mut effects = vec![CompositionEffect::SetMarkedText {
            text: value.clone(),
        }];
        effects.extend(inline_candidate_display_effects(&value, can_add_entry));
        return (state, effects);
    }

    let selection_index = match &state.mode {
        Mode::Converting(conversion) => candidate_selection_index(
            &text,
            conversion.candidates.len(),
            conversion.selected_index,
        ),
        Mode::Idle | Mode::Inline(_) => None,
    };
    if let Some(index) = selection_index {
        let Mode::Converting(conversion) = &mut state.mode else {
            unreachable!("candidate selection requires conversion mode");
        };
        conversion.selected_index = index;
        return commit(state, CommitKind::Candidate);
    }

    let has_conversion = matches!(state.mode, Mode::Converting(_));

    if text == " " {
        return if has_conversion {
            commit(state, CommitKind::Candidate)
        } else {
            (
                state,
                vec![CompositionEffect::InsertText { text: text.into() }],
            )
        };
    }

    if text == "+" {
        if let Some(code) = match &state.mode {
            Mode::Converting(conversion) => Some(conversion.display_code()),
            Mode::Idle | Mode::Inline(_) => None,
        } {
            return (state, vec![CompositionEffect::ShowAddEntryDialog { code }]);
        }
    }

    if let Some(punctuation) = localized_punctuation(&mut state, &text) {
        let (state, mut effects) = commit(state, CommitKind::Candidate);
        effects.push(CompositionEffect::InsertText { text: punctuation });
        return (state, effects);
    }

    if text == "`" && !has_conversion {
        return (
            state,
            vec![CompositionEffect::InsertText { text: text.into() }],
        );
    }

    let character = text.as_bytes()[0];
    if !is_code_character(character) {
        let (state, mut effects) = commit(state, CommitKind::Candidate);
        effects.push(CompositionEffect::InsertText { text: text.into() });
        return (state, effects);
    }

    extend_code(
        state,
        &text.to_ascii_lowercase(),
        &text,
        context,
        user_dictionary,
    )
}

fn input_merged_key(
    state: CompositionState,
    letters: String,
    primary_weight: Option<u16>,
    context: &DispatchContext,
    user_dictionary: &UserDictionary,
) -> (CompositionState, Vec<CompositionEffect>) {
    let letters = letters.to_ascii_lowercase();
    let Some(first) = letters.chars().next() else {
        return (state, Vec::new());
    };
    let merged = letters.len() == 2 && letters.bytes().all(|byte| byte.is_ascii_lowercase());
    if !merged || matches!(state.mode, Mode::Inline(_)) {
        return input_text(state, first.to_string(), context, user_dictionary);
    }
    extend_code_weighted(
        state,
        &letters,
        &first.to_string(),
        primary_weight.unwrap_or(500),
        context,
        user_dictionary,
    )
}

/// Appends one keystroke, which is one letter or a merged key's two letters.
fn extend_code(
    state: CompositionState,
    letters: &str,
    fallback_text: &str,
    context: &DispatchContext,
    user_dictionary: &UserDictionary,
) -> (CompositionState, Vec<CompositionEffect>) {
    extend_code_weighted(state, letters, fallback_text, 500, context, user_dictionary)
}

fn extend_code_weighted(
    state: CompositionState,
    letters: &str,
    fallback_text: &str,
    primary_weight: u16,
    context: &DispatchContext,
    user_dictionary: &UserDictionary,
) -> (CompositionState, Vec<CompositionEffect>) {
    let mut code = match &state.mode {
        Mode::Converting(conversion) => conversion.code.clone(),
        Mode::Idle | Mode::Inline(_) => CodeBuffer::new(),
    };
    code.push_weighted(letters, primary_weight);
    if is_valid_code_prefix(&code, user_dictionary, context.dictionary_mode) {
        return begin_conversion(state, code, context, user_dictionary);
    }
    if matches!(&state.mode, Mode::Converting(conversion) if {
        conversion.code.len() == MAXIMUM_CODE_LENGTH && !conversion.candidates.is_empty()
    }) {
        let (state, mut effects) = commit(state, CommitKind::Candidate);
        let (state, following_effects) = extend_code_weighted(
            state,
            letters,
            fallback_text,
            primary_weight,
            context,
            user_dictionary,
        );
        effects.extend(following_effects);
        return (state, effects);
    }
    let inline_prefix = match &state.mode {
        Mode::Converting(conversion) => Some(conversion.display_code()),
        Mode::Idle | Mode::Inline(_) => None,
    };
    match inline_prefix {
        Some(prefix) => enter_inline(state, &prefix, fallback_text, InlineKind::UnmatchedCode),
        None => (
            state,
            vec![CompositionEffect::InsertText {
                text: fallback_text.into(),
            }],
        ),
    }
}

fn delete_backward(
    mut state: CompositionState,
    context: &DispatchContext,
    user_dictionary: &UserDictionary,
) -> (CompositionState, Vec<CompositionEffect>) {
    let mut buffer = match std::mem::replace(&mut state.mode, Mode::Idle) {
        Mode::Idle => return (state, vec![CompositionEffect::DeleteBackward]),
        Mode::Converting(conversion) => conversion.code,
        Mode::Inline(inline) => CodeBuffer::from_code(&inline.buffer),
    };
    buffer.pop();
    if buffer.is_empty() {
        state.mode = Mode::Idle;
        return (
            state,
            vec![
                CompositionEffect::SetMarkedText {
                    text: CompactString::new(""),
                },
                CompositionEffect::HideCandidates,
            ],
        );
    }
    if is_valid_code_prefix(&buffer, user_dictionary, context.dictionary_mode) {
        begin_conversion(state, buffer, context, user_dictionary)
    } else {
        let text = CompactString::new(buffer.primary());
        let inline = InlineState {
            buffer: text.clone(),
            kind: InlineKind::UnmatchedCode,
        };
        let can_add_entry = inline.can_add_entry();
        state.mode = Mode::Inline(inline);
        let mut effects = vec![CompositionEffect::SetMarkedText { text: text.clone() }];
        effects.extend(inline_candidate_display_effects(&text, can_add_entry));
        (state, effects)
    }
}

fn begin_conversion(
    mut state: CompositionState,
    code: CodeBuffer,
    context: &DispatchContext,
    user_dictionary: &UserDictionary,
) -> (CompositionState, Vec<CompositionEffect>) {
    let candidates = candidates_for_buffer(
        &code,
        state.last_committed_text.as_deref(),
        context,
        user_dictionary,
    )
    .into();
    let conversion = ConversionState {
        code,
        candidates,
        selected_index: 0,
    };
    let mut effects = vec![CompositionEffect::SetMarkedText {
        text: conversion.display_code(),
    }];
    effects.extend(candidate_display_effects(&conversion));
    state.mode = Mode::Converting(conversion);
    (state, effects)
}

fn enter_inline_mode(
    mut state: CompositionState,
    text: String,
) -> (CompositionState, Vec<CompositionEffect>) {
    match std::mem::replace(&mut state.mode, Mode::Idle) {
        Mode::Idle => (
            state,
            vec![CompositionEffect::InsertText { text: text.into() }],
        ),
        Mode::Converting(conversion) => {
            let prefix = conversion.display_code();
            enter_inline(state, &prefix, &text, InlineKind::ExplicitAscii)
        }
        Mode::Inline(inline) => {
            enter_inline(state, &inline.buffer, &text, InlineKind::ExplicitAscii)
        }
    }
}

fn enter_inline(
    mut state: CompositionState,
    buffer: &str,
    text: &str,
    kind: InlineKind,
) -> (CompositionState, Vec<CompositionEffect>) {
    let value = format_compact!("{buffer}{text}");
    let inline = InlineState {
        buffer: value.clone(),
        kind,
    };
    let can_add_entry = inline.can_add_entry();
    state.mode = Mode::Inline(inline);
    let mut effects = vec![CompositionEffect::SetMarkedText {
        text: value.clone(),
    }];
    effects.extend(inline_candidate_display_effects(&value, can_add_entry));
    (state, effects)
}

fn commit(
    mut state: CompositionState,
    kind: CommitKind,
) -> (CompositionState, Vec<CompositionEffect>) {
    let (text, committed_candidate, pairing) = match &state.mode {
        Mode::Idle => return (state, Vec::new()),
        Mode::Inline(inline) => (inline.buffer.clone(), None, None),
        Mode::Converting(conversion) => {
            if kind == CommitKind::Code {
                (conversion.display_code(), None, None)
            } else {
                let candidate = conversion
                    .candidates
                    .get(conversion.selected_index)
                    .map(|candidate| CompactString::new(candidate.text()));
                let text = candidate
                    .clone()
                    .unwrap_or_else(|| conversion.display_code());
                if let Some(after) = paired_fast_symbol(conversion.code.primary(), &text) {
                    (format_compact!("{text}{after}"), Some(text), Some(after))
                } else {
                    (text, candidate, None)
                }
            }
        }
    };
    if committed_candidate.is_some() {
        state.last_committed_text = Some(text.clone());
    }
    state.mode = Mode::Idle;
    let insertion = if let Some(after) = pairing {
        let before = CompactString::new(text.strip_suffix(after).unwrap_or(&text));
        CompositionEffect::InsertPairedText {
            before,
            after: after.into(),
        }
    } else {
        CompositionEffect::InsertText { text }
    };
    (state, vec![insertion, CompositionEffect::HideCandidates])
}

fn move_candidate(
    mut state: CompositionState,
    offset: i32,
) -> (CompositionState, Vec<CompositionEffect>) {
    let previous_mode = std::mem::replace(&mut state.mode, Mode::Idle);
    let Mode::Converting(mut conversion) = previous_mode else {
        state.mode = previous_mode;
        return (state, Vec::new());
    };
    let count = conversion.candidates.len();
    if count <= 1 {
        state.mode = Mode::Converting(conversion);
        return (state, Vec::new());
    }
    conversion.selected_index = if offset.unsigned_abs() as usize == CANDIDATES_PER_ROW {
        let row_count = count.div_ceil(CANDIDATES_PER_ROW);
        let row = conversion.selected_index / CANDIDATES_PER_ROW;
        let column = conversion.selected_index % CANDIDATES_PER_ROW;
        let target_row = (row as i32 + offset.signum()).clamp(0, row_count as i32 - 1) as usize;
        (target_row * CANDIDATES_PER_ROW + column).min(count - 1)
    } else {
        (conversion.selected_index as i32 + offset).rem_euclid(count as i32) as usize
    };
    let mut effects = Vec::new();
    if conversion.code.is_ambiguous() {
        effects.push(CompositionEffect::SetMarkedText {
            text: conversion.display_code(),
        });
    }
    effects.extend(candidate_display_effects(&conversion));
    state.mode = Mode::Converting(conversion);
    (state, effects)
}

/// Selects an absolute candidate and commits it as one state transition. UI clients
/// should prefer this over a move followed by commit: besides avoiding an unnecessary
/// candidate rebuild, it cannot expose the intermediate selection to another event.
fn select_candidate(
    mut state: CompositionState,
    index: usize,
) -> (CompositionState, Vec<CompositionEffect>) {
    let Mode::Converting(conversion) = &mut state.mode else {
        return (state, Vec::new());
    };
    if index >= conversion.candidates.len() {
        return (state, Vec::new());
    }
    conversion.selected_index = index;
    commit(state, CommitKind::Candidate)
}

fn candidate_selection_index(
    input: &str,
    candidate_count: usize,
    selected_index: usize,
) -> Option<usize> {
    let row_start = selected_index / CANDIDATES_PER_ROW * CANDIDATES_PER_ROW;
    if input == ";" {
        let index = row_start + 1;
        return (index < candidate_count).then_some(index);
    }
    let value = input.as_bytes().first().copied()?;
    if !(b'1'..=b'9').contains(&value) {
        return None;
    }
    let index = row_start + (value - b'1') as usize;
    (index < candidate_count).then_some(index)
}

fn is_valid_code_prefix(
    code: &CodeBuffer,
    user_dictionary: &UserDictionary,
    dictionary_mode: DictionaryMode,
) -> bool {
    code.len() <= MAXIMUM_CODE_LENGTH
        && code
            .expansions()
            .iter()
            .any(|code| is_valid_concrete_prefix(code, user_dictionary, dictionary_mode))
}

fn is_valid_concrete_prefix(
    code: &str,
    user_dictionary: &UserDictionary,
    dictionary_mode: DictionaryMode,
) -> bool {
    has_code_prefix(code, dictionary_mode)
        || user_dictionary.has_prefix(code)
        || [";", ";f", "o", "of", "ofi", "or", "orq", "ou", "ouj"]
            .iter()
            .any(|special| special.starts_with(code))
}

fn is_code_character(character: u8) -> bool {
    character.is_ascii_alphabetic() || matches!(character, b'\'' | b';' | b'`')
}
