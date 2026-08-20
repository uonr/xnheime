use std::collections::BTreeMap;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};

use rsmarisa::{Agent, Trie};

const RIME_TABLE_FORMAT: &[u8] = b"Rime::Table/4.0\0";

const MODE_EXPERT: u8 = 0;
const MODE_REGULAR: u8 = 1;
const MODE_BEGINNER: u8 = 2;

const RANK_BEFORE_SYSTEM: usize = 0;
const RANK_MAIN_TABLE: usize = 1;
const RANK_AFTER_SYSTEM: usize = 2;
const RANK_REGULAR_AFTER_SYSTEM: usize = 3;
const RANK_BEGINNER_AFTER_SYSTEM: usize = 4;

#[derive(Debug)]
struct DictionaryCandidate {
    word: String,
    dictionary_index: usize,
    source_index: usize,
    weight: Option<f64>,
    minimum_mode: u8,
}

fn main() {
    let manifest = PathBuf::from(env::var_os("CARGO_MANIFEST_DIR").unwrap());
    let dictionary_dir = manifest.join("../../data/flypy");
    let mut entries = BTreeMap::<String, Vec<DictionaryCandidate>>::new();

    parse_tracked_text_dictionary(
        &dictionary_dir.join("flypy_top.txt"),
        RANK_BEFORE_SYSTEM,
        MODE_EXPERT,
        &mut entries,
    );
    let main_table_path = dictionary_dir.join("flypy.table.bin");
    println!("cargo:rerun-if-changed={}", main_table_path.display());
    parse_rime_table(&main_table_path, RANK_MAIN_TABLE, &mut entries);
    parse_tracked_text_dictionary(
        &dictionary_dir.join("flypy_sys.txt"),
        RANK_AFTER_SYSTEM,
        MODE_EXPERT,
        &mut entries,
    );

    let mode_path = dictionary_dir.join("模式切换&补充简码方案.txt");
    println!("cargo:rerun-if-changed={}", mode_path.display());
    parse_mode_dictionary(&mode_path, &mut entries);
    let full_character_path = dictionary_dir.join("flypy_full全码字.txt");
    println!("cargo:rerun-if-changed={}", full_character_path.display());
    parse_text_dictionary(
        &full_character_path,
        RANK_BEGINNER_AFTER_SYSTEM,
        MODE_BEGINNER,
        &mut entries,
    );

    // OK mode is an independent component-decomposition lookup entered with
    // `ok...`; it is available in every dictionary mode and must not leak into
    // normal reverse lookup results.
    let mut ok_entries = BTreeMap::<String, Vec<DictionaryCandidate>>::new();
    parse_tracked_text_dictionary(
        &dictionary_dir.join("flypy_ok.txt"),
        RANK_MAIN_TABLE,
        MODE_EXPERT,
        &mut ok_entries,
    );

    let mut prefixes = BTreeMap::<String, u8>::new();
    for (code, candidates) in &entries {
        let minimum_mode = candidates
            .iter()
            .map(|candidate| candidate.minimum_mode)
            .min()
            .expect("dictionary code has no candidates");
        for index in 1..=code.len() {
            prefixes
                .entry(code[..index].to_owned())
                .and_modify(|existing| *existing = (*existing).min(minimum_mode))
                .or_insert(minimum_mode);
        }
    }

    let mut generated = String::from("static ENTRIES: &[(&str, &str, u8)] = &[\n");
    let mut character_codes = BTreeMap::<char, Vec<(String, u8)>>::new();
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
                if !codes.iter().any(|(existing, _)| existing == &code) {
                    codes.push((code.clone(), candidate.minimum_mode));
                }
            }
            generated.push_str(&format!(
                "    ({code:?}, {:?}, {}),\n",
                candidate.word, candidate.minimum_mode
            ));
        }
    }
    generated.push_str("];\nstatic PREFIXES: &[(&str, u8)] = &[\n");
    for (prefix, minimum_mode) in prefixes {
        generated.push_str(&format!("    ({prefix:?}, {minimum_mode}),\n"));
    }
    generated.push_str("];\nstatic CHARACTER_CODES: &[(char, &[(&str, u8)])] = &[\n");
    for (character, codes) in character_codes {
        generated.push_str(&format!("    ({character:?}, &["));
        for (code, minimum_mode) in codes {
            generated.push_str(&format!("({code:?}, {minimum_mode}), "));
        }
        generated.push_str("]),\n");
    }
    generated.push_str("];\nstatic OK_ENTRIES: &[(&str, &str)] = &[\n");
    for (code, candidates) in ok_entries {
        for candidate in candidates {
            generated.push_str(&format!("    ({code:?}, {:?}),\n", candidate.word));
        }
    }
    generated.push_str("];\n");

    let output = PathBuf::from(env::var_os("OUT_DIR").unwrap()).join("flypy_index.rs");
    fs::write(output, generated).unwrap();
}

fn parse_tracked_text_dictionary(
    path: &Path,
    dictionary_index: usize,
    minimum_mode: u8,
    entries: &mut BTreeMap<String, Vec<DictionaryCandidate>>,
) {
    println!("cargo:rerun-if-changed={}", path.display());
    parse_text_dictionary(path, dictionary_index, minimum_mode, entries);
}

fn parse_text_dictionary(
    path: &Path,
    dictionary_index: usize,
    minimum_mode: u8,
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
                    minimum_mode,
                });
            }
        }
    }
}

fn parse_mode_dictionary(path: &Path, entries: &mut BTreeMap<String, Vec<DictionaryCandidate>>) {
    let source = fs::read_to_string(path).unwrap_or_else(|error| {
        panic!("failed to read {}: {error}", path.display());
    });
    let mut dictionary_index = None;
    let mut found_before_system = false;
    let mut found_after_system = false;
    for (source_index, line) in source.lines().enumerate() {
        if line.starts_with("# 1.全码词 置顶 本类词条") {
            found_before_system = true;
            dictionary_index = Some(RANK_BEFORE_SYSTEM);
            continue;
        }
        if line.starts_with("# 2.全码词 居后 本类词条") {
            found_after_system = true;
            dictionary_index = Some(RANK_REGULAR_AFTER_SYSTEM);
            continue;
        }
        let Some(dictionary_index) = dictionary_index else {
            continue;
        };
        let mut fields = line.trim_end().split('\t');
        let (Some(word), Some(code)) = (fields.next(), fields.next()) else {
            continue;
        };
        if !word.is_empty() && is_flypy_code(code) {
            push_candidate(
                entries,
                code,
                word,
                dictionary_index,
                source_index,
                fields.next().and_then(parse_weight),
                MODE_REGULAR,
            );
        }
    }
    assert!(
        found_before_system && found_after_system,
        "unrecognized mode sections in {}; update parse_mode_dictionary for the new format",
        path.display()
    );
}

fn push_candidate(
    entries: &mut BTreeMap<String, Vec<DictionaryCandidate>>,
    code: &str,
    word: &str,
    dictionary_index: usize,
    source_index: usize,
    weight: Option<f64>,
    minimum_mode: u8,
) {
    let candidates = entries.entry(code.to_owned()).or_default();
    if !candidates.iter().any(|candidate| candidate.word == word) {
        candidates.push(DictionaryCandidate {
            word: word.to_owned(),
            dictionary_index,
            source_index,
            weight,
            minimum_mode,
        });
    }
}

fn parse_rime_table(
    path: &Path,
    dictionary_index: usize,
    entries: &mut BTreeMap<String, Vec<DictionaryCandidate>>,
) {
    let data = fs::read(path).unwrap_or_else(|error| {
        panic!("failed to read {}: {error}", path.display());
    });
    assert!(
        data.starts_with(RIME_TABLE_FORMAT),
        "unsupported Rime table format in {}",
        path.display()
    );

    let declared_entries = read_u32(&data, 40) as usize;
    let syllabary = read_pointer(&data, 44);
    let index = read_pointer(&data, 48);
    let string_table = read_pointer(&data, 60);
    let string_table_size = read_u32(&data, 64) as usize;
    let string_table_end = string_table
        .checked_add(string_table_size)
        .filter(|end| *end <= data.len())
        .expect("Rime string table extends past the end of the file");

    // rsmarisa reads a standalone trie, while Rime embeds it in table.bin.
    let trie_path = PathBuf::from(env::var_os("OUT_DIR").unwrap()).join("flypy.marisa");
    fs::write(&trie_path, &data[string_table..string_table_end]).unwrap();
    let mut trie = Trie::new();
    trie.load(trie_path.to_str().unwrap())
        .unwrap_or_else(|error| {
            panic!(
                "failed to read the Marisa trie in {}: {error}",
                path.display()
            )
        });

    let syllable_count = read_u32(&data, syllabary) as usize;
    assert_eq!(
        syllable_count,
        read_u32(&data, index) as usize,
        "Rime syllabary and head index sizes differ"
    );
    let mut agent = Agent::new();
    let mut source_index = 0;
    for position in 0..syllable_count {
        let code_id = read_i32(&data, syllabary + 4 + 4 * position);
        let code = restore_string(&trie, &mut agent, code_id);
        assert!(is_flypy_code(&code), "invalid Flypy code {code:?}");

        // A HeadIndexNode is List<Entry> (size + relative pointer), followed
        // by the next-level pointer. Flypy codes are individual syllables, so
        // all candidates live in this head index.
        let node = index + 4 + 12 * position;
        let entry_count = read_u32(&data, node) as usize;
        if entry_count == 0 {
            continue;
        }
        let entry_array = read_pointer(&data, node + 4);
        for entry_position in 0..entry_count {
            let entry = entry_array + 8 * entry_position;
            let text = restore_string(&trie, &mut agent, read_i32(&data, entry));
            let weight = f32::from_le_bytes(read_bytes::<4>(&data, entry + 4)) as f64;
            entries
                .entry(code.clone())
                .or_default()
                .push(DictionaryCandidate {
                    word: text,
                    dictionary_index,
                    source_index,
                    weight: Some(weight),
                    minimum_mode: MODE_EXPERT,
                });
            source_index += 1;
        }
    }
    assert_eq!(
        source_index, declared_entries,
        "Rime entry count differs from metadata"
    );
}

fn restore_string(trie: &Trie, agent: &mut Agent, id: i32) -> String {
    let id = usize::try_from(id).expect("negative Marisa string id");
    agent.set_query_id(id);
    trie.reverse_lookup(agent);
    String::from_utf8(agent.key().as_bytes().to_vec()).expect("non-UTF-8 Rime string")
}

fn read_pointer(data: &[u8], offset: usize) -> usize {
    let relative = read_i32(data, offset);
    assert_ne!(relative, 0, "unexpected null pointer at byte {offset}");
    offset
        .checked_add_signed(relative as isize)
        .filter(|target| *target < data.len())
        .expect("Rime pointer extends past the end of the file")
}

fn read_i32(data: &[u8], offset: usize) -> i32 {
    i32::from_le_bytes(read_bytes(data, offset))
}

fn read_u32(data: &[u8], offset: usize) -> u32 {
    u32::from_le_bytes(read_bytes(data, offset))
}

fn read_bytes<const N: usize>(data: &[u8], offset: usize) -> [u8; N] {
    data.get(offset..offset + N)
        .expect("Rime table ended unexpectedly")
        .try_into()
        .unwrap()
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
