use compact_str::{format_compact, CompactString};

/// One entry per keystroke. A merged key stands for two letters at once, so the
/// buffer expands to several concrete codes that all have to be looked up.
#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub(super) struct CodeBuffer {
    primary: CompactString,
    secondary: CompactString,
    primary_weights: Vec<u16>,
}

impl CodeBuffer {
    pub(super) fn new() -> Self {
        Self::default()
    }

    pub(super) fn from_code(code: &str) -> Self {
        Self {
            primary: code.into(),
            secondary: code.into(),
            primary_weights: vec![1000; code.chars().count()],
        }
    }

    #[cfg(test)]
    pub(super) fn push(&mut self, letters: &str) {
        self.push_weighted(letters, 500);
    }

    pub(super) fn push_weighted(&mut self, letters: &str, primary_weight: u16) {
        let mut letters = letters.chars();
        let Some(first) = letters.next() else {
            return;
        };
        self.primary.push(first);
        let second = letters.next().unwrap_or(first);
        self.secondary.push(second);
        self.primary_weights.push(if second == first {
            1000
        } else {
            primary_weight.clamp(1, 999)
        });
    }

    pub(super) fn pop(&mut self) {
        self.primary.pop();
        self.secondary.pop();
        self.primary_weights.pop();
    }

    pub(super) fn len(&self) -> usize {
        self.primary.len()
    }

    pub(super) fn is_empty(&self) -> bool {
        self.primary.is_empty()
    }

    pub(super) fn is_ambiguous(&self) -> bool {
        self.primary != self.secondary
    }

    pub(super) fn primary(&self) -> &str {
        &self.primary
    }

    pub(super) fn expansions(&self) -> Vec<CompactString> {
        self.weighted_expansions()
            .into_iter()
            .map(|(code, _)| code)
            .collect()
    }

    pub(super) fn weighted_expansions(&self) -> Vec<(CompactString, f64)> {
        let mut codes = vec![(CompactString::default(), 1.0)];
        for ((primary, secondary), primary_weight) in self
            .primary
            .chars()
            .zip(self.secondary.chars())
            .zip(self.primary_weights.iter().copied())
        {
            let primary_weight = f64::from(primary_weight) / 1000.0;
            let mut next = Vec::with_capacity(codes.len() * 2);
            for (code, weight) in &codes {
                next.push((format_compact!("{code}{primary}"), weight * primary_weight));
                if secondary != primary {
                    next.push((
                        format_compact!("{code}{secondary}"),
                        weight * (1.0 - primary_weight),
                    ));
                }
            }
            codes = next;
        }
        codes
    }
}

#[cfg(test)]
mod tests {
    use super::CodeBuffer;

    #[test]
    fn unambiguous_buffer_has_a_single_expansion() {
        let mut buffer = CodeBuffer::new();
        buffer.push("n");
        buffer.push("i");
        assert!(!buffer.is_ambiguous());
        assert_eq!(buffer.primary(), "ni");
        assert_eq!(buffer.expansions(), vec!["ni"]);
    }

    #[test]
    fn merged_keys_expand_leftmost_position_first() {
        let mut buffer = CodeBuffer::new();
        buffer.push("as");
        buffer.push("df");
        assert!(buffer.is_ambiguous());
        assert_eq!(buffer.primary(), "ad");
        assert_eq!(buffer.expansions(), vec!["ad", "af", "sd", "sf"]);
    }

    #[test]
    fn expansions_grow_only_with_merged_positions() {
        let mut buffer = CodeBuffer::new();
        buffer.push("bn");
        buffer.push("i");
        buffer.push("zx");
        assert_eq!(buffer.len(), 3);
        assert_eq!(buffer.expansions(), vec!["biz", "bix", "niz", "nix"]);
    }

    #[test]
    fn popping_keeps_the_remaining_ambiguity() {
        let mut buffer = CodeBuffer::new();
        buffer.push("qw");
        buffer.push("er");
        buffer.pop();
        assert_eq!(buffer.expansions(), vec!["q", "w"]);
        buffer.pop();
        assert!(buffer.is_empty());
    }

    #[test]
    fn a_plain_code_round_trips() {
        let buffer = CodeBuffer::from_code("ofi");
        assert!(!buffer.is_ambiguous());
        assert_eq!(buffer.expansions(), vec!["ofi"]);
    }
}
