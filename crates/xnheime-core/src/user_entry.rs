use std::fs::{self, OpenOptions};
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};

const USER_DICTIONARY_TEMPLATE: &str = "# Xnheime user dictionary (UTF-8)\n\
# 词条<Tab>编码\n\
# 在行尾添加 # top 可将该词条排在系统词库之前：\n\
# 竹子\tvuzi # top\n\
# 周目\tvzmu\n\n";

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum UserEntryPlacement {
    BeforeSystem,
    AfterSystem,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct UserEntry {
    text: String,
    code: String,
    placement: UserEntryPlacement,
    weight: Option<String>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum UserEntryValidationError {
    InvalidCode,
    InvalidText,
    InvalidWeight,
}

pub fn validate_user_entry(
    code: &str,
    text: &str,
    placement: UserEntryPlacement,
    weight: &str,
) -> Result<UserEntry, UserEntryValidationError> {
    let code = code.trim();
    if code.is_empty()
        || code.len() > 4
        || !code
            .bytes()
            .all(|byte| byte.is_ascii_lowercase() || matches!(byte, b';' | b'\''))
    {
        return Err(UserEntryValidationError::InvalidCode);
    }

    let text = text.trim();
    if text.is_empty() || text.contains(['\t', '\n', '\r']) {
        return Err(UserEntryValidationError::InvalidText);
    }

    let weight = weight.trim();
    if placement == UserEntryPlacement::AfterSystem
        && !weight.is_empty()
        && weight.trim_end_matches('%').parse::<f64>().is_err()
    {
        return Err(UserEntryValidationError::InvalidWeight);
    }

    Ok(UserEntry {
        text: text.to_owned(),
        code: code.to_owned(),
        placement,
        weight: (placement == UserEntryPlacement::AfterSystem && !weight.is_empty())
            .then(|| weight.to_owned()),
    })
}

pub fn append_user_entry(directory: &Path, entry: &UserEntry) -> std::io::Result<PathBuf> {
    fs::create_dir_all(directory)?;
    let path = directory.join("xnhe.txt");
    let mut file = OpenOptions::new()
        .create(true)
        .read(true)
        .append(true)
        .open(&path)?;

    let length = file.metadata()?.len();
    let needs_newline = if length == 0 {
        false
    } else {
        file.seek(SeekFrom::End(-1))?;
        let mut last_byte = [0];
        file.read_exact(&mut last_byte)?;
        last_byte[0] != b'\n'
    };

    let mut addition = String::new();
    if length == 0 {
        addition.push_str(USER_DICTIONARY_TEMPLATE);
    } else if needs_newline {
        addition.push('\n');
    }
    addition.push_str(&entry.text);
    addition.push('\t');
    addition.push_str(&entry.code);
    if let Some(weight) = &entry.weight {
        addition.push('\t');
        addition.push_str(weight);
    }
    if entry.placement == UserEntryPlacement::BeforeSystem {
        addition.push_str(" # top");
    }
    addition.push('\n');
    file.write_all(addition.as_bytes())?;
    file.sync_data()?;
    Ok(path)
}

#[cfg(test)]
mod tests {
    use super::{
        append_user_entry, validate_user_entry, UserEntryPlacement, UserEntryValidationError,
    };
    use std::fs;

    #[test]
    fn validates_and_formats_user_entries() {
        assert_eq!(
            validate_user_entry("ABCDE", "词", UserEntryPlacement::AfterSystem, ""),
            Err(UserEntryValidationError::InvalidCode)
        );
        assert_eq!(
            validate_user_entry("abcd", "词\t条", UserEntryPlacement::AfterSystem, ""),
            Err(UserEntryValidationError::InvalidText)
        );
        assert_eq!(
            validate_user_entry("abcd", "词", UserEntryPlacement::AfterSystem, "heavy"),
            Err(UserEntryValidationError::InvalidWeight)
        );

        let directory = std::env::temp_dir().join(format!(
            "xnheime-user-entry-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let _ = fs::remove_dir_all(&directory);
        let top =
            validate_user_entry(" vuzi ", " 竹子 ", UserEntryPlacement::BeforeSystem, "9").unwrap();
        append_user_entry(&directory, &top).unwrap();
        let weighted =
            validate_user_entry("vzmu", "周目", UserEntryPlacement::AfterSystem, "100%").unwrap();
        let path = append_user_entry(&directory, &weighted).unwrap();
        let source = fs::read_to_string(path).unwrap();
        assert!(source.ends_with("竹子\tvuzi # top\n周目\tvzmu\t100%\n"));
        fs::remove_dir_all(directory).unwrap();
    }
}
