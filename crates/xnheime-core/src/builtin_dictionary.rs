include!(concat!(env!("OUT_DIR"), "/flypy_index.rs"));

/// Numeric values are embedded in the generated dictionary index by build.rs.
#[derive(Clone, Copy, Debug, Default, Eq, Ord, PartialEq, PartialOrd)]
#[repr(u8)]
pub enum DictionaryMode {
    #[default]
    Expert = 0,
    Regular = 1,
    Beginner = 2,
}

impl DictionaryMode {
    const fn level(self) -> u8 {
        self as u8
    }
}

pub(crate) fn lookup_candidates(
    input: &str,
    mode: DictionaryMode,
) -> Vec<(&'static str, &'static str)> {
    if !is_flypy_code(input) {
        return Vec::new();
    }

    let start = ENTRIES.partition_point(|(code, _, _)| *code < input);
    let end = ENTRIES[start..].partition_point(|(code, _, _)| *code == input) + start;
    ENTRIES[start..end]
        .iter()
        .filter(|(_, _, minimum_mode)| *minimum_mode <= mode.level())
        .map(|(code, text, _)| (*code, *text))
        .collect()
}

pub(crate) fn lookup_candidates_matching(
    input: &str,
    mode: DictionaryMode,
) -> Vec<(&'static str, &'static str)> {
    if !is_flypy_pattern(input) {
        return Vec::new();
    }

    ENTRIES
        .iter()
        .filter(|(code, _, minimum_mode)| {
            *minimum_mode <= mode.level()
                && code.len() == input.len()
                && code_matches_pattern_prefix(code, input)
        })
        .map(|(code, text, _)| (*code, *text))
        .collect()
}

pub(crate) fn lookup_codes_for_character(
    character: char,
    mode: DictionaryMode,
) -> Vec<&'static str> {
    CHARACTER_CODES
        .binary_search_by_key(&character, |(candidate, _)| *candidate)
        .ok()
        .map(|index| {
            CHARACTER_CODES[index]
                .1
                .iter()
                .filter(|(_, minimum_mode)| *minimum_mode <= mode.level())
                .map(|(code, _)| *code)
                .collect()
        })
        .unwrap_or_default()
}

pub(crate) fn has_code_prefix(input: &str, mode: DictionaryMode) -> bool {
    if input.contains('`') {
        is_flypy_pattern(input)
            && ENTRIES.iter().any(|(code, _, minimum_mode)| {
                *minimum_mode <= mode.level() && code_matches_pattern_prefix(code, input)
            })
    } else {
        is_flypy_code(input)
            && PREFIXES
                .binary_search_by_key(&input, |(prefix, _)| *prefix)
                .is_ok_and(|index| PREFIXES[index].1 <= mode.level())
    }
}

pub(crate) fn code_matches_pattern_prefix(code: &str, pattern: &str) -> bool {
    code.len() >= pattern.len()
        && code
            .bytes()
            .zip(pattern.bytes())
            .all(|(actual, expected)| expected == b'`' || actual == expected)
}

fn is_flypy_pattern(input: &str) -> bool {
    !input.is_empty()
        && input
            .bytes()
            .all(|byte| matches!(byte, b'a'..=b'z' | b';' | b'\'' | b'`'))
}

pub(crate) fn is_flypy_code(input: &str) -> bool {
    !input.is_empty()
        && input
            .bytes()
            .all(|byte| matches!(byte, b'a'..=b'z' | b';' | b'\''))
}

#[cfg(test)]
mod tests {
    use super::{
        has_code_prefix, lookup_candidates, lookup_candidates_matching, lookup_codes_for_character,
        DictionaryMode,
    };

    #[test]
    fn looks_up_first_candidate_from_flypy_table() {
        assert_eq!(
            lookup_candidates("ni", DictionaryMode::Expert)
                .first()
                .map(|(_, word)| *word),
            Some("你")
        );
        assert_eq!(
            lookup_candidates("wo", DictionaryMode::Expert)
                .first()
                .map(|(_, word)| *word),
            Some("我")
        );
        assert_eq!(
            lookup_candidates("aakk", DictionaryMode::Expert)
                .first()
                .map(|(_, word)| *word),
            Some("啊")
        );
        assert!(lookup_candidates("hello", DictionaryMode::Expert).is_empty());
    }

    #[test]
    fn returns_ranked_candidates_without_duplicates() {
        let candidates: Vec<_> = lookup_candidates("oxy", DictionaryMode::Expert)
            .iter()
            .map(|(_, candidate)| *candidate)
            .collect();
        assert!(candidates.len() > 1);
        assert_eq!(candidates.first(), Some(&"又"));
        assert_eq!(
            candidates.len(),
            candidates
                .iter()
                .collect::<std::collections::HashSet<_>>()
                .len()
        );
    }

    #[test]
    fn respects_explicit_candidate_weights_within_a_dictionary() {
        let candidates: Vec<_> = lookup_candidates("obg", DictionaryMode::Expert)
            .iter()
            .map(|(_, candidate)| *candidate)
            .collect();
        let bone = candidates
            .iter()
            .position(|candidate| *candidate == "骨")
            .unwrap();
        let leather = candidates
            .iter()
            .position(|candidate| *candidate == "革")
            .unwrap();
        assert!(bone < leather, "weight 97 should sort before weight 96");
    }

    #[test]
    fn exposes_additional_tables_by_dictionary_mode() {
        assert!(!lookup_candidates("xqvg", DictionaryMode::Expert)
            .iter()
            .any(|(_, word)| *word == "修正"));
        assert!(lookup_candidates("xqvg", DictionaryMode::Regular)
            .iter()
            .any(|(_, word)| *word == "修正"));
        assert!(!lookup_candidates("aofe", DictionaryMode::Regular)
            .iter()
            .any(|(_, word)| *word == "嶅"));
        assert!(lookup_candidates("aofe", DictionaryMode::Beginner)
            .iter()
            .any(|(_, word)| *word == "嶅"));
    }

    #[test]
    fn checks_flypy_prefixes() {
        assert!(has_code_prefix("n", DictionaryMode::Expert));
        assert!(has_code_prefix("ni", DictionaryMode::Expert));
        assert!(has_code_prefix("aak", DictionaryMode::Expert));
        assert!(!has_code_prefix("hello", DictionaryMode::Expert));
        assert!(!has_code_prefix("N", DictionaryMode::Expert));
    }

    #[test]
    fn backtick_matches_one_unknown_code_position() {
        let matches = lookup_candidates_matching("n`", DictionaryMode::Expert);
        assert!(matches
            .iter()
            .any(|(code, word)| *code == "ni" && *word == "你"));
        assert!(matches
            .iter()
            .all(|(code, _)| code.starts_with('n') && code.len() == 2));
        assert!(has_code_prefix("n`", DictionaryMode::Expert));
        assert!(!has_code_prefix("zzzz`", DictionaryMode::Expert));
    }

    #[test]
    fn reverse_looks_up_codes_for_single_characters() {
        let codes = lookup_codes_for_character('你', DictionaryMode::Expert);
        assert!(codes.contains(&"ni"));
        assert!(lookup_codes_for_character('A', DictionaryMode::Expert).is_empty());
    }
}
