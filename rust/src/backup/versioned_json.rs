use crate::{AppState, PouchError, PouchResult};

pub fn from_versioned_json(contents: &str) -> PouchResult<AppState> {
    let contents = contents.strip_prefix('\u{feff}').unwrap_or(contents);
    if contents.len() > 5_000_000 {
        return Err(PouchError::BackupTooLarge);
    }
    let source: serde_json::Value =
        serde_json::from_str(contents).map_err(|_| PouchError::InvalidBackup)?;
    let version = source.get("version").and_then(|value| value.as_u64());
    let value = source
        .get("state")
        .ok_or(PouchError::InvalidBackup)?
        .clone();
    if version == Some(8) {
        return crate::storage::previous_schema::upgrade_json(value);
    }
    if version != Some(9) {
        return Err(PouchError::UnsupportedBackupVersion);
    }
    let state: AppState = serde_json::from_value(value).map_err(|_| PouchError::InvalidBackup)?;
    state.validate().map_err(|_| PouchError::InvalidBackup)?;
    Ok(state)
}
