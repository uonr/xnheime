use std::collections::{BTreeMap, BTreeSet};
use std::env;
use std::fs;
use std::path::{Path, PathBuf};

const DICTIONARIES: &[&str] = &[
    "flypy.user.top.dict.yaml",
    "flypy.fast.symbols.dict.yaml",
    "flypy.primary.dict.yaml",
    "flypy.secondary.dict.yaml",
    "flypy.three.dict.yaml",
    "flypy.web.dict.yaml",
    "flypy.emoji.dict.yaml",
    "flypy.symbols.dict.yaml",
    "flypy.wechat.dict.yaml",
    "flypy.primary.short.word.dict.yaml",
    "flypy.whimsicality.dict.yaml",
    "flypy.user.dict.yaml",
];

#[derive(Debug)]
struct DictionaryCandidate {
    word: String,
    dictionary_index: usize,
    source_index: usize,
    weight: Option<f64>,
}

fn main() {
    let manifest = PathBuf::from(env::var_os("CARGO_MANIFEST_DIR").unwrap());
    let dictionary_dir = manifest.join("../../data/flypy/flypy");
    let mut entries = BTreeMap::<String, Vec<DictionaryCandidate>>::new();

    for (dictionary_index, name) in DICTIONARIES.iter().enumerate() {
        let path = dictionary_dir.join(name);
        println!("cargo:rerun-if-changed={}", path.display());
        parse_dictionary(&path, dictionary_index, &mut entries);
    }

    let mut prefixes = BTreeSet::new();
    for code in entries.keys() {
        for index in 1..=code.len() {
            prefixes.insert(code[..index].to_owned());
        }
    }

    let mut generated = String::from("static ENTRIES: &[(&str, &str)] = &[\n");
    let mut character_codes = BTreeMap::<char, Vec<String>>::new();
    for (code, mut candidates) in entries {
        candidates.sort_by(|left, right| {
            left.dictionary_index
                .cmp(&right.dictionary_index)
                .then_with(|| match (left.weight, right.weight) {
                    (Some(left), Some(right)) => right.total_cmp(&left),
                    (Some(_), None) => std::cmp::Ordering::Less,
                    (None, Some(_)) => std::cmp::Ordering::Greater,
                    (None, None) => std::cmp::Ordering::Equal,
                })
                .then_with(|| left.source_index.cmp(&right.source_index))
        });
        for candidate in candidates {
            let mut characters = candidate.word.chars();
            if let (Some(character), None) = (characters.next(), characters.next()) {
                let codes = character_codes.entry(character).or_default();
                if !codes.contains(&code) {
                    codes.push(code.clone());
                }
            }
            generated.push_str(&format!("    ({code:?}, {:?}),\n", candidate.word));
        }
    }
    generated.push_str("];\nstatic PREFIXES: &[&str] = &[\n");
    for prefix in prefixes {
        generated.push_str(&format!("    {prefix:?},\n"));
    }
    generated.push_str("];\nstatic CHARACTER_CODES: &[(char, &[&str])] = &[\n");
    for (character, codes) in character_codes {
        generated.push_str(&format!("    ({character:?}, &["));
        for code in codes {
            generated.push_str(&format!("{code:?}, "));
        }
        generated.push_str("]),\n");
    }
    generated.push_str("];\n");

    let output = PathBuf::from(env::var_os("OUT_DIR").unwrap()).join("flypy_index.rs");
    fs::write(output, generated).unwrap();
}

fn parse_dictionary(
    path: &Path,
    dictionary_index: usize,
    entries: &mut BTreeMap<String, Vec<DictionaryCandidate>>,
) {
    let source = fs::read_to_string(path).unwrap_or_else(|error| {
        panic!("failed to read {}: {error}", path.display());
    });

    for (source_index, line) in source.lines().enumerate() {
        let mut fields = line.trim_end().split('\t');
        let (Some(word), Some(code)) = (fields.next(), fields.next()) else {
            continue;
        };
        if !word.is_empty() && is_flypy_code(code) {
            let candidates = entries.entry(code.to_owned()).or_default();
            if !candidates.iter().any(|candidate| candidate.word == word) {
                candidates.push(DictionaryCandidate {
                    word: word.to_owned(),
                    dictionary_index,
                    source_index,
                    weight: fields.next().and_then(parse_weight),
                });
            }
        }
    }
}

fn parse_weight(value: &str) -> Option<f64> {
    value.trim().trim_end_matches('%').parse().ok()
}

fn is_flypy_code(input: &str) -> bool {
    !input.is_empty()
        && input
            .bytes()
            .all(|byte| matches!(byte, b'a'..=b'z' | b';' | b'\''))
}
