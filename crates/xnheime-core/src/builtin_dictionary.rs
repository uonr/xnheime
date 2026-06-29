include!(concat!(env!("OUT_DIR"), "/flypy_index.rs"));

pub(crate) fn lookup_candidates(input: &str) -> &'static [(&'static str, &'static str)] {
    if !is_flypy_code(input) {
        return &[];
    }

    let start = ENTRIES.partition_point(|(code, _)| *code < input);
    let end = ENTRIES[start..].partition_point(|(code, _)| *code == input) + start;
    &ENTRIES[start..end]
}

pub(crate) fn lookup_candidates_matching(input: &str) -> Vec<(&'static str, &'static str)> {
    if !is_flypy_pattern(input) {
        return Vec::new();
    }

    ENTRIES
        .iter()
        .copied()
        .filter(|(code, _)| code.len() == input.len() && code_matches_pattern_prefix(code, input))
        .collect()
}

pub(crate) fn lookup_codes_for_character(character: char) -> &'static [&'static str] {
    CHARACTER_CODES
        .binary_search_by_key(&character, |(candidate, _)| *candidate)
        .ok()
        .map(|index| CHARACTER_CODES[index].1)
        .unwrap_or_default()
}

pub(crate) fn has_code_prefix(input: &str) -> bool {
    if input.contains('`') {
        is_flypy_pattern(input)
            && ENTRIES
                .iter()
                .any(|(code, _)| code_matches_pattern_prefix(code, input))
    } else {
        is_flypy_code(input) && PREFIXES.binary_search(&input).is_ok()
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
    };

    #[test]
    fn looks_up_first_candidate_from_flypy_table() {
        assert_eq!(
            lookup_candidates("ni").first().map(|(_, word)| *word),
            Some("你")
        );
        assert_eq!(
            lookup_candidates("wo").first().map(|(_, word)| *word),
            Some("我")
        );
        assert_eq!(
            lookup_candidates("aakk").first().map(|(_, word)| *word),
            Some("啊")
        );
        assert!(lookup_candidates("hello").is_empty());
    }

    #[test]
    fn returns_ranked_candidates_without_duplicates() {
        let candidates: Vec<_> = lookup_candidates("oxy")
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
        let candidates: Vec<_> = lookup_candidates("obg")
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
    fn checks_flypy_prefixes() {
        assert!(has_code_prefix("n"));
        assert!(has_code_prefix("ni"));
        assert!(has_code_prefix("aak"));
        assert!(!has_code_prefix("hello"));
        assert!(!has_code_prefix("N"));
    }

    #[test]
    fn backtick_matches_one_unknown_code_position() {
        let matches = lookup_candidates_matching("n`");
        assert!(matches
            .iter()
            .any(|(code, word)| *code == "ni" && *word == "你"));
        assert!(matches
            .iter()
            .all(|(code, _)| code.starts_with('n') && code.len() == 2));
        assert!(has_code_prefix("n`"));
        assert!(!has_code_prefix("zzzz`"));
    }

    #[test]
    fn reverse_looks_up_codes_for_single_characters() {
        let codes = lookup_codes_for_character('你');
        assert!(codes.contains(&"ni"));
        assert!(lookup_codes_for_character('A').is_empty());
    }
}
