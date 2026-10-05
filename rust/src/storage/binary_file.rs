use std::{
    fs,
    io::Write,
    path::{Path, PathBuf},
};

use atomicwrites::{AllowOverwrite, AtomicFile};
use serde::{Deserialize, Serialize};

use crate::{AppState, PouchError, PouchResult};
use crate::{
    Date,
    models::{
        BudgetPlan, Calendar, Country, Currency, DailyRecord, IncomeEntry, Language, PlannedItem,
        Preferences, WeekStart,
    },
};

const MAGIC: &[u8; 8] = b"POUCHDAT";
const FILE_FORMAT_VERSION: u16 = 1;
const HEADER_LENGTH: usize = 18;
const MAX_FILE_LENGTH: usize = 5_000_000;

#[derive(Deserialize, Serialize)]
struct StorageEnvelope {
    schema_version: u16,
    state: AppState,
}

#[derive(Deserialize, Serialize)]
struct StorageEnvelopeV1 {
    schema_version: u16,
    state: AppStateV1,
}

#[derive(Deserialize, Serialize)]
struct AppStateV1 {
    schema_version: u16,
    start_date: Date,
    preferences: PreferencesV1,
    income: Vec<IncomeEntry>,
    plans: Vec<BudgetPlan>,
    days: std::collections::BTreeMap<Date, DailyRecord>,
    planned: Vec<PlannedItem>,
}

#[derive(Deserialize, Serialize)]
struct PreferencesV1 {
    currency: Currency,
    language: Language,
    calendar: Calendar,
    week_start: WeekStart,
}

#[derive(Deserialize, Serialize)]
struct StorageEnvelopeV2 {
    schema_version: u16,
    state: AppStateV2,
}

#[derive(Deserialize, Serialize)]
struct AppStateV2 {
    schema_version: u16,
    start_date: Date,
    preferences: Preferences,
    income: Vec<IncomeEntry>,
    expected_income: Vec<crate::models::ExpectedIncomeEntry>,
    plans: Vec<BudgetPlan>,
    days: std::collections::BTreeMap<Date, DailyRecord>,
    planned: Vec<PlannedItem>,
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

    let (stored_schema_version, _) =
        postcard::take_from_bytes::<u16>(payload).map_err(|_| PouchError::CorruptStorage)?;
    let state = match stored_schema_version {
        1 => migrate_v1(
            postcard::from_bytes::<StorageEnvelopeV1>(payload)
                .map_err(|_| PouchError::CorruptStorage)?,
        )?,
        2 => migrate_v2(
            postcard::from_bytes::<StorageEnvelopeV2>(payload)
                .map_err(|_| PouchError::CorruptStorage)?,
        )?,
        version if version == AppState::CURRENT_SCHEMA_VERSION => {
            let envelope: StorageEnvelope =
                postcard::from_bytes(payload).map_err(|_| PouchError::CorruptStorage)?;
            if envelope.schema_version != version {
                return Err(PouchError::CorruptStorage);
            }
            envelope.state
        }
        version if version > AppState::CURRENT_SCHEMA_VERSION => {
            return Err(PouchError::UnsupportedStorageVersion);
        }
        _ => return Err(PouchError::UnsupportedStorageVersion),
    };
    state.validate().map_err(|_| PouchError::CorruptStorage)?;
    Ok(state)
}

fn migrate_v1(envelope: StorageEnvelopeV1) -> PouchResult<AppState> {
    if envelope.schema_version != 1 || envelope.state.schema_version != 1 {
        return Err(PouchError::CorruptStorage);
    }
    let old = envelope.state;
    Ok(AppState {
        schema_version: AppState::CURRENT_SCHEMA_VERSION,
        start_date: old.start_date,
        preferences: Preferences {
            country: Country::Custom,
            currency: old.preferences.currency,
            language: old.preferences.language,
            calendar: old.preferences.calendar,
            week_start: old.preferences.week_start,
        },
        income: old.income,
        expected_income: Vec::new(),
        plans: old.plans,
        days: old.days,
        planned: old.planned,
        economic_assumptions: std::collections::BTreeMap::new(),
    })
}

fn migrate_v2(envelope: StorageEnvelopeV2) -> PouchResult<AppState> {
    if envelope.schema_version != 2 || envelope.state.schema_version != 2 {
        return Err(PouchError::CorruptStorage);
    }
    let old = envelope.state;
    Ok(AppState {
        schema_version: AppState::CURRENT_SCHEMA_VERSION,
        start_date: old.start_date,
        preferences: old.preferences,
        income: old.income,
        expected_income: old.expected_income,
        plans: old.plans,
        days: old.days,
        planned: old.planned,
        economic_assumptions: std::collections::BTreeMap::new(),
    })
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

    use super::{
        AppStateV1, BinaryStore, FILE_FORMAT_VERSION, HEADER_LENGTH, MAGIC, PreferencesV1,
        StorageEnvelopeV1, decode,
    };
    use crate::{
        AppState, Date, Money, PouchError,
        models::{Calendar, Country, Currency, IncomeEntry, Language, WeekStart},
    };

    fn encode_v1_state(date: Date) -> Vec<u8> {
        let mut state = AppState::fresh(date);
        state.plans[0].calendar = Calendar::Gregorian;
        let old_state = AppStateV1 {
            schema_version: 1,
            start_date: date,
            preferences: PreferencesV1 {
                currency: Currency::Cad,
                language: Language::Persian,
                calendar: Calendar::Gregorian,
                week_start: WeekStart::Monday,
            },
            income: vec![IncomeEntry {
                id: "recorded-income".into(),
                date,
                amount: Money::from_hundredths(12500).expect("the income is valid"),
            }],
            plans: state.plans,
            days: state.days,
            planned: state.planned,
        };
        let payload = postcard::to_allocvec(&StorageEnvelopeV1 {
            schema_version: 1,
            state: old_state,
        })
        .expect("the legacy state serializes");
        let mut bytes = Vec::with_capacity(HEADER_LENGTH + payload.len());
        bytes.extend_from_slice(MAGIC);
        bytes.extend_from_slice(&FILE_FORMAT_VERSION.to_le_bytes());
        bytes.extend_from_slice(&(payload.len() as u32).to_le_bytes());
        bytes.extend_from_slice(&crc32fast::hash(&payload).to_le_bytes());
        bytes.extend_from_slice(&payload);
        bytes
    }

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
    fn version_one_state_migrates_without_changing_existing_preferences() {
        let date = Date::parse_iso("2026-09-21").expect("the date should be valid");
        let migrated = decode(&encode_v1_state(date)).expect("the old state migrates");

        assert_eq!(migrated.schema_version, AppState::CURRENT_SCHEMA_VERSION);
        assert_eq!(migrated.preferences.country, Country::Custom);
        assert_eq!(migrated.preferences.currency, Currency::Cad);
        assert_eq!(migrated.preferences.language, Language::Persian);
        assert_eq!(migrated.preferences.calendar, Calendar::Gregorian);
        assert_eq!(migrated.preferences.week_start, WeekStart::Monday);
        assert!(migrated.expected_income.is_empty());
        assert_eq!(migrated.income.len(), 1);
        assert_eq!(migrated.income[0].id, "recorded-income");
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
    #[test]
    fn version_two_migration_preserves_every_existing_field() {
        let mut expected = AppState::fresh(Date::parse_iso("2024-01-01").expect("date"));
        expected.preferences.country = Country::Iran;
        expected.preferences.currency = Currency::Toman;
        expected.income.push(IncomeEntry {
            id: "received".into(),
            date: expected.start_date,
            amount: Money::from_hundredths(12000).expect("amount"),
        });
        expected
            .expected_income
            .push(crate::models::ExpectedIncomeEntry {
                id: "expected".into(),
                date: expected.start_date.add_days(50).expect("date"),
                amount: Money::from_hundredths(15000).expect("amount"),
            });
        expected
            .days
            .insert(expected.start_date, crate::models::DailyRecord::default());
        let old = super::AppStateV2 {
            schema_version: 2,
            start_date: expected.start_date,
            preferences: expected.preferences.clone(),
            income: expected.income.clone(),
            expected_income: expected.expected_income.clone(),
            plans: expected.plans.clone(),
            days: expected.days.clone(),
            planned: expected.planned.clone(),
        };
        let payload = postcard::to_allocvec(&super::StorageEnvelopeV2 {
            schema_version: 2,
            state: old,
        })
        .expect("legacy payload");
        let mut bytes = Vec::new();
        bytes.extend_from_slice(MAGIC);
        bytes.extend_from_slice(&FILE_FORMAT_VERSION.to_le_bytes());
        bytes.extend_from_slice(&(payload.len() as u32).to_le_bytes());
        bytes.extend_from_slice(&crc32fast::hash(&payload).to_le_bytes());
        bytes.extend_from_slice(&payload);
        assert_eq!(decode(&bytes).expect("migrated"), expected);
    }
}
