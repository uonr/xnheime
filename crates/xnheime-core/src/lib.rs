use std::collections::{HashMap, HashSet};
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::ptr;
use std::sync::OnceLock;

const FLYPY_DICTIONARIES: &[&str] = &[
    include_str!("../../../data/flypy/flypy/flypy.user.top.dict.yaml"),
    include_str!("../../../data/flypy/flypy/flypy.fast.symbols.dict.yaml"),
    include_str!("../../../data/flypy/flypy/flypy.primary.dict.yaml"),
    include_str!("../../../data/flypy/flypy/flypy.secondary.dict.yaml"),
    include_str!("../../../data/flypy/flypy/flypy.three.dict.yaml"),
    include_str!("../../../data/flypy/flypy/flypy.web.dict.yaml"),
    include_str!("../../../data/flypy/flypy/flypy.emoji.dict.yaml"),
    include_str!("../../../data/flypy/flypy/flypy.symbols.dict.yaml"),
    include_str!("../../../data/flypy/flypy/flypy.wechat.dict.yaml"),
    include_str!("../../../data/flypy/flypy/flypy.primary.short.word.dict.yaml"),
    include_str!("../../../data/flypy/flypy/flypy.whimsicality.dict.yaml"),
    include_str!("../../../data/flypy/flypy/flypy.user.dict.yaml"),
];

static FLYPY_TABLE: OnceLock<CodeTable> = OnceLock::new();

struct CodeTable {
    entries: HashMap<&'static str, Vec<&'static str>>,
    prefixes: HashSet<String>,
}

impl CodeTable {
    fn load() -> Self {
        let mut entries = HashMap::new();

        for dictionary in FLYPY_DICTIONARIES {
            parse_rime_dictionary(dictionary, &mut entries);
        }

        let mut prefixes = HashSet::new();
        for code in entries.keys() {
            for index in 1..=code.len() {
                prefixes.insert(code[..index].to_owned());
            }
        }

        Self { entries, prefixes }
    }
}

pub fn lookup_first(input: &str) -> Option<&'static str> {
    if !is_flypy_code(input) {
        return None;
    }

    flypy_table()
        .entries
        .get(input)
        .and_then(|candidates| candidates.first())
        .copied()
}

pub fn has_code_prefix(input: &str) -> bool {
    is_flypy_code(input) && flypy_table().prefixes.contains(input)
}

fn flypy_table() -> &'static CodeTable {
    FLYPY_TABLE.get_or_init(CodeTable::load)
}

fn parse_rime_dictionary(
    source: &'static str,
    entries: &mut HashMap<&'static str, Vec<&'static str>>,
) {
    for line in source.lines() {
        let line = line.trim_end();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }

        let mut fields = line.split('\t');
        let Some(word) = fields.next() else { continue };
        let Some(code) = fields.next() else { continue };

        if word.is_empty() || !is_flypy_code(code) {
            continue;
        }

        entries.entry(code).or_default().push(word);
    }
}

fn is_flypy_code(input: &str) -> bool {
    !input.is_empty()
        && input
            .bytes()
            .all(|byte| matches!(byte, b'a'..=b'z' | b';' | b'\''))
}

unsafe fn with_c_input<T>(input: *const c_char, body: impl FnOnce(&str) -> T) -> Option<T> {
    if input.is_null() {
        return None;
    }

    CStr::from_ptr(input).to_str().ok().map(body)
}

fn c_string_or_null(value: Option<&str>) -> *mut c_char {
    match value {
        Some(output) => CString::new(output).unwrap().into_raw(),
        None => ptr::null_mut(),
    }
}

#[no_mangle]
pub unsafe extern "C" fn xnheime_lookup_first(input: *const c_char) -> *mut c_char {
    c_string_or_null(with_c_input(input, lookup_first).flatten())
}

#[no_mangle]
pub unsafe extern "C" fn xnheime_has_code_prefix(input: *const c_char) -> bool {
    with_c_input(input, has_code_prefix).unwrap_or(false)
}

#[no_mangle]
pub unsafe extern "C" fn xnheime_string_free(value: *mut c_char) {
    if !value.is_null() {
        let _ = CString::from_raw(value);
    }
}

#[cfg(test)]
mod tests {
    use super::{has_code_prefix, lookup_first};

    #[test]
    fn looks_up_first_candidate_from_flypy_table() {
        assert_eq!(lookup_first("ni"), Some("你"));
        assert_eq!(lookup_first("wo"), Some("我"));
        assert_eq!(lookup_first("aakk"), Some("啊"));
        assert_eq!(lookup_first("hello"), None);
    }

    #[test]
    fn checks_flypy_prefixes() {
        assert!(has_code_prefix("n"));
        assert!(has_code_prefix("ni"));
        assert!(has_code_prefix("aak"));
        assert!(!has_code_prefix("hello"));
        assert!(!has_code_prefix("N"));
    }
}
