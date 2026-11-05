use pouch_core::{
    AppState, Date, Money, backup, budget, expenses, income,
    models::{BudgetPlan, Calendar, Category, PlannedKind, Recurrence, SavingsAllocation},
    periods, savings,
};

#[test]
fn old_goal_driven_allocation_is_rebuilt_from_the_savings_plan() {
    let start = Date::parse_iso("2024-10-10").unwrap();
    let end = Date::parse_iso("2024-11-10").unwrap();
    let effective = Date::parse_iso("2024-10-20").unwrap();
    let mut state = AppState::fresh(start);
    periods::create(
        &mut state,
        start,
        end,
        Recurrence::Monthly,
        Calendar::Gregorian,
    )
    .unwrap();
    income::record(
        &mut state,
        "income".into(),
        start,
        Money::from_hundredths(4_000_000_000).unwrap(),
    )
    .unwrap();
    budget::save_plan(
        &mut state,
        BudgetPlan {
            period_id: "BP-001".into(),
            effective,
            savings: Money::from_hundredths(700_000_000).unwrap(),
        },
    )
    .unwrap();
    expenses::save_planned(
        &mut state,
        expenses::create_planned(
            "goal".into(),
            "Car".into(),
            Money::from_hundredths(50_000_000_000).unwrap(),
            Category::Shopping,
            PlannedKind::Goal,
            Date::parse_iso("2030-03-20").unwrap(),
        ),
    )
    .unwrap();
    state.allocations = vec![SavingsAllocation {
        period_id: "BP-001".into(),
        date: start,
        amount: 1_270_849_881,
    }];
    let mut old = serde_json::to_value(&state).unwrap();
    old["schemaVersion"] = 7.into();
    old.as_object_mut().unwrap().remove("financialMetadata");
    let backup = serde_json::json!({"version": 10, "state": old}).to_string();
    let restored = backup::import_json(&backup).unwrap();
    assert_eq!(
        savings::recorded_balance(&restored, effective).unwrap(),
        700_000_000
    );
    assert_eq!(restored.income, state.income);
    assert_eq!(restored.planned, state.planned);
}

#[test]
fn changing_goal_target_does_not_increase_savings() {
    let date = Date::parse_iso("2024-10-10").unwrap();
    let mut state = AppState::fresh(date);
    periods::create(
        &mut state,
        date,
        Date::parse_iso("2024-11-10").unwrap(),
        Recurrence::Monthly,
        Calendar::Gregorian,
    )
    .unwrap();
    income::record(
        &mut state,
        "income".into(),
        date,
        Money::from_hundredths(10_000).unwrap(),
    )
    .unwrap();
    budget::save_plan(
        &mut state,
        BudgetPlan {
            period_id: "BP-001".into(),
            effective: date,
            savings: Money::from_hundredths(2_000).unwrap(),
        },
    )
    .unwrap();
    expenses::save_planned(
        &mut state,
        expenses::create_planned(
            "goal".into(),
            "Car".into(),
            Money::from_hundredths(100_000).unwrap(),
            Category::Shopping,
            PlannedKind::Goal,
            Date::parse_iso("2028-03-20").unwrap(),
        ),
    )
    .unwrap();
    savings::reconcile(&mut state, date).unwrap();
    assert_eq!(savings::recorded_balance(&state, date).unwrap(), 2_000);
    assert_eq!(budget::cash(&state, date).unwrap(), 10_000);
}
