use pouch_core::{
    AppState, Date, Money, PouchCore, backup,
    models::{Calendar, Recurrence},
    periods,
};
fn date(s: &str) -> Date {
    Date::parse_iso(s).unwrap()
}
#[test]
fn failed_receipt_and_failed_edit_leave_saved_state_and_revision_unchanged() {
    let dir = tempfile::tempdir().unwrap();
    let mut core = PouchCore::open(dir.path(), &[]).unwrap();
    core.apply(|state| {
        periods::create(
            state,
            date("2024-01-01"),
            date("2024-02-01"),
            Recurrence::Monthly,
            Calendar::Gregorian,
        )
        .map(|_| ())
    })
    .unwrap();
    let before = core.state().clone();
    let revision = core.revision();
    let bytes = std::fs::read(dir.path().join("pouch.data")).unwrap();
    assert!(
        core.apply(|state| pouch_core::income::receive(
            state,
            "bad".into(),
            date("2024-01-01"),
            Money::from_hundredths(100)?,
            None,
            Some((date("2024-01-08"), Recurrence::Weekly, Calendar::Gregorian)),
            false
        ))
        .is_err()
    );
    assert!(
        core.apply(|state| periods::edit(
            state,
            "BP-001",
            date("2024-01-10"),
            date("2024-01-09"),
            Recurrence::Once,
            Calendar::Gregorian
        ))
        .is_err()
    );
    assert_eq!(core.state(), &before);
    assert_eq!(core.revision(), revision);
    assert_eq!(std::fs::read(dir.path().join("pouch.data")).unwrap(), bytes);
}
#[test]
fn current_formats_round_trip_and_unsupported_files_are_preserved() {
    let mut state = AppState::fresh(date("2024-01-01"));
    periods::create(
        &mut state,
        date("2024-01-01"),
        date("2024-02-01"),
        Recurrence::Monthly,
        Calendar::Gregorian,
    )
    .unwrap();
    assert_eq!(
        backup::import_json(&backup::export_json(&state).unwrap()).unwrap(),
        state
    );
    assert!(backup::import_json("{\"version\":7}").is_err());
    let dir = tempfile::tempdir().unwrap();
    let mut store = pouch_core::storage::BinaryStore::new(dir.path());
    store.save(&state).unwrap();
    let path = dir.path().join("pouch.data");
    let mut bytes = std::fs::read(&path).unwrap();
    bytes[8..10].copy_from_slice(&2u16.to_le_bytes());
    std::fs::write(&path, &bytes).unwrap();
    assert!(store.load().is_err());
    assert_eq!(std::fs::read(path).unwrap(), bytes);
}
#[test]
fn period_creation_undo_survives_persistence() {
    let dir = tempfile::tempdir().unwrap();
    let mut core = PouchCore::open(dir.path(), &[]).unwrap();
    core.apply_reversible(|state| {
        periods::create(
            state,
            date("2024-01-01"),
            date("2024-02-01"),
            Recurrence::Monthly,
            Calendar::Gregorian,
        )
        .map(|_| ())
    })
    .unwrap();
    assert_eq!(
        PouchCore::open(dir.path(), &[])
            .unwrap()
            .state()
            .periods
            .len(),
        1
    );
    assert!(core.undo().unwrap());
    assert!(
        PouchCore::open(dir.path(), &[])
            .unwrap()
            .state()
            .periods
            .is_empty()
    );
}

#[test]
fn explicit_incompatible_reset_archives_original_files() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("pouch.data");
    let state = AppState::fresh(date("2024-01-01"));
    let mut store = pouch_core::storage::BinaryStore::new(dir.path());
    store.save(&state).unwrap();
    let mut old = std::fs::read(&path).unwrap();
    old[8..10].copy_from_slice(&2u16.to_le_bytes());
    std::fs::write(&path, &old).unwrap();
    assert!(store.save(&state).is_err());
    assert_eq!(std::fs::read(&path).unwrap(), old);
    pouch_core::api::reset_incompatible_storage(dir.path().to_string_lossy().into()).unwrap();
    let archive = std::fs::read_dir(dir.path())
        .unwrap()
        .map(|entry| entry.unwrap().path())
        .find(|path| path.is_dir())
        .unwrap();
    assert_eq!(std::fs::read(archive.join("pouch.data")).unwrap(), old);
    assert!(
        PouchCore::open(dir.path(), &[])
            .unwrap()
            .state()
            .periods
            .is_empty()
    );
}

#[test]
fn inspecting_another_period_does_not_change_today_revision_or_backup() {
    let dir = tempfile::tempdir().unwrap();
    let today = Date::from_naive_date(chrono::Local::now().date_naive()).unwrap();
    let mut state = AppState::fresh(today.add_days(-14).unwrap());
    periods::create(
        &mut state,
        today.add_days(-14).unwrap(),
        today.add_days(-7).unwrap(),
        Recurrence::Weekly,
        Calendar::Gregorian,
    )
    .unwrap();
    periods::create(
        &mut state,
        today.add_days(-7).unwrap(),
        today.add_days(7).unwrap(),
        Recurrence::Biweekly,
        Calendar::Gregorian,
    )
    .unwrap();
    pouch_core::storage::BinaryStore::new(dir.path())
        .save(&state)
        .unwrap();
    let app = pouch_core::api::PouchApp::open(dir.path().to_string_lossy().into(), vec![]).unwrap();
    let before = app.snapshot().unwrap();
    let backup = app.export_backup().unwrap();
    app.period_view(today.add_days(-14).unwrap().iso().unwrap())
        .unwrap();
    let after = app.snapshot().unwrap();
    assert_eq!(
        after.current_period.unwrap().id,
        before.current_period.unwrap().id
    );
    assert_eq!(after.revision, before.revision);
    assert_eq!(app.export_backup().unwrap(), backup);
}

#[test]
fn unsupported_recovery_copy_is_never_silently_overwritten() {
    let dir = tempfile::tempdir().unwrap();
    let state = AppState::fresh(date("2024-01-01"));
    let mut store = pouch_core::storage::BinaryStore::new(dir.path());
    store.save(&state).unwrap();
    let path = dir.path().join("pouch.data.backup");
    let mut old = std::fs::read(&path).unwrap();
    old[8..10].copy_from_slice(&2u16.to_le_bytes());
    std::fs::write(&path, &old).unwrap();
    assert!(store.load().is_err());
    assert!(store.save(&state).is_err());
    assert_eq!(std::fs::read(&path).unwrap(), old);
}

#[test]
fn deleting_current_past_and_future_savings_is_persisted_and_undoable() {
    use pouch_core::{budget, income, models::BudgetPlan};

    let dir = tempfile::tempdir().unwrap();
    let today = Date::from_naive_date(chrono::Local::now().date_naive()).unwrap();
    let start = today.add_days(-7).unwrap();
    let mut core = PouchCore::open(dir.path(), &[]).unwrap();
    core.apply(|state| {
        let period_id = periods::create(
            state,
            start,
            today.add_days(14)?,
            Recurrence::Monthly,
            Calendar::Gregorian,
        )?;
        income::record(state, "salary".into(), start, Money::from_hundredths(1000)?)?;
        for (effective, amount) in [(start, 200), (today, 400), (today.add_days(1)?, 600)] {
            budget::save_plan(
                state,
                BudgetPlan {
                    period_id: period_id.clone(),
                    effective,
                    savings: Money::from_hundredths(amount)?,
                },
            )?;
        }
        Ok(())
    })
    .unwrap();
    let original = core.state().clone();
    for effective in [start, today, today.add_days(1).unwrap()] {
        core.apply_reversible(|state| budget::remove_plan(state, effective))
            .unwrap();
        assert_eq!(core.state().plans.len(), 2);
        assert!(
            !core
                .state()
                .plans
                .iter()
                .any(|plan| plan.effective == effective)
        );
        assert_eq!(core.state().income, original.income);
        let reopened = PouchCore::open(dir.path(), &[]).unwrap();
        assert_eq!(reopened.state(), core.state());
        assert!(core.undo().unwrap());
        assert_eq!(core.state(), &original);
        assert_eq!(PouchCore::open(dir.path(), &[]).unwrap().state(), &original);
    }
    let revision = core.revision();
    let bytes = std::fs::read(dir.path().join("pouch.data")).unwrap();
    assert!(
        core.apply_reversible(|state| budget::remove_plan(state, today.add_days(2)?))
            .is_err()
    );
    assert_eq!(core.state(), &original);
    assert_eq!(core.revision(), revision);
    assert_eq!(std::fs::read(dir.path().join("pouch.data")).unwrap(), bytes);
}

#[test]
fn assigned_income_persists_and_undo_restores_its_period() {
    let dir = tempfile::tempdir().unwrap();
    let mut core = PouchCore::open(dir.path(), &[]).unwrap();
    core.apply(|state| {
        let first = periods::create(
            state,
            date("2024-01-01"),
            date("2024-01-08"),
            Recurrence::Weekly,
            Calendar::Gregorian,
        )?;
        periods::create(
            state,
            date("2024-01-08"),
            date("2024-01-15"),
            Recurrence::Weekly,
            Calendar::Gregorian,
        )?;
        pouch_core::income::receive(
            state,
            "salary".into(),
            date("2024-01-10"),
            Money::from_hundredths(1000)?,
            Some(&first),
            None,
            false,
        )
    })
    .unwrap();
    let before = core.state().clone();
    core.apply_reversible(|state| periods::context::assign_income(state, "salary", "BP-002"))
        .unwrap();
    assert_eq!(
        PouchCore::open(dir.path(), &[])
            .unwrap()
            .state()
            .period_context
            .income["salary"],
        "BP-002"
    );
    assert!(core.undo().unwrap());
    assert_eq!(core.state(), &before);
    let revision = core.revision();
    assert!(
        core.apply_reversible(|state| periods::context::assign_income(state, "salary", "missing"))
            .is_err()
    );
    assert_eq!(core.state(), &before);
    assert_eq!(core.revision(), revision);
}

#[test]
fn current_user_files_upgrade_without_resetting_records_or_ids() {
    let mut state = AppState::fresh(date("2024-01-01"));
    periods::create(
        &mut state,
        date("2024-01-01"),
        date("2024-02-01"),
        Recurrence::Monthly,
        Calendar::Gregorian,
    )
    .unwrap();
    pouch_core::income::record(
        &mut state,
        "salary".into(),
        date("2024-01-10"),
        Money::from_hundredths(2000).unwrap(),
    )
    .unwrap();
    let payload = postcard::to_allocvec(&(
        5u16,
        (
            5u16,
            state.start_date,
            &state.preferences,
            &state.periods,
            &state.essentials,
            &state.allocations,
            &state.receipts,
            &state.income,
            &state.expected_income,
            &state.plans,
            &state.days,
            &state.planned,
            &state.economic_assumptions,
        ),
    ))
    .unwrap();
    let mut previous = b"POUCHDAT".to_vec();
    previous.extend_from_slice(&3u16.to_le_bytes());
    previous.extend_from_slice(&(payload.len() as u32).to_le_bytes());
    previous.extend_from_slice(&crc32fast::hash(&payload).to_le_bytes());
    previous.extend_from_slice(&payload);
    let dir = tempfile::tempdir().unwrap();
    std::fs::write(dir.path().join("pouch.data"), &previous).unwrap();
    let core = PouchCore::open(dir.path(), &[]).unwrap();
    assert_eq!(core.state().income, state.income);
    assert_eq!(core.state().periods, state.periods);
    assert_eq!(core.state().days, state.days);
    assert_eq!(core.state().allocations, state.allocations);
    assert_eq!(
        core.state().schema_version,
        AppState::CURRENT_SCHEMA_VERSION
    );
    assert_eq!(
        std::fs::read(dir.path().join("pouch.data.backup")).unwrap(),
        previous
    );
    let names = core.state().period_context.names.clone();
    assert_eq!(
        PouchCore::open(dir.path(), &[])
            .unwrap()
            .state()
            .period_context
            .names,
        names
    );

    let mut old_state = serde_json::to_value(&state).unwrap();
    old_state["schemaVersion"] = 5.into();
    old_state.as_object_mut().unwrap().remove("periodContext");
    let previous_backup = serde_json::json!({"version": 8, "state": old_state}).to_string();
    let upgraded = backup::import_json(&previous_backup).unwrap();
    assert_eq!(upgraded.income, state.income);
    assert_eq!(upgraded.periods, state.periods);
    assert_eq!(upgraded.days, state.days);
    assert_eq!(upgraded.allocations, state.allocations);
    assert_eq!(
        backup::import_json(&backup::export_json(&upgraded).unwrap()).unwrap(),
        upgraded
    );
}

#[test]
fn unused_period_deletion_persists_and_can_be_undone() {
    let dir = tempfile::tempdir().unwrap();
    let mut core = PouchCore::open(dir.path(), &[]).unwrap();
    core.apply(|state| {
        for (start, end) in [
            ("2024-01-01", "2024-01-08"),
            ("2024-01-08", "2024-01-15"),
            ("2024-01-15", "2024-01-22"),
        ] {
            periods::create(
                state,
                date(start),
                date(end),
                Recurrence::Weekly,
                Calendar::Gregorian,
            )?;
        }
        Ok(())
    })
    .unwrap();
    let before = core.state().clone();
    core.apply_reversible(|state| periods::remove(state, "BP-002"))
        .unwrap();
    assert_eq!(core.state().periods.len(), 2);
    assert_eq!(core.state().periods[0].end, date("2024-01-15"));
    assert!(!core.state().period_context.names.contains_key("BP-002"));
    assert_eq!(
        PouchCore::open(dir.path(), &[]).unwrap().state(),
        core.state()
    );
    assert!(core.undo().unwrap());
    assert_eq!(core.state(), &before);
    for id in ["BP-001", "BP-003", "BP-002"] {
        core.apply_reversible(|state| periods::remove(state, id))
            .unwrap();
    }
    assert!(core.state().periods.is_empty());
    assert!(core.state().period_context.names.is_empty());
}

#[test]
fn deleting_a_period_with_income_is_atomic_even_for_outside_dates() {
    let mut state = AppState::fresh(date("2024-01-01"));
    let id = periods::create(
        &mut state,
        date("2024-01-01"),
        date("2024-02-01"),
        Recurrence::Monthly,
        Calendar::Gregorian,
    )
    .unwrap();
    pouch_core::income::receive(
        &mut state,
        "salary".into(),
        date("2024-03-01"),
        Money::from_hundredths(1000).unwrap(),
        Some(&id),
        None,
        false,
    )
    .unwrap();
    let before = state.clone();
    assert!(periods::remove(&mut state, &id).is_err());
    assert_eq!(state, before);
}

#[test]
fn period_deletion_preserves_linked_savings_purchases_and_targets() {
    use pouch_core::models::{BudgetPlan, Category, PlannedKind};
    let mut base = AppState::fresh(date("2024-01-01"));
    let id = periods::create(
        &mut base,
        date("2024-01-01"),
        date("2024-02-01"),
        Recurrence::Monthly,
        Calendar::Gregorian,
    )
    .unwrap();
    for kind in ["savings", "purchase", "goal", "expected"] {
        let mut state = base.clone();
        match kind {
            "savings" => pouch_core::budget::save_plan(
                &mut state,
                BudgetPlan {
                    period_id: id.clone(),
                    effective: date("2024-01-02"),
                    savings: Money::from_hundredths(100).unwrap(),
                },
            )
            .unwrap(),
            "purchase" => pouch_core::purchases::add(
                &mut state,
                "purchase".into(),
                date("2024-01-02"),
                "Coffee".into(),
                Money::from_hundredths(100).unwrap(),
                Category::Food,
            )
            .unwrap(),
            "goal" => {
                let target = pouch_core::expenses::create_planned(
                    "goal".into(),
                    "Goal".into(),
                    Money::from_hundredths(100).unwrap(),
                    Category::Other,
                    PlannedKind::Goal,
                    date("2024-03-01"),
                );
                pouch_core::expenses::save_planned(&mut state, target).unwrap();
                periods::context::assign_planned(&mut state, "goal", &id).unwrap();
            }
            "expected" => {
                let tomorrow = Date::from_naive_date(chrono::Local::now().date_naive())
                    .unwrap()
                    .add_days(1)
                    .unwrap();
                pouch_core::income::schedule(
                    &mut state,
                    "expected".into(),
                    tomorrow,
                    Money::from_hundredths(100).unwrap(),
                )
                .unwrap();
                periods::context::assign_income(&mut state, "expected", &id).unwrap();
            }
            _ => unreachable!(),
        }
        state.validate().unwrap();
        let before = state.clone();
        assert!(periods::remove(&mut state, &id).is_err(), "{kind}");
        assert_eq!(state, before, "{kind}");
    }
}

fn inflated_savings_state() -> AppState {
    use pouch_core::{budget, expenses, income, models::*, purchases};

    let mut state = AppState::fresh(date("2024-01-01"));
    let period_id = periods::create(
        &mut state,
        date("2024-01-01"),
        date("2024-02-01"),
        Recurrence::Monthly,
        Calendar::Gregorian,
    )
    .unwrap();
    income::receive(
        &mut state,
        "salary".into(),
        date("2024-01-01"),
        Money::from_hundredths(100_000).unwrap(),
        Some(&period_id),
        None,
        false,
    )
    .unwrap();
    expenses::save_planned(
        &mut state,
        expenses::create_planned(
            "goal".into(),
            "Long term goal".into(),
            Money::from_hundredths(62_000).unwrap(),
            Category::Other,
            PlannedKind::Goal,
            date("2024-03-02"),
        ),
    )
    .unwrap();
    periods::context::assign_planned(&mut state, "goal", &period_id).unwrap();
    budget::save_plan(
        &mut state,
        BudgetPlan {
            period_id: period_id.clone(),
            effective: date("2024-01-04"),
            savings: Money::from_hundredths(40_000).unwrap(),
        },
    )
    .unwrap();
    purchases::add(
        &mut state,
        "purchase".into(),
        date("2024-01-05"),
        "Food".into(),
        Money::from_hundredths(500).unwrap(),
        Category::Food,
    )
    .unwrap();
    state.allocations = [
        ("2024-01-01", 60_000),
        ("2024-01-02", 40_000),
        ("2024-01-05", -500),
    ]
    .into_iter()
    .map(|(day, amount)| SavingsAllocation {
        period_id: period_id.clone(),
        date: date(day),
        amount,
    })
    .collect();
    state.validate().unwrap();
    state
}

fn previous_binary(state: &AppState) -> Vec<u8> {
    let mut previous = state.clone();
    previous.schema_version = 6;
    let payload = postcard::to_allocvec(&(6u16, previous)).unwrap();
    let mut bytes = b"POUCHDAT".to_vec();
    bytes.extend_from_slice(&4u16.to_le_bytes());
    bytes.extend_from_slice(&(payload.len() as u32).to_le_bytes());
    bytes.extend_from_slice(&crc32fast::hash(&payload).to_le_bytes());
    bytes.extend_from_slice(&payload);
    bytes
}

fn assert_repaired_savings(original: &AppState, repaired: &AppState) {
    let mut ledger = serde_json::to_value(original).unwrap();
    ledger["schemaVersion"] = AppState::CURRENT_SCHEMA_VERSION.into();
    ledger["allocations"] = serde_json::to_value(&repaired.allocations).unwrap();
    assert_eq!(ledger, serde_json::to_value(repaired).unwrap());
    let summary = pouch_core::budget::recommend(repaired, date("2024-01-05")).unwrap();
    assert_eq!(summary.savings, 40_000);
    assert_eq!(summary.remaining, 59_500);
    assert_eq!(summary.recommendation, 1722);
    assert_eq!(
        pouch_core::budget::recommend(repaired, date("2024-01-06"))
            .unwrap()
            .recommendation,
        2288
    );
}

#[test]
fn version_nine_backup_repairs_savings_and_keeps_every_ledger_record() {
    let original = inflated_savings_state();
    let mut previous = original.clone();
    previous.schema_version = 6;
    let contents = serde_json::json!({"version": 9, "state": previous}).to_string();
    let repaired = backup::import_json(&contents).unwrap();
    assert_repaired_savings(&original, &repaired);
    let current = backup::export_json(&repaired).unwrap();
    assert_eq!(
        serde_json::from_str::<serde_json::Value>(&current).unwrap()["version"],
        10
    );
    assert_eq!(backup::import_json(&current).unwrap(), repaired);
    let dir = tempfile::tempdir().unwrap();
    let mut core = PouchCore::open(dir.path(), &[]).unwrap();
    core.replace_state(repaired.clone()).unwrap();
    assert_eq!(PouchCore::open(dir.path(), &[]).unwrap().state(), &repaired);
    core.apply_reversible(|state| {
        pouch_core::purchases::remove(state, date("2024-01-05"), "purchase")
    })
    .unwrap();
    assert!(core.undo().unwrap());
    assert_eq!(core.state(), &repaired);
    assert_eq!(PouchCore::open(dir.path(), &[]).unwrap().state(), &repaired);
}

#[test]
fn version_four_binary_repairs_once_and_preserves_original_recovery_bytes() {
    let original = inflated_savings_state();
    let previous = previous_binary(&original);
    let dir = tempfile::tempdir().unwrap();
    let primary = dir.path().join("pouch.data");
    let recovery = dir.path().join("pouch.data.backup");
    std::fs::write(&primary, &previous).unwrap();
    let core = PouchCore::open(dir.path(), &[]).unwrap();
    assert_repaired_savings(&original, core.state());
    assert_eq!(std::fs::read(&recovery).unwrap(), previous);
    let upgraded = std::fs::read(&primary).unwrap();
    let reopened = PouchCore::open(dir.path(), &[]).unwrap();
    assert_eq!(core.state(), reopened.state());
    assert_eq!(std::fs::read(&primary).unwrap(), upgraded);
    assert_eq!(std::fs::read(&recovery).unwrap(), previous);
}

#[test]
fn corrupt_primary_can_recover_and_repair_previous_savings_data() {
    let original = inflated_savings_state();
    let previous = previous_binary(&original);
    let dir = tempfile::tempdir().unwrap();
    std::fs::write(dir.path().join("pouch.data"), b"incomplete").unwrap();
    std::fs::write(dir.path().join("pouch.data.backup"), &previous).unwrap();
    let core = PouchCore::open(dir.path(), &[]).unwrap();
    assert!(core.was_recovered());
    assert_repaired_savings(&original, core.state());
    assert_eq!(
        std::fs::read(dir.path().join("pouch.data.backup")).unwrap(),
        previous
    );
}

#[test]
fn backup_versions_require_the_matching_state_schema() {
    let original = inflated_savings_state();
    for (version, schema) in [(8, 6), (9, 7), (10, 6), (11, 7)] {
        let mut state = original.clone();
        state.schema_version = schema;
        let contents = serde_json::json!({"version": version, "state": state}).to_string();
        assert!(backup::import_json(&contents).is_err());
    }
}

#[test]
fn version_eight_backup_also_repairs_inflated_savings() {
    let original = inflated_savings_state();
    let mut previous = serde_json::to_value(&original).unwrap();
    previous["schemaVersion"] = 5.into();
    previous.as_object_mut().unwrap().remove("periodContext");
    let contents = serde_json::json!({"version": 8, "state": previous}).to_string();
    let repaired = backup::import_json(&contents).unwrap();
    let mut expected = original.clone();
    expected.period_context = repaired.period_context.clone();
    assert_repaired_savings(&expected, &repaired);
    assert_eq!(repaired.period_context.names.len(), 1);
}

#[test]
fn repair_keeps_goal_payments_and_their_historical_funding() {
    use pouch_core::{budget, expenses, models::*, savings};

    let mut original = inflated_savings_state();
    original.allocations.clear();
    original.plans.clear();
    original.planned[0].date = date("2024-01-10");
    savings::reconcile(&mut original, date("2024-01-01")).unwrap();
    expenses::mark_paid(
        &mut original,
        "goal",
        "goal-payment".into(),
        date("2024-01-10"),
        Money::from_hundredths(62_000).unwrap(),
    )
    .unwrap();
    let mut previous = original.clone();
    previous.schema_version = 6;
    let contents = serde_json::json!({"version": 9, "state": previous}).to_string();
    let repaired = backup::import_json(&contents).unwrap();
    assert_eq!(repaired.days, original.days);
    assert_eq!(repaired.planned, original.planned);
    assert_eq!(repaired.planned[0].status, PlannedStatus::Paid);
    assert_eq!(
        budget::recommend(&repaired, date("2024-01-09"))
            .unwrap()
            .savings,
        62_000
    );
    let after = budget::funding(&repaired, date("2024-01-10")).unwrap();
    assert_eq!(after.savings, 0);
    assert_eq!(after.cash, 37_500);
    assert_eq!(after.free, 37_500);
}

#[test]
fn invalid_old_backup_does_not_replace_existing_application_data() {
    let dir = tempfile::tempdir().unwrap();
    let mut app =
        pouch_core::api::PouchApp::open(dir.path().to_string_lossy().into(), vec![]).unwrap();
    let before = app.export_backup().unwrap();
    let primary = std::fs::read(dir.path().join("pouch.data")).unwrap();
    let mut previous = serde_json::to_value(inflated_savings_state()).unwrap();
    previous["schemaVersion"] = 6.into();
    previous["allocations"][0]["periodId"] = "missing".into();
    let contents = serde_json::json!({"version": 9, "state": previous}).to_string();
    assert!(app.import_backup(contents).is_err());
    assert_eq!(app.export_backup().unwrap(), before);
    assert_eq!(
        std::fs::read(dir.path().join("pouch.data")).unwrap(),
        primary
    );
}
