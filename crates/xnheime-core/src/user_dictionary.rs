use compact_str::CompactString;
use std::cmp::Ordering;
use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::fs;
use std::path::Path;

const USER_DICTIONARY_FILES: &[(&str, SourcePolicy)] = &[
    ("xnhe.txt", SourcePolicy::InlineMarker),
    ("flypy_top.txt", SourcePolicy::BeforeSystem),
    ("flypy_user.txt", SourcePolicy::AfterSystem),
];

#[derive(Clone, Copy)]
enum SourcePolicy {
    InlineMarker,
    BeforeSystem,
    AfterSystem,
}

#[derive(Clone, Copy)]
pub(crate) enum DictionaryLayer {
    BeforeSystem,
    AfterSystem,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct UserDictionaryLoadResult {
    pub loaded_entries: u32,
    pub ignored_lines: u32,
    pub loaded_files: Vec<String>,
}

#[derive(Clone, Debug)]
struct Entry {
    text: CompactString,
    weight: Option<f64>,
    source_index: usize,
}

#[derive(Clone, Debug, Default)]
pub struct UserDictionary {
    before_system: BTreeMap<CompactString, Vec<Entry>>,
    after_system: BTreeMap<CompactString, Vec<Entry>>,
    prefixes: BTreeSet<CompactString>,
    before_system_character_codes: HashMap<char, Vec<CompactString>>,
    after_system_character_codes: HashMap<char, Vec<CompactString>>,
}

impl UserDictionary {
    pub fn load_directory(path: &Path) -> std::io::Result<(Self, UserDictionaryLoadResult)> {
        let mut dictionary = Self::default();
        let mut loaded_files = Vec::new();
        let mut ignored_lines = 0;
        let mut source_index = 0;

        for &(name, kind) in USER_DICTIONARY_FILES {
            let file_path = path.join(name);
            let source = match fs::read_to_string(&file_path) {
                Ok(source) => source,
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => continue,
                Err(error) => return Err(error),
            };
            loaded_files.push(name.to_owned());
            ignored_lines += dictionary.parse_source(&source, kind, &mut source_index);
        }

        dictionary.finish();
        let loaded_entries = dictionary
            .before_system
            .values()
            .map(Vec::len)
            .sum::<usize>()
            + dictionary
                .after_system
                .values()
                .map(Vec::len)
                .sum::<usize>();
        Ok((
            dictionary,
            UserDictionaryLoadResult {
                loaded_entries: loaded_entries as u32,
                ignored_lines,
                loaded_files,
            },
        ))
    }

    pub(crate) fn candidates(
        &self,
        code: &str,
        layer: DictionaryLayer,
    ) -> impl Iterator<Item = &str> {
        self.entries(layer)
            .get(code)
            .into_iter()
            .flatten()
            .map(|entry| entry.text.as_str())
    }

    pub(crate) fn pattern_candidates(
        &self,
        pattern: &str,
        layer: DictionaryLayer,
    ) -> Vec<(&str, &str)> {
        self.entries(layer)
            .iter()
            .filter(|(code, _)| {
                code.len() == pattern.len() && super::code_matches_pattern_prefix(code, pattern)
            })
            .flat_map(|(code, entries)| {
                entries
                    .iter()
                    .map(move |entry| (code.as_str(), entry.text.as_str()))
            })
            .collect()
    }

    pub(crate) fn has_prefix(&self, code: &str) -> bool {
        self.prefixes.contains(code)
    }

    pub(crate) fn codes_for_character(
        &self,
        character: char,
        layer: DictionaryLayer,
    ) -> &[CompactString] {
        let codes = match layer {
            DictionaryLayer::BeforeSystem => &self.before_system_character_codes,
            DictionaryLayer::AfterSystem => &self.after_system_character_codes,
        };
        codes.get(&character).map(Vec::as_slice).unwrap_or_default()
    }

    fn entries(&self, layer: DictionaryLayer) -> &BTreeMap<CompactString, Vec<Entry>> {
        match layer {
            DictionaryLayer::BeforeSystem => &self.before_system,
            DictionaryLayer::AfterSystem => &self.after_system,
        }
    }

    fn parse_source(
        &mut self,
        source: &str,
        policy: SourcePolicy,
        source_index: &mut usize,
    ) -> u32 {
        let mut ignored = 0;
        for raw_line in source.lines() {
            let line = raw_line.trim_end().trim_start_matches('\u{feff}');
            if line.is_empty() || line.starts_with('#') || line == "---" || line == "..." {
                continue;
            }
            let (content, inline_top) = split_top_marker(line);
            let mut fields = content.split('\t');
            let (Some(text), Some(code)) = (fields.next(), fields.next()) else {
                ignored += 1;
                continue;
            };
            let code = code.trim();
            if text.is_empty() || code.len() > 4 || !super::is_flypy_code(code) {
                ignored += 1;
                continue;
            }
            let layer = match policy {
                SourcePolicy::InlineMarker if inline_top => DictionaryLayer::BeforeSystem,
                SourcePolicy::InlineMarker => DictionaryLayer::AfterSystem,
                SourcePolicy::BeforeSystem => DictionaryLayer::BeforeSystem,
                SourcePolicy::AfterSystem => DictionaryLayer::AfterSystem,
            };
            let entries = match layer {
                DictionaryLayer::BeforeSystem => self.before_system.entry(code.into()).or_default(),
                DictionaryLayer::AfterSystem => self.after_system.entry(code.into()).or_default(),
            };
            if entries.iter().any(|entry| entry.text == text) {
                continue;
            }
            entries.push(Entry {
                text: text.into(),
                weight: fields.next().and_then(parse_weight),
                source_index: *source_index,
            });
            *source_index += 1;
        }
        ignored
    }

    fn finish(&mut self) {
        for entries in self
            .before_system
            .values_mut()
            .chain(self.after_system.values_mut())
        {
            entries.sort_by(|left, right| compare_entries(left, right));
        }
        for code in self.before_system.keys().chain(self.after_system.keys()) {
            for index in 1..=code.len() {
                self.prefixes.insert(code[..index].into());
            }
        }
        self.before_system_character_codes = character_codes(&self.before_system);
        self.after_system_character_codes = character_codes(&self.after_system);
    }
}

fn split_top_marker(line: &str) -> (&str, bool) {
    let Some((content, comment)) = line.rsplit_once('#') else {
        return (line, false);
    };
    if comment.trim().eq_ignore_ascii_case("top") {
        (content.trim_end(), true)
    } else {
        (line, false)
    }
}

fn parse_weight(value: &str) -> Option<f64> {
    value.trim().trim_end_matches('%').parse().ok()
}

fn compare_entries(left: &Entry, right: &Entry) -> Ordering {
    match (left.weight, right.weight) {
        (Some(left), Some(right)) => right.total_cmp(&left),
        (Some(_), None) => Ordering::Less,
        (None, Some(_)) => Ordering::Greater,
        (None, None) => Ordering::Equal,
    }
    .then_with(|| left.source_index.cmp(&right.source_index))
}

fn character_codes(
    entries: &BTreeMap<CompactString, Vec<Entry>>,
) -> HashMap<char, Vec<CompactString>> {
    let mut result = HashMap::<char, Vec<CompactString>>::new();
    for (code, entries) in entries {
        for entry in entries {
            let mut characters = entry.text.chars();
            if let (Some(character), None) = (characters.next(), characters.next()) {
                let codes = result.entry(character).or_default();
                if !codes.contains(code) {
                    codes.push(code.clone());
                }
            }
        }
    }
    result
}

#[cfg(test)]
mod tests {
    use super::{DictionaryLayer, SourcePolicy, UserDictionary};

    #[test]
    fn parses_inline_top_markers_weights_and_rime_headers() {
        let mut dictionary = UserDictionary::default();
        let mut source_index = 0;
        let ignored = dictionary.parse_source(
            "# Rime dictionary\n---\n置顶\tzzzz # top\n较轻\tzzzz\t1\n较重\tzzzz\t9\n坏行\n",
            SourcePolicy::InlineMarker,
            &mut source_index,
        );
        dictionary.finish();

        assert_eq!(ignored, 1);
        assert_eq!(
            dictionary
                .candidates("zzzz", DictionaryLayer::BeforeSystem)
                .collect::<Vec<_>>(),
            ["置顶"]
        );
        assert_eq!(
            dictionary
                .candidates("zzzz", DictionaryLayer::AfterSystem)
                .collect::<Vec<_>>(),
            ["较重", "较轻"]
        );
        assert!(dictionary.has_prefix("zzz"));
    }
}
