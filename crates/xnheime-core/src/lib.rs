mod builtin_dictionary;
mod composition;
mod user_dictionary;
mod user_entry;

pub use builtin_dictionary::DictionaryMode;
pub use composition::{
    CandidateAction, CandidateItem, CompositionEffect, CompositionEvent, CompositionMode,
    CompositionSession,
};
pub use user_dictionary::{UserDictionary, UserDictionaryLoadResult};
pub use user_entry::{
    append_user_entry, validate_user_entry, UserEntry, UserEntryPlacement, UserEntryValidationError,
};

pub(crate) use builtin_dictionary::{
    code_matches_pattern_prefix, has_code_prefix, is_flypy_code, lookup_candidates,
    lookup_candidates_matching, lookup_codes_for_character,
};
pub(crate) use user_dictionary::DictionaryLayer;
