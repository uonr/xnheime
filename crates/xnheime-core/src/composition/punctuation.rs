use super::{CompositionState, Mode};
use compact_str::CompactString;

pub(super) fn paired_fast_symbol(code: &str, candidate: &str) -> Option<&'static str> {
    let closing = match (code, candidate) {
        (";q", "：“") => "”",
        (";e", "（") => "）",
        (";y", "《") => "》",
        (";o" | ";h", "[") => "]",
        (";k", "(") => ")",
        (";z", "“") => "”",
        _ => return None,
    };
    Some(closing)
}

pub(super) fn localized_punctuation(
    state: &mut CompositionState,
    input: &str,
) -> Option<CompactString> {
    if input == "'" {
        if !matches!(state.mode, Mode::Idle) {
            return None;
        }
        let punctuation = if state.next_single_quote_is_opening {
            "‘"
        } else {
            "’"
        };
        state.next_single_quote_is_opening = !state.next_single_quote_is_opening;
        return Some(punctuation.into());
    }
    if input == "\"" {
        let punctuation = if state.next_double_quote_is_opening {
            "“"
        } else {
            "”"
        };
        state.next_double_quote_is_opening = !state.next_double_quote_is_opening;
        return Some(punctuation.into());
    }
    let punctuation = match input {
        "," => "，",
        "." => "。",
        "\\" => "、",
        "?" => "？",
        "!" => "！",
        ":" => "：",
        "(" => "（",
        ")" => "）",
        "[" => "【",
        "]" => "】",
        "{" => "「",
        "}" => "」",
        "<" => "《",
        ">" => "》",
        "^" => "……",
        "_" => "——",
        _ => return None,
    };
    Some(punctuation.into())
}
