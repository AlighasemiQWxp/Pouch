use pouch_core::api::{PouchApp, ReceiveIncomeRequest};

#[test]
fn explicit_assignments_income_labels_and_savings_purchases_survive_roundtrip() {
    let folder = tempfile::tempdir().unwrap();
    let mut app = PouchApp::open(folder.path().to_str().unwrap().to_owned(), vec![]).unwrap();
    let today = chrono::Local::now().date_naive();
    let date = today.format("%Y-%m-%d").to_string();
    let through = (today + chrono::Days::new(30))
        .format("%Y-%m-%d")
        .to_string();
    let initial = app
        .receive_income(ReceiveIncomeRequest {
            id: "gift".into(),
            date: date.clone(),
            amount: "1000".into(),
            period_id: None,
            start_new: true,
            kind: "once".into(),
            custom_days: 7,
            through: Some(through.clone()),
            expected: false,
            label: Some("Birthday".into()),
        })
        .unwrap();
    assert_eq!(initial.income[0].label.as_deref(), Some("Birthday"));
    let period = initial.periods[0].id.clone();
    app.save_budget_plan(period.clone(), date.clone(), "500".into())
        .unwrap();
    let saved = app
        .save_planned(
            "car".into(),
            "Car".into(),
            "1000".into(),
            "other".into(),
            "goal".into(),
            through.clone(),
            Some(period.clone()),
            Some("200".into()),
        )
        .unwrap();
    assert_eq!(saved.planned[0].allocated, 20_000);
    let free_before = app.budget_summary(date.clone(), None).unwrap().remaining;
    app.save_planned(
        "car".into(),
        "Car".into(),
        "1500".into(),
        "other".into(),
        "goal".into(),
        through.clone(),
        Some(period.clone()),
        Some("200".into()),
    )
    .unwrap();
    assert_eq!(
        app.budget_summary(date.clone(), None).unwrap().remaining,
        free_before
    );
    assert!(
        app.save_planned(
            "house".into(),
            "House".into(),
            "1000".into(),
            "other".into(),
            "goal".into(),
            through,
            Some(period),
            Some("400".into())
        )
        .is_err()
    );
    assert_eq!(
        app.budget_summary(date.clone(), None).unwrap().savings,
        50_000
    );
    app.add_purchase(
        "lunch".into(),
        date.clone(),
        "Lunch".into(),
        "100".into(),
        "food".into(),
        true,
    )
    .unwrap();
    let summary = app.budget_summary(date.clone(), None).unwrap();
    assert_eq!(summary.savings, 40_000);
    assert_eq!(summary.funds + summary.savings, 90_000);
    app.edit_purchase(
        date.clone(),
        "lunch".into(),
        "Lunch".into(),
        "150".into(),
        "food".into(),
        true,
    )
    .unwrap();
    assert_eq!(
        app.budget_summary(date.clone(), None).unwrap().savings,
        35_000
    );
    app.edit_purchase(
        date.clone(),
        "lunch".into(),
        "Lunch".into(),
        "100".into(),
        "food".into(),
        true,
    )
    .unwrap();
    assert_eq!(
        app.budget_summary(date.clone(), None).unwrap().savings,
        40_000
    );
    assert!(
        app.add_purchase(
            "too-much".into(),
            date.clone(),
            "Too much".into(),
            "250".into(),
            "food".into(),
            true
        )
        .is_err()
    );
    app.remove_purchase(date.clone(), "lunch".into()).unwrap();
    assert_eq!(
        app.budget_summary(date.clone(), None).unwrap().savings,
        50_000
    );
    app.undo_last_change().unwrap();
    assert_eq!(
        app.budget_summary(date.clone(), None).unwrap().savings,
        40_000
    );
    let exported = app.export_backup().unwrap();
    drop(app);
    let mut reopened = PouchApp::open(folder.path().to_str().unwrap().to_owned(), vec![]).unwrap();
    assert_eq!(
        reopened.snapshot().unwrap().income[0].label.as_deref(),
        Some("Birthday")
    );
    assert_eq!(reopened.snapshot().unwrap().planned[0].allocated, 20_000);
    reopened.import_backup(exported).unwrap();
    assert_eq!(reopened.budget_summary(date, None).unwrap().savings, 40_000);
}
