use std::{
    fs,
    io::Write,
    path::{Path, PathBuf},
};

use atomicwrites::{AllowOverwrite, AtomicFile};
use serde::{Deserialize, Serialize};

use crate::{AppState, PouchError, PouchResult};

const MAGIC: &[u8; 8] = b"POUCHDAT";
const FILE_FORMAT_VERSION: u16 = 1;
const HEADER_LENGTH: usize = 18;
const MAX_FILE_LENGTH: usize = 5_000_000;

#[derive(Deserialize, Serialize)]
struct StorageEnvelope {
    schema_version: u16,
    state: AppState,
}

pub struct LoadedState {
    pub state: AppState,
    pub recovered: bool,
}

pub struct BinaryStore {
    primary_path: PathBuf,
    backup_path: PathBuf,
    recovery_payload: Option<Vec<u8>>,
}

impl BinaryStore {
    pub fn new(directory: impl AsRef<Path>) -> Self {
        let directory = directory.as_ref();
        Self {
            primary_path: directory.join("pouch.data"),
            backup_path: directory.join("pouch.data.backup"),
            recovery_payload: None,
        }
    }

    pub fn load(&mut self) -> PouchResult<Option<LoadedState>> {
        fs::create_dir_all(
            self.primary_path
                .parent()
                .ok_or(PouchError::StorageUnavailable)?,
        )
        .map_err(|_| PouchError::StorageUnavailable)?;

        let primary = read_optional(&self.primary_path);
        let backup = read_optional(&self.backup_path);
        let primary_failed = primary.is_err();
        let backup_failed = backup.is_err();

        if let Ok(Some(bytes)) = primary.as_ref() {
            match decode(bytes) {
                Ok(state) => {
                    self.recovery_payload = Some(bytes.clone());
                    return Ok(Some(LoadedState {
                        state,
                        recovered: false,
                    }));
                }
                Err(PouchError::UnsupportedStorageVersion) => {
                    return Err(PouchError::UnsupportedStorageVersion);
                }
                Err(_) => {}
            }
        }

        if let Ok(Some(bytes)) = backup.as_ref() {
            match decode(bytes) {
                Ok(state) => {
                    self.recovery_payload = Some(bytes.clone());
                    return Ok(Some(LoadedState {
                        state,
                        recovered: true,
                    }));
                }
                Err(PouchError::UnsupportedStorageVersion) => {
                    return Err(PouchError::UnsupportedStorageVersion);
                }
                Err(_) => {}
            }
        }

        if primary_failed || backup_failed {
            return Err(PouchError::StorageUnavailable);
        }
        if self.primary_path.exists() || self.backup_path.exists() {
            return Err(PouchError::CorruptStorage);
        }
        Ok(None)
    }

    pub fn save(&mut self, state: &AppState) -> PouchResult<()> {
        state.validate()?;
        let bytes = encode(state)?;
        if bytes.len() > MAX_FILE_LENGTH {
            return Err(PouchError::SaveFailed);
        }
        decode(&bytes)?;

        let previous_good = match read_optional(&self.primary_path)? {
            Some(current) => match decode(&current) {
                Ok(_) => Some(current),
                Err(_) => self.recovery_payload.clone(),
            },
            None => self.recovery_payload.clone(),
        };

        if let Some(previous) = previous_good {
            atomic_write(&self.backup_path, &previous)?;
        } else if !self.backup_path.exists() {
            atomic_write(&self.backup_path, &bytes)?;
        }
        atomic_write(&self.primary_path, &bytes)?;
        self.recovery_payload = Some(bytes);
        Ok(())
    }

    pub fn load_recovery_copy(&self) -> PouchResult<Option<AppState>> {
        match read_optional(&self.backup_path)? {
            Some(bytes) => decode(&bytes).map(Some),
            None => Ok(None),
        }
    }
}

fn encode(state: &AppState) -> PouchResult<Vec<u8>> {
    let payload = postcard::to_allocvec(&StorageEnvelope {
        schema_version: AppState::CURRENT_SCHEMA_VERSION,
        state: state.clone(),
    })
    .map_err(|_| PouchError::SaveFailed)?;
    let length = u32::try_from(payload.len()).map_err(|_| PouchError::SaveFailed)?;
    let checksum = crc32fast::hash(&payload);
    let mut bytes = Vec::with_capacity(HEADER_LENGTH + payload.len());
    bytes.extend_from_slice(MAGIC);
    bytes.extend_from_slice(&FILE_FORMAT_VERSION.to_le_bytes());
    bytes.extend_from_slice(&length.to_le_bytes());
    bytes.extend_from_slice(&checksum.to_le_bytes());
    bytes.extend_from_slice(&payload);
    Ok(bytes)
}

fn decode(bytes: &[u8]) -> PouchResult<AppState> {
    if bytes.len() < HEADER_LENGTH || bytes.get(..8) != Some(MAGIC.as_slice()) {
        return Err(PouchError::CorruptStorage);
    }
    let format_version = u16::from_le_bytes(
        bytes[8..10]
            .try_into()
            .map_err(|_| PouchError::CorruptStorage)?,
    );
    if format_version > FILE_FORMAT_VERSION {
        return Err(PouchError::UnsupportedStorageVersion);
    }
    if format_version != FILE_FORMAT_VERSION {
        return Err(PouchError::CorruptStorage);
    }
    let payload_length = u32::from_le_bytes(
        bytes[10..14]
            .try_into()
            .map_err(|_| PouchError::CorruptStorage)?,
    ) as usize;
    let checksum = u32::from_le_bytes(
        bytes[14..18]
            .try_into()
            .map_err(|_| PouchError::CorruptStorage)?,
    );
    let payload = bytes
        .get(HEADER_LENGTH..)
        .filter(|payload| payload.len() == payload_length)
        .ok_or(PouchError::CorruptStorage)?;
    if crc32fast::hash(payload) != checksum {
        return Err(PouchError::CorruptStorage);
    }

    let envelope: StorageEnvelope =
        postcard::from_bytes(payload).map_err(|_| PouchError::CorruptStorage)?;
    if envelope.schema_version > AppState::CURRENT_SCHEMA_VERSION {
        return Err(PouchError::UnsupportedStorageVersion);
    }
    if envelope.schema_version != AppState::CURRENT_SCHEMA_VERSION {
        return Err(PouchError::UnsupportedStorageVersion);
    }
    envelope
        .state
        .validate()
        .map_err(|_| PouchError::CorruptStorage)?;
    Ok(envelope.state)
}

fn read_optional(path: &Path) -> PouchResult<Option<Vec<u8>>> {
    match fs::metadata(path) {
        Ok(metadata) if metadata.len() > MAX_FILE_LENGTH as u64 => {
            return Err(PouchError::CorruptStorage);
        }
        Ok(_) => {}
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(_) => return Err(PouchError::StorageUnavailable),
    }
    match fs::read(path) {
        Ok(bytes) => Ok(Some(bytes)),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(_) => Err(PouchError::StorageUnavailable),
    }
}

fn atomic_write(path: &Path, bytes: &[u8]) -> PouchResult<()> {
    let parent = path.parent().ok_or(PouchError::SaveFailed)?;
    fs::create_dir_all(parent).map_err(|_| PouchError::SaveFailed)?;
    AtomicFile::new(path, AllowOverwrite)
        .write(|file| {
            file.write_all(bytes)?;
            file.sync_all()
        })
        .map_err(|_| PouchError::SaveFailed)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use std::{fs, io::Write};

    use super::BinaryStore;
    use crate::{AppState, Date, PouchError};

    #[test]
    fn binary_file_round_trip_keeps_versioned_state() {
        let directory = tempfile::tempdir().expect("a temporary directory should be available");
        let date = Date::parse_iso("2026-09-21").expect("the date should be valid");
        let expected = AppState::fresh(date);
        let mut store = BinaryStore::new(directory.path());
        store.save(&expected).expect("state should be saved");
        let loaded = store
            .load()
            .expect("state should load")
            .expect("file should exist");
        assert_eq!(loaded.state, expected);
        assert!(!loaded.recovered);
        assert_eq!(
            store.load_recovery_copy().expect("recovery should load"),
            Some(expected)
        );
    }

    #[test]
    fn corrupt_primary_recovers_previous_valid_state() {
        let directory = tempfile::tempdir().expect("a temporary directory should be available");
        let date = Date::parse_iso("2026-09-21").expect("the date should be valid");
        let mut store = BinaryStore::new(directory.path());
        store
            .save(&AppState::fresh(date))
            .expect("first state should be saved");
        let second_date = Date::parse_iso("2026-09-22").expect("the date should be valid");
        store
            .save(&AppState::fresh(second_date))
            .expect("second state should be saved");
        fs::write(directory.path().join("pouch.data"), b"partial write")
            .expect("test corruption should be written");

        let recovered = BinaryStore::new(directory.path())
            .load()
            .expect("the recovery copy should load")
            .expect("a saved file should exist");

        assert!(recovered.recovered);
        assert_eq!(recovered.state.start_date, date);
    }

    #[test]
    fn truncated_binary_is_not_treated_as_an_empty_budget() {
        let directory = tempfile::tempdir().expect("a temporary directory should be available");
        let mut file = fs::File::create(directory.path().join("pouch.data"))
            .expect("primary file should be created");
        file.write_all(b"POUCHDAT")
            .expect("the partial header should be written");

        let result = BinaryStore::new(directory.path()).load();

        assert!(result.is_err());
    }

    #[test]
    fn unsupported_future_format_is_reported_without_falling_back() {
        let directory = tempfile::tempdir().expect("a temporary directory should be available");
        let date = Date::parse_iso("2026-09-21").expect("the date should be valid");
        let mut store = BinaryStore::new(directory.path());
        store
            .save(&AppState::fresh(date))
            .expect("state should be saved");
        let primary = directory.path().join("pouch.data");
        let mut contents = fs::read(&primary).expect("the primary file should be readable");
        contents[8..10].copy_from_slice(&2_u16.to_le_bytes());
        fs::write(primary, contents).expect("the future version should be written");

        let result = BinaryStore::new(directory.path()).load();

        assert!(matches!(result, Err(PouchError::UnsupportedStorageVersion)));
    }

    #[test]
    fn failed_recovery_copy_write_keeps_the_primary_state_intact() {
        let directory = tempfile::tempdir().expect("a temporary directory should be available");
        let first_date = Date::parse_iso("2026-09-21").expect("the date should be valid");
        let second_date = Date::parse_iso("2026-09-22").expect("the date should be valid");
        let mut store = BinaryStore::new(directory.path());
        store
            .save(&AppState::fresh(first_date))
            .expect("the original state should be saved");
        fs::remove_file(directory.path().join("pouch.data.backup"))
            .expect("the recovery file should be removed");
        fs::create_dir(directory.path().join("pouch.data.backup"))
            .expect("the recovery path should block replacement");

        assert!(store.save(&AppState::fresh(second_date)).is_err());
        let loaded = BinaryStore::new(directory.path())
            .load()
            .expect("the original primary should still load")
            .expect("the original primary should remain present");
        assert_eq!(loaded.state.start_date, first_date);
    }
}
