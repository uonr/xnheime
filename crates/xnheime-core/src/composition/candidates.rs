use super::code_buffer::CodeBuffer;
use super::{
    CandidateAction, CandidateItem, CompositionEffect, ConversionState, DispatchContext,
    MAXIMUM_CODE_LENGTH,
};
use crate::{
    lookup_candidates, lookup_candidates_matching, lookup_codes_for_character, DictionaryLayer,
    DictionaryMode, UserDictionary,
};
use compact_str::{format_compact, CompactString};
use std::cmp::Ordering;
use std::collections::{BinaryHeap, HashSet};

/// Merged keys make several codes possible at once. Their candidate lists are
/// merged-code likelihood is combined with each dictionary candidate's rank.
pub(super) fn candidates_for_buffer(
    code: &CodeBuffer,
    last_committed_text: Option<&str>,
    context: &DispatchContext,
    user_dictionary: &UserDictionary,
) -> Vec<CandidateItem> {
    let expansions = code.weighted_expansions();
    let [only] = expansions.as_slice() else {
        let lists: Vec<(f64, Vec<CandidateItem>)> = expansions
            .iter()
            .map(|(expansion, weight)| {
                let candidates =
                    candidates_for(expansion, last_committed_text, context, user_dictionary)
                        .into_iter()
                        .map(|candidate| labelled_with_code(candidate, expansion))
                        .collect();
                (*weight, candidates)
            })
            .collect();
        return merge_by_weighted_rank(&lists);
    };
    candidates_for(&only.0, last_committed_text, context, user_dictionary)
}

fn labelled_with_code(candidate: CandidateItem, expansion: &str) -> CandidateItem {
    match candidate {
        CandidateItem::Candidate { text, code } => CandidateItem::Candidate {
            text,
            code: Some(code.unwrap_or_else(|| expansion.into())),
        },
        hint @ CandidateItem::ActionHint { .. } => hint,
    }
}

fn merge_by_weighted_rank(lists: &[(f64, Vec<CandidateItem>)]) -> Vec<CandidateItem> {
    #[derive(Clone, Copy)]
    struct Cursor {
        score: f64,
        rank: usize,
        list: usize,
    }
    impl PartialEq for Cursor {
        fn eq(&self, other: &Self) -> bool {
            self.score == other.score && self.rank == other.rank && self.list == other.list
        }
    }
    impl Eq for Cursor {}
    impl PartialOrd for Cursor {
        fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
            Some(self.cmp(other))
        }
    }
    impl Ord for Cursor {
        fn cmp(&self, other: &Self) -> Ordering {
            other
                .score
                .total_cmp(&self.score)
                .then_with(|| other.rank.cmp(&self.rank))
                .then_with(|| other.list.cmp(&self.list))
        }
    }

    let score = |list: usize, rank: usize| (rank + 1) as f64 / lists[list].0.max(0.001);
    let mut heap = BinaryHeap::new();
    for (list, (_, candidates)) in lists.iter().enumerate() {
        if !candidates.is_empty() {
            heap.push(Cursor {
                score: score(list, 0),
                rank: 0,
                list,
            });
        }
    }
    let mut seen = HashSet::new();
    let mut candidates = Vec::new();
    while let Some(cursor) = heap.pop() {
        let candidate = &lists[cursor.list].1[cursor.rank];
        if seen.insert(CompactString::new(candidate.text())) {
            candidates.push(candidate.clone());
        }
        let rank = cursor.rank + 1;
        if rank < lists[cursor.list].1.len() {
            heap.push(Cursor {
                score: score(cursor.list, rank),
                rank,
                list: cursor.list,
            });
        }
    }
    candidates
}

fn candidates_for(
    input: &str,
    last_committed_text: Option<&str>,
    context: &DispatchContext,
    user_dictionary: &UserDictionary,
) -> Vec<CandidateItem> {
    let dynamic = match input {
        ";f" => last_committed_text.map(|text| vec![CompactString::new(text)]),
        "orq" => Some(vec![
            format_compact!("{}", context.now.format("%Y年%m月%d日")),
            format_compact!("{}", context.now.format("%Y-%m-%d")),
        ]),
        "ouj" => Some(vec![
            format_compact!("{}", context.now.format("%H:%M")),
            format_compact!("{}", context.now.timestamp()),
        ]),
        _ => None,
    };
    if let Some(dynamic) = dynamic {
        return dynamic
            .into_iter()
            .map(|text| CandidateItem::Candidate { text, code: None })
            .collect();
    }
    if input == "ofi" {
        let selected_candidates = reverse_lookup_candidates(
            context.selected_text.as_deref(),
            user_dictionary,
            context.dictionary_mode,
        );
        if !selected_candidates.is_empty() {
            return selected_candidates;
        }
        let clipboard_candidates = reverse_lookup_candidates(
            context.clipboard_text.as_deref(),
            user_dictionary,
            context.dictionary_mode,
        );
        return if clipboard_candidates.is_empty() {
            reverse_lookup_candidates(
                last_committed_text,
                user_dictionary,
                context.dictionary_mode,
            )
        } else {
            clipboard_candidates
        };
    }
    if input.contains('`') {
        let mut seen = HashSet::new();
        let mut candidates = Vec::new();
        for (code, text) in user_dictionary.pattern_candidates(input, DictionaryLayer::BeforeSystem)
        {
            if seen.insert(text) {
                candidates.push(CandidateItem::Candidate {
                    text: text.into(),
                    code: Some(code.into()),
                });
            }
        }
        for (code, text) in lookup_candidates_matching(input, context.dictionary_mode) {
            if seen.insert(text) {
                candidates.push(CandidateItem::Candidate {
                    text: CompactString::const_new(text),
                    code: Some(CompactString::const_new(code)),
                });
            }
        }
        for (code, text) in user_dictionary.pattern_candidates(input, DictionaryLayer::AfterSystem)
        {
            if seen.insert(text) {
                candidates.push(CandidateItem::Candidate {
                    text: text.into(),
                    code: Some(code.into()),
                });
            }
        }
        candidates.sort_by_key(|candidate| wildcard_candidate_category(candidate.text()));
        candidates
    } else {
        let mut seen = HashSet::new();
        let mut candidates = Vec::new();
        for text in user_dictionary.candidates(input, DictionaryLayer::BeforeSystem) {
            if seen.insert(text) {
                candidates.push(CandidateItem::Candidate {
                    text: text.into(),
                    code: None,
                });
            }
        }
        for (_, text) in lookup_candidates(input, context.dictionary_mode) {
            if seen.insert(text) {
                candidates.push(CandidateItem::Candidate {
                    text: CompactString::const_new(text),
                    code: None,
                });
            }
        }
        for text in user_dictionary.candidates(input, DictionaryLayer::AfterSystem) {
            if seen.insert(text) {
                candidates.push(CandidateItem::Candidate {
                    text: text.into(),
                    code: None,
                });
            }
        }
        candidates
    }
}

pub(super) fn reverse_lookup_candidates(
    text: Option<&str>,
    user_dictionary: &UserDictionary,
    dictionary_mode: DictionaryMode,
) -> Vec<CandidateItem> {
    let mut candidates = Vec::new();
    for character in text.unwrap_or_default().chars() {
        let mut push_candidate = |code: CompactString| {
            let candidate = CandidateItem::Candidate {
                text: format_compact!("{character}"),
                code: Some(code),
            };
            if !candidates.contains(&candidate) {
                candidates.push(candidate);
            }
        };
        for code in user_dictionary.codes_for_character(character, DictionaryLayer::BeforeSystem) {
            push_candidate(code.clone());
        }
        for code in lookup_codes_for_character(character, dictionary_mode) {
            push_candidate(CompactString::const_new(code));
        }
        for code in user_dictionary.codes_for_character(character, DictionaryLayer::AfterSystem) {
            push_candidate(code.clone());
        }
    }
    candidates
}

pub(super) fn wildcard_candidate_category(text: &str) -> u8 {
    let mut characters = text.chars();
    let Some(first) = characters.next() else {
        return 2;
    };
    if is_cjk_ideograph(first) && characters.next().is_none() {
        0
    } else if text.chars().any(is_cjk_ideograph) {
        1
    } else {
        2
    }
}

pub(super) fn is_cjk_ideograph(character: char) -> bool {
    matches!(
        character as u32,
        0x3400..=0x4DBF
            | 0x4E00..=0x9FFF
            | 0xF900..=0xFAFF
            | 0x20000..=0x2FA1F
            | 0x30000..=0x323AF
    )
}

pub(super) fn candidate_display_effects(conversion: &ConversionState) -> Vec<CompositionEffect> {
    if conversion.candidates.is_empty() {
        add_entry_candidate_display_effects(&conversion.display_code())
    } else {
        vec![CompositionEffect::ShowCandidates {
            candidates: conversion.candidates.clone(),
            selected_index: conversion.selected_index as u32,
            character_index: conversion.display_code().encode_utf16().count() as u32,
        }]
    }
}

pub(super) fn inline_candidate_display_effects(
    buffer: &str,
    can_add_entry: bool,
) -> Vec<CompositionEffect> {
    if can_add_entry {
        add_entry_candidate_display_effects(buffer)
    } else {
        vec![CompositionEffect::HideCandidates]
    }
}

pub(super) fn add_entry_candidate_display_effects(code: &str) -> Vec<CompositionEffect> {
    vec![CompositionEffect::ShowCandidates {
        candidates: vec![CandidateItem::ActionHint {
            text: "新增".into(),
            label: "+".into(),
            action: CandidateAction::AddUserEntry,
        }]
        .into(),
        selected_index: 0,
        character_index: code.encode_utf16().count() as u32,
    }]
}

pub(super) fn is_addable_code(code: &str) -> bool {
    code.len() <= MAXIMUM_CODE_LENGTH && crate::is_flypy_code(code)
}
