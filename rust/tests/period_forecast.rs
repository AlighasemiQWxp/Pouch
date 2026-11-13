use pouch_core::{
    AppState, Date, Money, budget, expenses, forecast, income,
    models::{Calendar, Category, PlannedKind, Recurrence},
    periods,
};
fn date(s: &str) -> Date {
    Date::parse_iso(s).unwrap()
}
#[test]
fn historical_and_current_forecasts_are_read_only_and_use_the_selected_period() {
    let mut state = AppState::fresh(date("2024-01-01"));
    periods::create(
        &mut state,
        date("2024-01-01"),
        date("2024-01-08"),
        Recurrence::Weekly,
        Calendar::Gregorian,
    )
    .unwrap();
    income::record(
        &mut state,
        "one".into(),
        date("2024-01-01"),
        Money::from_hundredths(700).unwrap(),
    )
    .unwrap();
    periods::create(
        &mut state,
        date("2024-01-08"),
        date("2024-01-15"),
        Recurrence::Weekly,
        Calendar::Gregorian,
    )
    .unwrap();
    income::record(
        &mut state,
        "two".into(),
        date("2024-01-08"),
        Money::from_hundredths(1400).unwrap(),
    )
    .unwrap();
    expenses::save_planned(
        &mut state,
        expenses::create_planned(
            "target".into(),
            "Goal".into(),
            Money::from_hundredths(5000).unwrap(),
            Category::Other,
            PlannedKind::Goal,
            date("2024-02-01"),
        ),
    )
    .unwrap();
    let before = state.clone();
    let past = forecast::preview(&state, date("2024-01-07"), "target", false, false).unwrap();
    let current = forecast::preview(&state, date("2024-01-08"), "target", false, false).unwrap();
    assert_eq!(past.period_income, 700);
    assert_eq!(current.period_income, 1400);
    assert_eq!(state, before);
    assert_eq!(
        budget::recommend(&state, date("2024-01-08"))
            .unwrap()
            .income,
        1400
    );
}

#[test]
fn one_time_rollover_is_not_repeated_as_future_income() {
    let mut state = AppState::fresh(date("2024-01-01"));
    periods::create(
        &mut state,
        date("2024-01-01"),
        date("2024-01-08"),
        Recurrence::Weekly,
        Calendar::Gregorian,
    )
    .unwrap();
    income::record(
        &mut state,
        "once".into(),
        date("2024-01-01"),
        Money::from_hundredths(1000).unwrap(),
    )
    .unwrap();
    periods::create(
        &mut state,
        date("2024-01-08"),
        date("2024-01-15"),
        Recurrence::Weekly,
        Calendar::Gregorian,
    )
    .unwrap();
    expenses::save_planned(
        &mut state,
        expenses::create_planned(
            "target".into(),
            "Goal".into(),
            Money::from_hundredths(10000).unwrap(),
            Category::Other,
            PlannedKind::Goal,
            date("2024-02-01"),
        ),
    )
    .unwrap();
    pouch_core::purchases::add(
        &mut state,
        "food".into(),
        date("2024-01-08"),
        "Food".into(),
        Money::from_hundredths(10).unwrap(),
        Category::Food,
    )
    .unwrap();
    let before = state.clone();
    let result = forecast::preview(&state, date("2024-01-08"), "target", false, false).unwrap();
    assert_eq!(result.period_income, 0);
    assert_eq!(result.completion_date, None);
    assert_eq!(state, before);
}

#[test]
fn unrelated_bills_outside_the_period_do_not_change_a_target_forecast() {
    let mut state = AppState::fresh(date("2024-01-01"));
    let period = periods::create(
        &mut state,
        date("2024-01-01"),
        date("2024-01-08"),
        Recurrence::Weekly,
        Calendar::Gregorian,
    )
    .unwrap();
    let as_of = date("2024-01-01");
    income::record(
        &mut state,
        "salary".into(),
        as_of,
        Money::from_hundredths(10_000).unwrap(),
    )
    .unwrap();
    for (id, due, amount) in [
        ("current", "2024-01-05", 3_000),
        ("future", "2024-01-08", 20_000),
    ] {
        expenses::save_planned(
            &mut state,
            expenses::create_planned(
                id.into(),
                id.into(),
                Money::from_hundredths(amount).unwrap(),
                Category::Bills,
                PlannedKind::Expense,
                date(due),
            ),
        )
        .unwrap();
        periods::context::assign_planned(&mut state, id, &period).unwrap();
    }
    let with_future_bill = forecast::preview(&state, as_of, "current", true, true).unwrap();
    let future_bill = forecast::preview(&state, as_of, "future", true, true).unwrap();
    assert_eq!(future_bill.allocated, 0);
    assert_eq!(future_bill.remaining, 20_000);
    assert!(future_bill.income_gap.unwrap() > 0);

    expenses::remove_planned(&mut state, "future").unwrap();
    assert_eq!(
        forecast::preview(&state, as_of, "current", true, true).unwrap(),
        with_future_bill
    );
}

#[test]
fn forecasts_use_assigned_targets_even_when_due_dates_are_outside_the_period() {
    let mut state = AppState::fresh(date("2024-01-01"));
    let first = periods::create(
        &mut state,
        date("2024-01-01"),
        date("2024-01-08"),
        Recurrence::Weekly,
        Calendar::Gregorian,
    )
    .unwrap();
    let second = periods::create(
        &mut state,
        date("2024-01-08"),
        date("2024-01-15"),
        Recurrence::Weekly,
        Calendar::Gregorian,
    )
    .unwrap();
    income::receive(
        &mut state,
        "salary".into(),
        date("2024-01-02"),
        Money::from_hundredths(1000).unwrap(),
        Some(&first),
        None,
        false,
    )
    .unwrap();
    for (id, period_id) in [("first", &first), ("second", &second)] {
        expenses::save_planned(
            &mut state,
            expenses::create_planned(
                id.into(),
                id.into(),
                Money::from_hundredths(5000).unwrap(),
                Category::Other,
                PlannedKind::Goal,
                date("2024-03-01"),
            ),
        )
        .unwrap();
        periods::context::assign_planned(&mut state, id, period_id).unwrap();
    }
    let before = state.clone();
    assert_eq!(
        forecast::preview(&state, date("2024-01-07"), "first", false, false)
            .unwrap()
            .period_income,
        1000
    );
    assert!(forecast::preview(&state, date("2024-01-07"), "second", false, false).is_err());
    assert!(forecast::preview(&state, date("2024-01-08"), "first", false, false).is_err());
    assert!(forecast::preview(&state, date("2024-01-08"), "second", false, false).is_ok());
    assert_eq!(state, before);
}
