use std::path::Path;

use chrono::Local;

use crate::{
    AppState, Date, PouchError, PouchResult, backup, models::Preferences, storage::BinaryStore,
};

pub struct CoreModules {
    state: AppState,
    storage: BinaryStore,
    revision: u64,
    recovered: bool,
    imported_json: bool,
    undo_state: Option<AppState>,
}

impl CoreModules {
    pub fn open(
        directory: impl AsRef<Path>,
        legacy_json_candidates: &[String],
    ) -> PouchResult<Self> {
        let mut storage = BinaryStore::new(directory);
        let loaded = storage.load()?;
        let (state, recovered, imported_json) = match loaded {
            Some(loaded) => (loaded.state, loaded.recovered, false),
            None => {
                let mut imported = None;
                let mut last_import_error = None;
                for contents in legacy_json_candidates {
                    match backup::import_json(contents) {
                        Ok(state) => {
                            imported = Some(state);
                            break;
                        }
                        Err(error) => last_import_error = Some(error),
                    }
                }
                if let Some(imported) = imported {
                    imported.validate()?;
                    storage.save(&imported)?;
                    (imported, false, true)
                } else if let Some(error) = last_import_error {
                    return Err(error);
                } else {
                    let today = Local::now().date_naive();
                    let start_date = Date::from_naive_date(today)?;
                    let initial = AppState::fresh(start_date);
                    storage.save(&initial)?;
                    (initial, false, false)
                }
            }
        };

        Ok(Self {
            state,
            storage,
            revision: 1,
            recovered,
            imported_json,
            undo_state: None,
        })
    }

    pub fn state(&self) -> &AppState {
        &self.state
    }

    pub fn revision(&self) -> u64 {
        self.revision
    }

    pub fn was_recovered(&self) -> bool {
        self.recovered
    }

    pub fn imported_json(&self) -> bool {
        self.imported_json
    }

    pub fn recovery_state(&self) -> PouchResult<Option<AppState>> {
        self.storage.load_recovery_copy()
    }

    pub fn update_preferences(&mut self, preferences: Preferences) -> PouchResult<u64> {
        self.apply(|state| crate::preferences::update(state, preferences))
    }

    pub fn replace_state(&mut self, next: AppState) -> PouchResult<u64> {
        self.commit(next)
    }

    pub fn reset(&mut self, start_date: Date) -> PouchResult<u64> {
        self.commit(AppState::fresh(start_date))
    }

    pub fn apply(
        &mut self,
        update: impl FnOnce(&mut AppState) -> PouchResult<()>,
    ) -> PouchResult<u64> {
        let mut next = self.state.clone();
        update(&mut next)?;
        self.commit(next)
    }

    pub fn apply_reversible(
        &mut self,
        update: impl FnOnce(&mut AppState) -> PouchResult<()>,
    ) -> PouchResult<u64> {
        let previous = self.state.clone();
        let mut next = previous.clone();
        update(&mut next)?;
        let revision = self.commit(next)?;
        self.undo_state = Some(previous);
        Ok(revision)
    }

    pub fn undo(&mut self) -> PouchResult<bool> {
        let Some(previous) = self.undo_state.clone() else {
            return Ok(false);
        };
        previous.validate()?;
        let revision = self
            .revision
            .checked_add(1)
            .ok_or(PouchError::TotalTooLarge)?;
        self.storage.save(&previous)?;
        self.state = previous;
        self.undo_state = None;
        self.revision = revision;
        self.recovered = false;
        self.imported_json = false;
        Ok(true)
    }

    fn commit(&mut self, next: AppState) -> PouchResult<u64> {
        next.validate()?;
        let revision = self
            .revision
            .checked_add(1)
            .ok_or(PouchError::TotalTooLarge)?;
        self.storage.save(&next)?;
        self.state = next;
        self.revision = revision;
        self.recovered = false;
        self.imported_json = false;
        self.undo_state = None;
        Ok(self.revision)
    }
}

#[cfg(test)]
mod tests {
    use chrono::Local;

    use super::CoreModules;
    use crate::{Date, Money, models::Category};

    #[test]
    fn reversible_changes_persist_and_undo_once() {
        let directory = tempfile::tempdir().expect("a temporary directory is available");
        let today = Date::from_naive_date(Local::now().date_naive()).expect("today is supported");
        let mut core = CoreModules::open(directory.path(), &[]).expect("the core opens");
        let id = "purchase".to_owned();
        core.apply(|state| {
            crate::purchases::add(
                state,
                id.clone(),
                today,
                "Lunch".into(),
                Money::from_hundredths(1200)?,
                Category::Food,
            )
        })
        .expect("the purchase is saved");
        core.apply_reversible(|state| crate::purchases::remove(state, today, &id))
            .expect("the purchase can be removed");

        assert_eq!(
            core.state().days.get(&today).map(|day| day.purchases.len()),
            Some(0)
        );
        assert!(core.undo().expect("the deletion can be undone"));
        assert_eq!(
            core.state().days.get(&today).map(|day| day.purchases.len()),
            Some(1)
        );
        assert!(!core.undo().expect("undo is available once"));
    }
}
