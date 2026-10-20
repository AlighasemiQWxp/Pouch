use pouch_core::{
    AppState, Date, Money, budget, expenses, income,
    models::{BudgetPlan, Calendar, Category, PlannedKind, Recurrence, RequiredExpense},
    periods, savings,
};
fn day(s: &str) -> Date {
    Date::parse_iso(s).unwrap()
}
fn money(n: i64) -> Money {
    Money::from_hundredths(n).unwrap()
}
fn state() -> AppState {
    let mut state = AppState::fresh(day("2024-10-10"));
    periods::create(
        &mut state,
        day("2024-10-10"),
        day("2024-11-10"),
        Recurrence::Monthly,
        Calendar::Gregorian,
    )
    .unwrap();
    state
}
fn receive(state: &mut AppState, id: &str, date: &str, amount: i64) {
    let period = periods::at(state, day(date)).unwrap();
    income::receive(
        state,
        id.into(),
        day(date),
        money(amount),
        Some(&period.id),
        None,
        false,
    )
    .unwrap();
}
fn bill(state: &mut AppState) {
    expenses::save_essential(
        state,
        RequiredExpense {
            id: "rent".into(),
            name: "Rent".into(),
            amount: money(300),
            date: day("2024-10-15"),
            recurrence: Recurrence::Monthly,
            calendar: Calendar::Gregorian,
            until: None,
        },
    )
    .unwrap();
}
#[test]
fn first_period_is_explicit_and_horizon_does_not_create_more_periods() {
    let empty = AppState::fresh(day("2024-10-10"));
    assert!(periods::at(&empty, day("2024-10-10")).is_err());
    let state = state();
    assert!(periods::at(&state, day("2024-11-10")).is_err());
    assert_eq!(
        budget::recommend(&state, day("2024-11-10"))
            .unwrap()
            .days_remaining,
        0
    );
}
#[test]
fn income_calendar_creates_inclusive_exclusive_periods_with_stable_ids() {
    let mut state = state();
    receive(&mut state, "first", "2024-10-10", 2000);
    income::receive(
        &mut state,
        "second".into(),
        day("2024-10-27"),
        money(1500),
        None,
        Some((day("2024-11-27"), Recurrence::Monthly, Calendar::Gregorian)),
        false,
    )
    .unwrap();
    income::receive(
        &mut state,
        "third".into(),
        day("2024-11-08"),
        money(3000),
        None,
        Some((day("2024-12-08"), Recurrence::Monthly, Calendar::Gregorian)),
        false,
    )
    .unwrap();
    assert_eq!(
        state
            .periods
            .iter()
            .map(|p| p.id.as_str())
            .collect::<Vec<_>>(),
        vec!["BP-001", "BP-002", "BP-003"]
    );
    assert_eq!(periods::at(&state, day("2024-10-26")).unwrap().id, "BP-001");
    assert_eq!(periods::at(&state, day("2024-10-27")).unwrap().id, "BP-002");
    assert_eq!(
        budget::funding(&state, day("2024-11-08")).unwrap().cash,
        6500
    );
    assert_eq!(
        budget::recommend(&state, day("2024-11-08")).unwrap().income,
        3000
    );
}
#[test]
fn same_day_income_adds_without_creating_zero_length_periods() {
    let mut state = state();
    receive(&mut state, "one", "2024-10-10", 700);
    receive(&mut state, "two", "2024-10-10", 100);
    let before = state.clone();
    assert!(
        income::receive(
            &mut state,
            "three".into(),
            day("2024-10-10"),
            money(200),
            None,
            Some((day("2024-10-17"), Recurrence::Weekly, Calendar::Gregorian)),
            false
        )
        .is_err()
    );
    assert_eq!(state, before);
    assert_eq!(
        budget::recommend(&state, day("2024-10-10")).unwrap().income,
        800
    );
}
#[test]
fn planning_presets_and_month_anchors_are_calendar_aware() {
    for (kind, expected) in [
        (Recurrence::Weekly, "2024-10-17"),
        (Recurrence::Biweekly, "2024-10-24"),
        (Recurrence::Monthly, "2024-11-10"),
        (Recurrence::Custom(10), "2024-10-20"),
    ] {
        assert_eq!(
            periods::horizon(day("2024-10-10"), kind, Calendar::Gregorian, None).unwrap(),
            day(expected)
        );
    }
    assert_eq!(
        periods::boundary(
            day("2024-01-31"),
            Recurrence::Monthly,
            Calendar::Gregorian,
            2
        )
        .unwrap(),
        day("2024-03-31")
    );
    let anchor = pouch_core::calendar::from_parts(1402, 12, 29, Calendar::Jalali).unwrap();
    let parts = pouch_core::calendar::parts(
        periods::boundary(anchor, Recurrence::Monthly, Calendar::Jalali, 1).unwrap(),
        Calendar::Jalali,
    )
    .unwrap();
    assert_eq!((parts.year, parts.month, parts.day), (1403, 1, 29));
}
#[test]
fn reservations_and_payments_conserve_balances_across_irregular_periods() {
    let mut state = state();
    receive(&mut state, "salary", "2024-10-10", 1000);
    bill(&mut state);
    let before = budget::funding(&state, day("2024-10-10")).unwrap();
    let id = expenses::obligations(&state, day("2024-10-15")).unwrap()[0]
        .id
        .clone();
    expenses::mark_paid(
        &mut state,
        &id,
        "payment".into(),
        day("2024-10-15"),
        money(300),
    )
    .unwrap();
    periods::create(
        &mut state,
        day("2024-10-16"),
        day("2024-10-23"),
        Recurrence::Weekly,
        Calendar::Gregorian,
    )
    .unwrap();
    let paid = budget::funding(&state, day("2024-10-15")).unwrap();
    assert_eq!(paid.cash, before.cash - 300);
    let unpaid_october =
        expenses::outstanding(&state, day("2024-10-16"), day("2024-10-23")).unwrap();
    assert!(unpaid_october.iter().all(|item| item.id != id));
    let after = budget::funding(&state, day("2024-10-16")).unwrap();
    assert_eq!(after.cash, after.free + after.savings + after.reserved);
    assert_eq!(state.income.len(), 1);
    pouch_core::purchases::remove(&mut state, day("2024-10-15"), "payment").unwrap();
    assert_eq!(
        budget::funding(&state, day("2024-10-16")).unwrap().cash,
        1000
    );
    state.validate().unwrap();
}
#[test]
fn deficits_and_protected_savings_roll_without_duplicate_income() {
    let mut state = state();
    receive(&mut state, "salary", "2024-10-10", 1000);
    let period = state.periods[0].clone();
    budget::save_plan(
        &mut state,
        BudgetPlan {
            period_id: period.id,
            effective: period.start,
            savings: money(200),
        },
    )
    .unwrap();
    savings::reconcile(&mut state, period.start).unwrap();
    periods::create(
        &mut state,
        day("2024-10-17"),
        day("2024-10-24"),
        Recurrence::Weekly,
        Calendar::Gregorian,
    )
    .unwrap();
    let funds = budget::funding(&state, day("2024-10-17")).unwrap();
    assert_eq!(funds.savings, 200);
    assert_eq!(funds.free, 800);
    pouch_core::purchases::add(
        &mut state,
        "spent".into(),
        day("2024-10-18"),
        "Food".into(),
        money(1200),
        Category::Food,
    )
    .unwrap();
    periods::create(
        &mut state,
        day("2024-10-20"),
        day("2024-10-27"),
        Recurrence::Weekly,
        Calendar::Gregorian,
    )
    .unwrap();
    let summary = budget::recommend(&state, day("2024-10-20")).unwrap();
    assert_eq!(summary.shortfall, 200);
    assert_eq!(summary.income, 0);
    assert_eq!(summary.recommendation, 0);
}
#[test]
fn missing_expected_income_never_funds_the_budget() {
    let mut state = state();
    income::schedule(
        &mut state,
        "expected".into(),
        Date::from_naive_date(chrono::Local::now().date_naive()).unwrap(),
        money(500),
    )
    .unwrap();
    assert_eq!(budget::funding(&state, day("2024-10-10")).unwrap().cash, 0);
    income::receive(
        &mut state,
        "expected".into(),
        day("2024-10-12"),
        money(400),
        Some("BP-001"),
        None,
        true,
    )
    .unwrap();
    assert_eq!(state.receipts[0].expected_amount, money(500));
    assert_eq!(state.income[0].amount, money(400));
    assert!(state.expected_income.is_empty());
}
#[test]
fn historical_corrections_recalculate_rollover_without_moving_ids() {
    let mut state = state();
    receive(&mut state, "salary", "2024-10-10", 1000);
    periods::create(
        &mut state,
        day("2024-10-17"),
        day("2024-10-24"),
        Recurrence::Weekly,
        Calendar::Gregorian,
    )
    .unwrap();
    income::edit(&mut state, "salary", day("2024-10-11"), money(800)).unwrap();
    assert_eq!(
        budget::recommend(&state, day("2024-10-17")).unwrap().carry,
        800
    );
    let ids: Vec<_> = state.periods.iter().map(|p| p.id.clone()).collect();
    periods::edit(
        &mut state,
        "BP-002",
        day("2024-10-18"),
        day("2024-10-25"),
        Recurrence::Weekly,
        Calendar::Gregorian,
    )
    .unwrap();
    assert_eq!(
        state
            .periods
            .iter()
            .map(|p| p.id.clone())
            .collect::<Vec<_>>(),
        ids
    );
    assert_eq!(state.periods[0].end, day("2024-10-18"));
}
#[test]
fn goal_payment_uses_protected_money_once_and_is_reported() {
    let mut state = state();
    receive(&mut state, "salary", "2024-10-10", 1000);
    let goal = expenses::create_planned(
        "goal".into(),
        "Goal".into(),
        money(400),
        Category::Other,
        PlannedKind::Goal,
        day("2024-10-10"),
    );
    expenses::save_planned(&mut state, goal).unwrap();
    savings::reconcile(&mut state, day("2024-10-10")).unwrap();
    expenses::mark_paid(
        &mut state,
        "goal",
        "goal-paid".into(),
        day("2024-10-10"),
        money(400),
    )
    .unwrap();
    savings::reconcile(&mut state, day("2024-10-10")).unwrap();
    assert_eq!(
        budget::funding(&state, day("2024-10-10")).unwrap().free,
        600
    );
    assert_eq!(
        pouch_core::reports::build(&state, vec![day("2024-10-10")])
            .unwrap()
            .total,
        400
    );
    let before = state.clone();
    savings::reconcile(&mut state, day("2024-10-10")).unwrap();
    assert_eq!(state, before);
}

#[test]
fn monthly_bills_keep_one_occurrence_across_weekly_periods_and_stopping_keeps_debt() {
    let mut state = state();
    bill(&mut state);
    let first = expenses::outstanding(&state, day("2024-10-10"), day("2024-10-17")).unwrap();
    periods::create(
        &mut state,
        day("2024-10-17"),
        day("2024-10-24"),
        Recurrence::Weekly,
        Calendar::Gregorian,
    )
    .unwrap();
    let second = expenses::outstanding(&state, day("2024-10-17"), day("2024-10-24")).unwrap();
    assert_eq!(
        first
            .iter()
            .filter(|item| item.date == day("2024-10-15"))
            .count(),
        1
    );
    assert_eq!(first[0].id, second[0].id);
    expenses::stop_essential(&mut state, "rent", day("2024-10-18")).unwrap();
    let pending = expenses::outstanding(&state, day("2024-11-01"), day("2024-11-08")).unwrap();
    assert_eq!(pending.len(), 1);
    assert_eq!(pending[0].date, day("2024-10-15"));
}
#[test]
fn report_preserves_historically_unpaid_bills_after_later_payment() {
    let mut state = state();
    bill(&mut state);
    receive(&mut state, "salary", "2024-10-10", 1000);
    let before = pouch_core::reports::build(&state, vec![day("2024-10-15")]).unwrap();
    let id = expenses::obligations(&state, day("2024-10-15")).unwrap()[0]
        .id
        .clone();
    expenses::mark_paid(
        &mut state,
        &id,
        "payment".into(),
        day("2024-10-20"),
        money(300),
    )
    .unwrap();
    let after = pouch_core::reports::build(&state, vec![day("2024-10-15")]).unwrap();
    assert_eq!(before.reserved, after.reserved);
    assert_eq!(before.total, after.total);
}
#[test]
fn adjusting_a_shared_boundary_keeps_ids_and_rebinds_allocations() {
    let mut state = state();
    receive(&mut state, "salary", "2024-10-10", 1000);
    budget::save_plan(
        &mut state,
        BudgetPlan {
            period_id: "BP-001".into(),
            effective: day("2024-10-10"),
            savings: money(200),
        },
    )
    .unwrap();
    savings::reconcile(&mut state, day("2024-10-10")).unwrap();
    periods::create(
        &mut state,
        day("2024-10-17"),
        day("2024-10-24"),
        Recurrence::Weekly,
        Calendar::Gregorian,
    )
    .unwrap();
    periods::edit(
        &mut state,
        "BP-001",
        day("2024-10-10"),
        day("2024-10-18"),
        Recurrence::Weekly,
        Calendar::Gregorian,
    )
    .unwrap();
    assert_eq!(state.periods[1].id, "BP-002");
    assert_eq!(state.periods[1].start, day("2024-10-18"));
    assert_eq!(
        budget::funding(&state, day("2024-10-18")).unwrap().savings,
        200
    );
    state.validate().unwrap();
}

#[test]
fn historical_income_and_plan_corrections_reconcile_savings_before_rollover() {
    let mut state = state();
    receive(&mut state, "salary", "2024-10-10", 1000);
    budget::save_plan(
        &mut state,
        BudgetPlan {
            period_id: "BP-001".into(),
            effective: day("2024-10-10"),
            savings: money(200),
        },
    )
    .unwrap();
    periods::create(
        &mut state,
        day("2024-10-17"),
        day("2024-10-24"),
        Recurrence::Weekly,
        Calendar::Gregorian,
    )
    .unwrap();
    budget::save_plan(
        &mut state,
        BudgetPlan {
            period_id: "BP-001".into(),
            effective: day("2024-10-10"),
            savings: money(300),
        },
    )
    .unwrap();
    assert_eq!(
        budget::funding(&state, day("2024-10-17")).unwrap().savings,
        300
    );
    income::edit(&mut state, "salary", day("2024-10-10"), money(250)).unwrap();
    let funds = budget::funding(&state, day("2024-10-17")).unwrap();
    assert_eq!(funds.savings, 250);
    assert_eq!(funds.free, 0);
    assert_eq!(funds.cash, funds.free + funds.reserved + funds.savings);
    income::remove(&mut state, "salary").unwrap();
    assert_eq!(
        budget::funding(&state, day("2024-10-17")).unwrap().savings,
        0
    );
    state.validate().unwrap();
}

#[test]
fn unfunded_obligations_are_distinct_from_protected_reservations() {
    let mut state = state();
    receive(&mut state, "salary", "2024-10-10", 100);
    bill(&mut state);
    let summary = budget::recommend(&state, day("2024-10-10")).unwrap();
    assert_eq!(summary.funded_expenses, 100);
    assert!(summary.reserved > summary.funded_expenses);
    assert_eq!(summary.recommendation, 0);
    assert!(summary.shortfall > 0);
}
#[test]
fn editing_a_goal_does_not_rewrite_prior_day_savings() {
    let mut state = state();
    receive(&mut state, "salary", "2024-10-10", 1000);
    expenses::save_planned(
        &mut state,
        expenses::create_planned(
            "goal".into(),
            "Goal".into(),
            money(800),
            Category::Other,
            PlannedKind::Goal,
            day("2024-11-30"),
        ),
    )
    .unwrap();
    savings::reconcile(&mut state, day("2024-10-10")).unwrap();
    let original = savings::balance(&state, day("2024-10-10")).unwrap();
    expenses::save_planned(
        &mut state,
        expenses::create_planned(
            "goal".into(),
            "Goal".into(),
            money(1600),
            Category::Other,
            PlannedKind::Goal,
            day("2024-11-30"),
        ),
    )
    .unwrap();
    savings::reconcile(&mut state, day("2024-10-11")).unwrap();
    assert_eq!(
        savings::balance(&state, day("2024-10-10")).unwrap(),
        original
    );
}

#[test]
fn deleting_savings_revisions_restores_previous_setting_and_releases_funds() {
    let mut state = state();
    receive(&mut state, "salary", "2024-10-10", 1000);
    for (effective, amount) in [("2024-10-10", 200), ("2024-10-11", 500)] {
        budget::save_plan(
            &mut state,
            BudgetPlan {
                period_id: "BP-001".into(),
                effective: day(effective),
                savings: money(amount),
            },
        )
        .unwrap();
    }
    savings::reconcile(&mut state, day("2024-10-12")).unwrap();
    let earlier = state.allocations[0].clone();
    let income = state.income.clone();
    assert_eq!(savings::balance(&state, day("2024-10-12")).unwrap(), 500);

    budget::remove_plan(&mut state, day("2024-10-11")).unwrap();
    assert_eq!(state.allocations[0], earlier);
    assert_eq!(
        budget::plan_at(&state, day("2024-10-12")).savings,
        money(200)
    );
    assert_eq!(savings::balance(&state, day("2024-10-12")).unwrap(), 200);
    assert_eq!(
        budget::funding(&state, day("2024-10-12")).unwrap().free,
        800
    );
    assert_eq!(state.income, income);

    budget::remove_plan(&mut state, day("2024-10-10")).unwrap();
    assert_eq!(savings::balance(&state, day("2024-10-12")).unwrap(), 0);
    assert_eq!(
        budget::funding(&state, day("2024-10-12")).unwrap().cash,
        1000
    );
    state.validate().unwrap();
}

#[test]
fn deleting_a_savings_revision_replays_later_revisions_and_preserves_purchases() {
    let mut state = state();
    receive(&mut state, "salary", "2024-10-10", 1000);
    for (effective, amount) in [("2024-10-10", 500), ("2024-10-12", 200)] {
        budget::save_plan(
            &mut state,
            BudgetPlan {
                period_id: "BP-001".into(),
                effective: day(effective),
                savings: money(amount),
            },
        )
        .unwrap();
    }
    pouch_core::purchases::add(
        &mut state,
        "lunch".into(),
        day("2024-10-11"),
        "Lunch".into(),
        money(100),
        Category::Food,
    )
    .unwrap();
    let purchases = state.days.clone();
    budget::remove_plan(&mut state, day("2024-10-10")).unwrap();
    assert_eq!(savings::balance(&state, day("2024-10-11")).unwrap(), 0);
    assert_eq!(savings::balance(&state, day("2024-10-12")).unwrap(), 200);
    assert_eq!(
        budget::funding(&state, day("2024-10-12")).unwrap().cash,
        900
    );
    assert_eq!(state.days, purchases);
    state.validate().unwrap();
}

#[test]
fn deleting_a_savings_revision_keeps_goal_funding() {
    let mut state = state();
    receive(&mut state, "salary", "2024-10-10", 1000);
    expenses::save_planned(
        &mut state,
        expenses::create_planned(
            "goal".into(),
            "Goal".into(),
            money(400),
            Category::Other,
            PlannedKind::Goal,
            day("2024-10-20"),
        ),
    )
    .unwrap();
    budget::save_plan(
        &mut state,
        BudgetPlan {
            period_id: "BP-001".into(),
            effective: day("2024-10-10"),
            savings: money(700),
        },
    )
    .unwrap();
    budget::remove_plan(&mut state, day("2024-10-10")).unwrap();
    assert_eq!(savings::balance(&state, day("2024-10-10")).unwrap(), 400);
    assert_eq!(state.planned.len(), 1);
    state.validate().unwrap();
}

#[test]
fn income_assignment_is_independent_of_date_without_duplicating_cash() {
    let mut state = state();
    let first = state.periods[0].id.clone();
    let second = periods::create(
        &mut state,
        day("2024-11-10"),
        day("2024-12-10"),
        Recurrence::Monthly,
        Calendar::Gregorian,
    )
    .unwrap();
    income::receive(
        &mut state,
        "assigned".into(),
        day("2024-10-12"),
        money(1200),
        Some(&second),
        None,
        false,
    )
    .unwrap();
    assert_eq!(state.income[0].date, day("2024-10-12"));
    assert_eq!(
        budget::income_for_period(&state, &first, day("2024-11-09")).unwrap(),
        0
    );
    assert_eq!(
        budget::income_for_period(&state, &second, day("2024-10-11")).unwrap(),
        0
    );
    assert_eq!(
        budget::income_for_period(&state, &second, day("2024-11-10")).unwrap(),
        1200
    );
    assert_eq!(budget::cash(&state, day("2024-10-11")).unwrap(), 0);
    assert_eq!(budget::cash(&state, day("2024-10-12")).unwrap(), 1200);
    assert_eq!(budget::cash(&state, day("2024-11-10")).unwrap(), 1200);
    state.validate().unwrap();
}

#[test]
fn assigned_future_expenses_and_goals_use_the_chosen_period() {
    let mut state = state();
    let first = state.periods[0].id.clone();
    let second = periods::create(
        &mut state,
        day("2024-11-10"),
        day("2024-12-10"),
        Recurrence::Monthly,
        Calendar::Gregorian,
    )
    .unwrap();
    receive(&mut state, "salary", "2024-10-10", 2000);
    for (id, kind, period_id) in [
        ("expense", PlannedKind::Expense, first.as_str()),
        ("goal", PlannedKind::Goal, second.as_str()),
    ] {
        expenses::save_planned(
            &mut state,
            expenses::create_planned(
                id.into(),
                id.into(),
                money(500),
                Category::Other,
                kind,
                day("2025-01-01"),
            ),
        )
        .unwrap();
        periods::context::assign_planned(&mut state, id, period_id).unwrap();
    }
    savings::reconcile(&mut state, day("2024-10-10")).unwrap();
    let funding = budget::funding(&state, day("2024-10-10")).unwrap();
    assert_eq!(funding.reserved, 500);
    assert_eq!(funding.savings, 0);
    assert_eq!(funding.free, 1500);
    assert_eq!(
        periods::context::planned_period(&state, &state.planned[1]),
        Some(second.as_str())
    );
    let names = state.period_context.names.clone();
    periods::edit(
        &mut state,
        &second,
        day("2024-11-11"),
        day("2024-12-11"),
        Recurrence::Monthly,
        Calendar::Gregorian,
    )
    .unwrap();
    assert_eq!(state.period_context.names, names);
    assert_eq!(
        names
            .values()
            .collect::<std::collections::BTreeSet<_>>()
            .len(),
        2
    );
    assert!(names.values().all(|name| name.starts_with("P-")));
    state.validate().unwrap();
}

#[test]
fn long_term_goal_contribution_is_not_repeated_on_later_days() {
    let mut state = state();
    receive(&mut state, "salary", "2024-10-10", 10_000);
    expenses::save_planned(
        &mut state,
        expenses::create_planned(
            "goal".into(),
            "Long term goal".into(),
            money(6200),
            Category::Other,
            PlannedKind::Goal,
            day("2024-12-10"),
        ),
    )
    .unwrap();
    for offset in 0..31 {
        let date = day("2024-10-10").add_days(offset).unwrap();
        savings::reconcile(&mut state, date).unwrap();
        assert_eq!(savings::balance(&state, date).unwrap(), 3100);
        let before = state.clone();
        savings::reconcile(&mut state, date).unwrap();
        assert_eq!(state, before);
    }
    assert_eq!(state.allocations.len(), 1);
    assert!(
        budget::recommend(&state, day("2024-10-21"))
            .unwrap()
            .recommendation
            > 0
    );
}

#[test]
fn minimum_savings_and_goal_share_one_period_contribution() {
    let mut state = state();
    receive(&mut state, "salary", "2024-10-10", 10_000);
    expenses::save_planned(
        &mut state,
        expenses::create_planned(
            "goal".into(),
            "Long term goal".into(),
            money(6200),
            Category::Other,
            PlannedKind::Goal,
            day("2024-12-10"),
        ),
    )
    .unwrap();
    savings::reconcile(&mut state, day("2024-10-10")).unwrap();
    budget::save_plan(
        &mut state,
        BudgetPlan {
            period_id: "BP-001".into(),
            effective: day("2024-10-12"),
            savings: money(4000),
        },
    )
    .unwrap();
    for offset in 3..10 {
        pouch_core::purchases::add(
            &mut state,
            format!("purchase-{offset}"),
            day("2024-10-10").add_days(offset).unwrap(),
            "Food".into(),
            money(50),
            Category::Food,
        )
        .unwrap();
    }
    let summary = budget::recommend(&state, day("2024-10-19")).unwrap();
    assert_eq!(summary.savings, 4000);
    assert_eq!(summary.remaining, 5650);
    assert_eq!(summary.recommendation, 209);
    assert_eq!(
        budget::recommend(&state, day("2024-10-20"))
            .unwrap()
            .recommendation,
        269
    );
}

#[test]
fn rollover_credits_opening_savings_before_funding_the_next_period() {
    let mut state = state();
    receive(&mut state, "salary", "2024-10-10", 10_000);
    expenses::save_planned(
        &mut state,
        expenses::create_planned(
            "goal".into(),
            "Long term goal".into(),
            money(6200),
            Category::Other,
            PlannedKind::Goal,
            day("2024-12-10"),
        ),
    )
    .unwrap();
    savings::reconcile(&mut state, day("2024-10-10")).unwrap();
    periods::create(
        &mut state,
        day("2024-11-10"),
        day("2024-12-11"),
        Recurrence::Monthly,
        Calendar::Gregorian,
    )
    .unwrap();
    for offset in 0..31 {
        let date = day("2024-11-10").add_days(offset).unwrap();
        savings::reconcile(&mut state, date).unwrap();
        assert_eq!(savings::balance(&state, date).unwrap(), 6200);
        assert_eq!(budget::funding(&state, date).unwrap().free, 3800);
    }
    assert_eq!(state.income.len(), 1);
}

#[test]
fn paying_a_goal_does_not_repeat_the_remaining_goals_contribution() {
    let mut state = state();
    receive(&mut state, "salary", "2024-10-10", 10_000);
    for (id, amount, due) in [("near", 1000, "2024-10-10"), ("later", 6200, "2024-12-10")] {
        expenses::save_planned(
            &mut state,
            expenses::create_planned(
                id.into(),
                id.into(),
                money(amount),
                Category::Other,
                PlannedKind::Goal,
                day(due),
            ),
        )
        .unwrap();
    }
    savings::reconcile(&mut state, day("2024-10-10")).unwrap();
    expenses::mark_paid(
        &mut state,
        "near",
        "payment".into(),
        day("2024-10-11"),
        money(1000),
    )
    .unwrap();
    for offset in 1..10 {
        let date = day("2024-10-10").add_days(offset).unwrap();
        savings::reconcile(&mut state, date).unwrap();
        let funding = budget::funding(&state, date).unwrap();
        assert_eq!(funding.savings, 3100);
        assert_eq!(funding.free, 5900);
        assert_eq!(
            funding.cash,
            funding.free + funding.reserved + funding.savings
        );
    }
}

#[test]
fn goal_reservation_recovers_after_cash_shortage_without_accumulating_again() {
    let mut state = state();
    receive(&mut state, "salary", "2024-10-10", 1000);
    expenses::save_planned(
        &mut state,
        expenses::create_planned(
            "goal".into(),
            "Goal".into(),
            money(6200),
            Category::Other,
            PlannedKind::Goal,
            day("2024-12-10"),
        ),
    )
    .unwrap();
    savings::reconcile(&mut state, day("2024-10-10")).unwrap();
    assert_eq!(savings::balance(&state, day("2024-10-10")).unwrap(), 1000);
    receive(&mut state, "extra", "2024-10-11", 9000);
    for offset in 1..10 {
        let date = day("2024-10-10").add_days(offset).unwrap();
        savings::reconcile(&mut state, date).unwrap();
        assert_eq!(savings::balance(&state, date).unwrap(), 3100);
    }
}

#[test]
fn backdated_income_correction_replays_later_savings_instead_of_duplicating_them() {
    let mut state = state();
    receive(&mut state, "salary", "2024-10-10", 1000);
    budget::save_plan(
        &mut state,
        BudgetPlan {
            period_id: "BP-001".into(),
            effective: day("2024-10-10"),
            savings: money(4000),
        },
    )
    .unwrap();
    receive(&mut state, "later", "2024-10-12", 9000);
    assert_eq!(savings::balance(&state, day("2024-10-12")).unwrap(), 4000);
    income::edit(&mut state, "salary", day("2024-10-10"), money(5000)).unwrap();
    assert_eq!(savings::balance(&state, day("2024-10-10")).unwrap(), 4000);
    assert_eq!(savings::balance(&state, day("2024-10-12")).unwrap(), 4000);
    assert_eq!(
        budget::funding(&state, day("2024-10-12")).unwrap().free,
        10_000
    );
}
