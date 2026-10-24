use pouch_core::{
    AppState, Date, Money, budget, calendar, dashboard,
    dashboard::range::{DashboardQuery, resolve},
    expenses, income,
    models::{
        BudgetPlan, Calendar, Category, ExpectedIncomeEntry, IncomeEntry, PlannedKind, Recurrence,
        RequiredExpense, WeekStart,
    },
    periods, purchases, savings,
};

fn date(value: &str) -> Date {
    Date::parse_iso(value).unwrap()
}
fn money(value: i64) -> Money {
    Money::from_hundredths(value).unwrap()
}
fn query(from: &str, through: &str) -> DashboardQuery {
    DashboardQuery {
        mode: "custom".into(),
        anchor: date(from),
        from: Some(date(from)),
        through: Some(date(through)),
        period_id: None,
    }
}
fn records() -> AppState {
    let mut state = AppState::fresh(date("2024-01-01"));
    state.preferences.calendar = Calendar::Gregorian;
    periods::create(
        &mut state,
        date("2024-01-01"),
        date("2024-02-01"),
        Recurrence::Monthly,
        Calendar::Gregorian,
    )
    .unwrap();
    periods::create(
        &mut state,
        date("2024-02-01"),
        date("2024-03-01"),
        Recurrence::Monthly,
        Calendar::Gregorian,
    )
    .unwrap();
    state
}
fn receive(state: &mut AppState, id: &str, day: &str, amount: i64) {
    income::record(state, id.into(), date(day), money(amount)).unwrap();
}
fn buy(state: &mut AppState, id: &str, day: &str, amount: i64) {
    purchases::add(
        state,
        id.into(),
        date(day),
        id.into(),
        money(amount),
        Category::Food,
    )
    .unwrap();
}
fn view(state: &AppState, from: &str, through: &str) -> dashboard::DashboardSnapshot {
    dashboard::snapshot(state, &query(from, through), date("2024-03-31")).unwrap()
}

#[test]
fn actual_cash_flow_reconciles_with_reports_and_excludes_expectations_and_rollover() {
    let mut state = records();
    receive(&mut state, "salary", "2024-01-01", 100_000);
    buy(&mut state, "food", "2024-02-02", 12_345);
    state.expected_income.push(ExpectedIncomeEntry {
        id: "expected".into(),
        date: date("2024-02-03"),
        amount: money(900_000),
    });
    let result = view(&state, "2024-02-01", "2024-02-29");
    assert_eq!(
        (result.income, result.expenses, result.net),
        (0, 12_345, -12_345)
    );
    assert_eq!(result.cash, 87_655);
    let report = pouch_core::reports::build(
        &state,
        pouch_core::reports::dates(pouch_core::reports::ReportPeriod::Range {
            from: date("2024-02-01"),
            through: date("2024-02-29"),
        })
        .unwrap(),
    )
    .unwrap();
    assert_eq!(result.expenses, report.total);
    assert_eq!(
        result
            .categories
            .iter()
            .map(|item| item.amount)
            .sum::<i64>(),
        report.total
    );
    assert_eq!(
        result
            .points
            .iter()
            .map(|point| point.expenses)
            .sum::<i64>(),
        report.total
    );
}

#[test]
fn period_assignments_do_not_change_dated_cash_flow() {
    let mut state = records();
    receive(&mut state, "salary", "2024-01-15", 10_000);
    periods::context::assign_income(&mut state, "salary", "BP-002").unwrap();
    let mut selection = query("2024-02-01", "2024-02-29");
    selection.mode = "period".into();
    selection.period_id = Some("BP-002".into());
    let before = state.clone();
    let result = dashboard::snapshot(&state, &selection, date("2024-03-01")).unwrap();
    assert_eq!(result.assigned_income, Some(10_000));
    assert_eq!(result.income, 0);
    assert_eq!(result.cash, 10_000);
    assert_eq!(state, before);
    assert_eq!(
        (result.from.as_str(), result.through.as_str()),
        ("2024-02-01", "2024-02-29")
    );
}

#[test]
fn allocations_and_goal_payments_are_counted_once() {
    let mut state = records();
    receive(&mut state, "salary", "2024-01-01", 100_000);
    budget::save_plan(
        &mut state,
        BudgetPlan {
            period_id: "BP-001".into(),
            effective: date("2024-01-01"),
            savings: money(20_000),
        },
    )
    .unwrap();
    let goal = expenses::create_planned(
        "goal".into(),
        "Bike".into(),
        money(10_000),
        Category::Other,
        PlannedKind::Goal,
        date("2024-01-10"),
    );
    expenses::save_planned(&mut state, goal).unwrap();
    savings::reconcile(&mut state, date("2024-01-01")).unwrap();
    expenses::mark_paid(
        &mut state,
        "goal",
        "bike".into(),
        date("2024-01-10"),
        money(10_000),
    )
    .unwrap();
    let result = view(&state, "2024-01-01", "2024-01-31");
    assert_eq!(result.expenses, 10_000);
    assert_eq!(result.income, 100_000);
    assert_eq!(result.cash, 90_000);
    assert_eq!(
        result.points.last().unwrap().savings,
        savings::recorded_balance(&state, date("2024-01-31")).unwrap()
    );
    assert_eq!(
        result
            .allocation
            .iter()
            .map(|slice| slice.amount)
            .sum::<i64>(),
        result.cash
    );
}

#[test]
fn pending_expenses_reserve_cash_without_becoming_payments() {
    let mut state = records();
    receive(&mut state, "salary", "2024-01-01", 10_000);
    expenses::save_planned(
        &mut state,
        expenses::create_planned(
            "bill".into(),
            "Bill".into(),
            money(3_000),
            Category::Bills,
            PlannedKind::Expense,
            date("2024-01-10"),
        ),
    )
    .unwrap();
    let result = view(&state, "2024-01-01", "2024-01-31");
    assert_eq!(result.expenses, 0);
    assert_eq!(result.reserved, 3_000);
    assert_eq!(result.free, 7_000);
    assert_eq!(result.comparisons[0].planned, 3_000);
    assert_eq!(result.comparisons[0].paid, 0);
}

#[test]
fn essential_classification_uses_payment_links_not_category_guesses() {
    let mut state = records();
    receive(&mut state, "salary", "2024-01-01", 10_000);
    expenses::save_essential(
        &mut state,
        RequiredExpense {
            id: "rent".into(),
            name: "Rent".into(),
            amount: money(2_000),
            date: date("2024-01-05"),
            recurrence: Recurrence::Once,
            calendar: Calendar::Gregorian,
            until: None,
        },
    )
    .unwrap();
    let bill = expenses::obligations(&state, date("2024-01-31"))
        .unwrap()
        .remove(0);
    expenses::mark_paid(
        &mut state,
        &bill.id,
        "rent-payment".into(),
        date("2024-01-06"),
        money(1_900),
    )
    .unwrap();
    purchases::add(
        &mut state,
        "unlinked".into(),
        date("2024-01-06"),
        "Unlinked bill".into(),
        money(500),
        Category::Bills,
    )
    .unwrap();
    let result = view(&state, "2024-01-01", "2024-01-31");
    assert_eq!(result.spending[0].amount, 1_900);
    assert_eq!(result.spending[1].amount, 500);
    let progress = result
        .progress
        .iter()
        .find(|item| item.key == "dashboardEssentialPayments")
        .unwrap();
    assert_eq!(
        (progress.amount, progress.target, progress.basis_points),
        (1_900, 2_000, 9_500)
    );
}

#[test]
fn historical_corrections_refresh_totals_balances_and_allocations() {
    let mut state = records();
    receive(&mut state, "salary", "2024-01-01", 100_000);
    budget::save_plan(
        &mut state,
        BudgetPlan {
            period_id: "BP-001".into(),
            effective: date("2024-01-01"),
            savings: money(60_000),
        },
    )
    .unwrap();
    savings::reconcile(&mut state, date("2024-01-01")).unwrap();
    let before = view(&state, "2024-01-01", "2024-02-29");
    buy(&mut state, "correction", "2024-01-02", 70_000);
    savings::reconcile(&mut state, date("2024-01-02")).unwrap();
    let after = view(&state, "2024-01-01", "2024-02-29");
    assert_eq!(after.expenses - before.expenses, 70_000);
    assert_eq!(before.cash - after.cash, 70_000);
    assert!(after.releases > 0);
    assert_eq!(
        after.points.last().unwrap().savings,
        savings::recorded_balance(&state, date("2024-02-29")).unwrap()
    );
    assert_eq!(
        after.free,
        budget::recommend(&state, date("2024-02-29"))
            .unwrap()
            .remaining
    );
}

#[test]
fn savings_goals_share_the_existing_funded_pool() {
    let mut state = records();
    receive(&mut state, "salary", "2024-01-01", 15_000);
    for id in ["a", "b"] {
        expenses::save_planned(
            &mut state,
            expenses::create_planned(
                id.into(),
                id.into(),
                money(10_000),
                Category::Other,
                PlannedKind::Goal,
                date("2024-01-15"),
            ),
        )
        .unwrap();
    }
    savings::reconcile(&mut state, date("2024-01-01")).unwrap();
    let result = view(&state, "2024-01-01", "2024-01-10");
    assert_eq!(result.goals.len(), 2);
    assert!(result.goals.iter().map(|goal| goal.amount).sum::<i64>() <= result.protected_savings);
    for goal in &result.goals {
        let expected =
            pouch_core::forecast::preview(&state, date("2024-01-10"), &goal.key, false, false)
                .unwrap();
        assert_eq!(goal.amount, expected.allocated);
    }
}

#[test]
fn empty_future_and_negative_balances_have_honest_results() {
    let mut state = records();
    let empty = view(&state, "2024-01-01", "2024-01-31");
    assert!(!empty.has_activity);
    assert!(empty.categories.is_empty());
    assert!(empty.progress.iter().all(|value| value.basis_points == 0));
    let future = dashboard::snapshot(
        &state,
        &query("2024-02-01", "2024-02-29"),
        date("2024-01-15"),
    )
    .unwrap();
    assert!(future.future_only);
    assert!(future.points.is_empty());
    buy(&mut state, "unfunded", "2024-01-05", 500);
    let deficit = view(&state, "2024-01-01", "2024-01-31");
    assert_eq!(deficit.free, -500);
    assert!(deficit.allocation.iter().all(|slice| slice.amount == 0));
}

#[test]
fn inclusive_boundaries_and_today_cutoff_never_create_future_actuals() {
    let mut state = records();
    receive(&mut state, "start", "2024-01-02", 100);
    receive(&mut state, "end", "2024-01-03", 200);
    receive(&mut state, "later", "2024-01-04", 400);
    let result = dashboard::snapshot(
        &state,
        &query("2024-01-02", "2024-01-31"),
        date("2024-01-03"),
    )
    .unwrap();
    assert_eq!(result.income, 300);
    assert_eq!(result.points.len(), 2);
    assert_eq!(result.points.last().unwrap().through, "2024-01-03");
}

#[test]
fn calendar_filters_follow_week_starts_leap_years_and_nowruz() {
    let mut state = records();
    let mut selection = query("2024-03-20", "2024-03-20");
    selection.mode = "daily".into();
    let daily = resolve(&state, &selection, date("2024-12-31")).unwrap();
    assert_eq!(daily.from, daily.through);
    selection.mode = "weekly".into();
    for (start, expected) in [
        (WeekStart::Saturday, "2024-03-16"),
        (WeekStart::Sunday, "2024-03-17"),
        (WeekStart::Monday, "2024-03-18"),
    ] {
        state.preferences.week_start = start;
        let range = resolve(&state, &selection, date("2024-12-31")).unwrap();
        assert_eq!(range.from, date(expected));
        assert_eq!(range.from.days_until(range.through), 6);
    }
    selection.mode = "monthly".into();
    selection.anchor = date("2024-02-15");
    assert_eq!(
        resolve(&state, &selection, date("2024-12-31"))
            .unwrap()
            .through,
        date("2024-02-29")
    );
    selection.mode = "yearly".into();
    let year = resolve(&state, &selection, date("2024-12-31")).unwrap();
    assert_eq!(year.from.days_until(year.through), 365);
    state.preferences.calendar = Calendar::Jalali;
    selection.anchor = date("2024-03-20");
    let jalali = resolve(&state, &selection, date("2025-12-31")).unwrap();
    assert_eq!(jalali.from, date("2024-03-20"));
    assert_eq!(
        calendar::parts(jalali.through, Calendar::Jalali)
            .unwrap()
            .year,
        1403
    );
    selection.mode = "monthly".into();
    assert_eq!(
        resolve(&state, &selection, date("2025-12-31"))
            .unwrap()
            .through,
        date("2024-04-19")
    );
}

#[test]
fn invalid_and_oversized_ranges_are_rejected() {
    let state = records();
    for selection in [
        query("2024-02-01", "2024-01-01"),
        query("2000-01-01", "2024-01-01"),
    ] {
        assert!(dashboard::snapshot(&state, &selection, date("2024-03-31")).is_err());
    }
    let mut selection = query("2024-01-01", "2024-01-31");
    selection.mode = "period".into();
    selection.period_id = Some("missing".into());
    assert!(dashboard::snapshot(&state, &selection, date("2024-03-31")).is_err());
}

#[test]
fn long_histories_have_bounded_series_with_exact_totals() {
    let mut state = AppState::fresh(date("2016-01-01"));
    state.preferences.calendar = Calendar::Gregorian;
    for index in 0..40_000 {
        state.income.push(IncomeEntry {
            id: format!("income-{index}"),
            date: date("2020-02-02"),
            amount: money(123),
        });
    }
    let result = dashboard::snapshot(
        &state,
        &query("2016-01-01", "2024-12-31"),
        date("2024-12-31"),
    )
    .unwrap();
    assert!(result.points.len() <= 120);
    assert_eq!(result.income, 4_920_000);
    assert_eq!(
        result.points.iter().map(|point| point.income).sum::<i64>(),
        result.income
    );
    assert_eq!(result.points.last().unwrap().cash, result.cash);
}

#[test]
fn json_api_is_read_only_and_rejects_malformed_requests() {
    let directory = tempfile::tempdir().unwrap();
    let state = records();
    pouch_core::storage::BinaryStore::new(directory.path())
        .save(&state)
        .unwrap();
    let app =
        pouch_core::api::PouchApp::open(directory.path().to_string_lossy().into(), vec![]).unwrap();
    let before = app.export_backup().unwrap();
    let revision = app.snapshot().unwrap().revision;
    let result = app
        .dashboard(r#"{"mode":"monthly","anchor":"2024-01-15"}"#.into())
        .unwrap();
    let result: serde_json::Value = serde_json::from_str(&result).unwrap();
    assert_eq!(result["from"], "2024-01-01");
    assert_eq!(result["income"], 0);
    assert!(app.dashboard("{}".into()).is_err());
    assert_eq!(app.export_backup().unwrap(), before);
    assert_eq!(app.snapshot().unwrap().revision, revision);
}

#[test]
fn dashboard_uses_the_rust_active_period_without_changing_other_views() {
    let today = Date::from_naive_date(chrono::Local::now().date_naive()).unwrap();
    let mut state = AppState::fresh(today.add_days(-14).unwrap());
    state.preferences.calendar = Calendar::Gregorian;
    for (from, through) in [(-14, 0), (0, 14), (14, 28)] {
        periods::create(
            &mut state,
            today.add_days(from).unwrap(),
            today.add_days(through).unwrap(),
            Recurrence::Biweekly,
            Calendar::Gregorian,
        )
        .unwrap();
    }
    let today_iso = today.iso().unwrap();
    receive(&mut state, "salary", &today_iso, 10_000);
    buy(&mut state, "food", &today_iso, 2_000);
    let directory = tempfile::tempdir().unwrap();
    pouch_core::storage::BinaryStore::new(directory.path())
        .save(&state)
        .unwrap();
    let app =
        pouch_core::api::PouchApp::open(directory.path().to_string_lossy().into(), vec![]).unwrap();
    let before = app.snapshot().unwrap();
    let active = before.current_period.as_ref().unwrap();
    assert_eq!(active.id, periods::at(&state, today).unwrap().id);
    assert_eq!(active.id, "BP-002");
    assert_eq!(active.status, "active");
    assert_eq!(before.periods.last().unwrap().id, "BP-003");
    let backup = app.export_backup().unwrap();
    let today_before = app.budget_summary(today_iso.clone(), None).unwrap();
    let budget_before = app
        .budget_summary(today_iso.clone(), Some("BP-001".into()))
        .unwrap();
    let selection = serde_json::json!({
        "mode": "period",
        "anchor": today_iso,
        "periodId": active.id,
    });
    let result: serde_json::Value =
        serde_json::from_str(&app.dashboard(selection.to_string()).unwrap()).unwrap();
    assert_eq!(result["periodId"], active.id);
    assert_eq!(result["from"], today.iso().unwrap());
    assert_eq!(
        result["through"],
        today.add_days(13).unwrap().iso().unwrap()
    );
    assert_eq!(result["income"], 10_000);
    assert_eq!(result["expenses"], 2_000);
    for id in ["BP-001", "BP-003"] {
        let selection = serde_json::json!({
            "mode": "period",
            "anchor": today_iso,
            "periodId": id,
        });
        app.dashboard(selection.to_string()).unwrap();
    }
    let selection = serde_json::json!({"mode": "monthly", "anchor": today_iso});
    app.dashboard(selection.to_string()).unwrap();
    let after = app.snapshot().unwrap();
    assert_eq!(after.current_period.unwrap().id, active.id);
    assert_eq!(after.revision, before.revision);
    assert_eq!(app.export_backup().unwrap(), backup);
    assert_eq!(app.today().unwrap(), today_iso);
    let today_after = app.budget_summary(today_iso.clone(), None).unwrap();
    let budget_after = app
        .budget_summary(today_iso, Some("BP-001".into()))
        .unwrap();
    for (before, after) in [(today_before, today_after), (budget_before, budget_after)] {
        assert_eq!(
            (
                before.income,
                before.spent,
                before.funds,
                before.remaining,
                before.savings,
                before.reserved,
            ),
            (
                after.income,
                after.spent,
                after.funds,
                after.remaining,
                after.savings,
                after.reserved,
            )
        );
    }
}

#[test]
fn missing_active_period_stays_missing_while_a_monthly_dashboard_is_available() {
    let today = Date::from_naive_date(chrono::Local::now().date_naive()).unwrap();
    for bounds in [None, Some((-14, 0)), Some((7, 14))] {
        let mut state = AppState::fresh(today.add_days(-14).unwrap());
        state.preferences.calendar = Calendar::Gregorian;
        if let Some((from, through)) = bounds {
            periods::create(
                &mut state,
                today.add_days(from).unwrap(),
                today.add_days(through).unwrap(),
                Recurrence::Biweekly,
                Calendar::Gregorian,
            )
            .unwrap();
        }
        let directory = tempfile::tempdir().unwrap();
        pouch_core::storage::BinaryStore::new(directory.path())
            .save(&state)
            .unwrap();
        let app =
            pouch_core::api::PouchApp::open(directory.path().to_string_lossy().into(), vec![])
                .unwrap();
        assert!(app.snapshot().unwrap().current_period.is_none());
        let backup = app.export_backup().unwrap();
        let selection = serde_json::json!({
            "mode": "monthly",
            "anchor": today.iso().unwrap(),
        });
        let result: serde_json::Value =
            serde_json::from_str(&app.dashboard(selection.to_string()).unwrap()).unwrap();
        assert!(result["periodId"].is_null());
        assert_eq!(
            result["from"],
            calendar::month_start(today, Calendar::Gregorian)
                .unwrap()
                .iso()
                .unwrap()
        );
        let after = app.snapshot().unwrap();
        assert!(after.current_period.is_none());
        assert_eq!(after.periods.len(), state.periods.len());
        assert_eq!(app.export_backup().unwrap(), backup);
    }
}
