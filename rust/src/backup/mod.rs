mod versioned_json;

use crate::{AppState, PouchError, PouchResult};

pub fn export_json(state: &AppState) -> PouchResult<String> {
    state.validate()?;
    let text = serde_json::to_string_pretty(&serde_json::json!({"version":9,"state":state}))
        .map_err(|_| PouchError::InvalidBackup)?;
    if text.len() > 5_000_000 {
        return Err(PouchError::BackupTooLarge);
    }
    Ok(text)
}

pub fn import_json(contents: &str) -> PouchResult<AppState> {
    versioned_json::from_versioned_json(contents)
}
