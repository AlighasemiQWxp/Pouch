use super::*;
use crate::models::{
    Calendar, Category, Currency, IncomeEntry, PlannedItem, PlannedKind, PlannedStatus,
};

fn date(value: &str) -> Date {
    Date::parse_iso(value).expect("valid date")
}
fn amount(value: i64) -> Money {
    Money::from_hundredths(value).expect("valid amount")
}

#[test]
fn every_country_has_automatic_forecasts_with_deadline_requirements() {
    for country in &COUNTRIES {
        assert!(country.automatic);
        let directory = tempfile::tempdir().expect("directory");
        let store = EconomicStore::new(directory.path());
        let profile = if country.code == "CA" {
            profile()
        } else {
            let income_unit = if country.code == "IR" {
                "TOMAN/household/year".into()
            } else {
                format!("{}/year", country.currency)
            };
            let spending_unit = if country.code == "IR" {
                "TOMAN/household/year".into()
            } else {
                format!("{}/person/year", country.currency)
            };
            let period = if country.code == "IR" { "1404" } else { "2025" };
            Profile {
                version: METHOD_VERSION,
                country: country.code.into(),
                downloaded: "2026-10-04".into(),
                observations: vec![
                    Observation {
                        indicator: "annual_net".into(),
                        value: 60_000.0,
                        unit: income_unit,
                        period: period.into(),
                        released: "fixture".into(),
                    },
                    Observation {
                        indicator: "annual_spending".into(),
                        value: 36_000.0,
                        unit: spending_unit,
                        period: period.into(),
                        released: "fixture".into(),
                    },
                    Observation {
                        indicator: "cad_per_local".into(),
                        value: 2.0,
                        unit: "CAD/local unit".into(),
                        period: "2026-10-04".into(),
                        released: "fixture".into(),
                    },
                ],
            }
        };
        store
            .save(Download {
                profile,
                exchange: Some(ExchangeRate {
                    currency: "CAD".into(),
                    cad_per_unit: 1.0,
                    date: "2026-10-04".into(),
                    downloaded: "2026-10-04".into(),
                }),
            })
            .expect("valid profile");
        let state = state();
        let before = state.clone();
        let result = forecast(
            &state,
            &store.read(),
            state.start_date,
            "target",
            country.code,
            "CAD",
        )
        .expect("forecast");
        let rate = if country.code == "CA" { 1 } else { 2 };
        let converted = 100_000 / rate;
        assert_eq!(result.converted_goal, Some(converted));
        assert_eq!(result.converted_remaining, Some(converted));
        let required = (i128::from(converted) * DAYS_PER_MONTH + 60 * 1200 - 1) / (60 * 1200);
        assert_eq!(result.required_monthly_saving, Some(required as i64));
        let living = i128::from(result.monthly_essential.expect("living costs"))
            + (i128::from(result.daily_spending.expect("daily costs")) * DAYS_PER_MONTH + 1199)
                / 1200;
        assert_eq!(
            result.required_monthly_income,
            Some((living + required) as i64)
        );
        let days = result.completion_days.expect("positive saving capacity");
        assert_eq!(
            result.completion_date,
            Some(
                state
                    .start_date
                    .add_days(days)
                    .expect("date")
                    .iso()
                    .expect("ISO")
            )
        );
        assert_eq!(state, before);
        if country.code != "CA" {
            let mut refreshed = store
                .read()
                .profile(country.code)
                .expect("cached profile")
                .clone();
            refreshed
                .observations
                .retain(|entry| entry.indicator != "cad_per_local");
            store
                .save(Download {
                    profile: refreshed,
                    exchange: None,
                })
                .expect("economic refresh without FX");
            let after = forecast(
                &state,
                &store.read(),
                state.start_date,
                "target",
                country.code,
                "CAD",
            )
            .expect("cached conversion survives");
            assert_eq!(after.converted_goal, result.converted_goal);
        }
    }
}

#[test]
fn international_profile_rejects_duplicate_indicators_and_wrong_units() {
    let mut value = Profile {
        version: METHOD_VERSION,
        country: "IR".into(),
        downloaded: "2026-10-04".into(),
        observations: vec![
            Observation {
                indicator: "annual_net".into(),
                value: 484_610_500.0,
                unit: "TOMAN/household/year".into(),
                period: "1404".into(),
                released: "SCI".into(),
            },
            Observation {
                indicator: "annual_spending".into(),
                value: 391_942_700.0,
                unit: "TOMAN/household/year".into(),
                period: "1404".into(),
                released: "SCI".into(),
            },
            Observation {
                indicator: "cad_per_local".into(),
                value: 0.00001,
                unit: "CAD/local unit".into(),
                period: "2026-10-04".into(),
                released: "market".into(),
            },
        ],
    };
    value.validate().expect("valid profile");
    value.observations[0].unit = "IRR/household/year".into();
    assert!(value.validate().is_err());
    value.observations[0].unit = "TOMAN/household/year".into();
    value.observations[1].indicator = "annual_net".into();
    assert!(value.validate().is_err());
}

fn state() -> AppState {
    let mut state = AppState::fresh(date("2024-01-01"));
    state.preferences.currency = Currency::Cad;
    state.preferences.calendar = Calendar::Gregorian;
    state.planned.push(PlannedItem {
        id: "target".into(),
        description: "Target".into(),
        amount: amount(100_000),
        category: Category::Other,
        kind: PlannedKind::Goal,
        date: date("2024-03-01"),
        status: PlannedStatus::Pending,
        paid_date: None,
        purchase_id: None,
    });
    state
}

fn profile() -> Profile {
    let values = [
        92400.82826182,
        68738.15807219,
        44074.0,
        16228.0,
        4595.0,
        3673.0,
        157.1,
        164.2,
    ];
    Profile {
        version: METHOD_VERSION,
        country: "CA".into(),
        downloaded: "2026-10-04".into(),
        observations: canada::INDICATORS
            .into_iter()
            .zip(values)
            .map(|((indicator, unit, period), value)| Observation {
                indicator: indicator.into(),
                value,
                unit: unit.into(),
                period: period.into(),
                released: "2026".into(),
            })
            .collect(),
    }
}

fn save(store: &EconomicStore) {
    store
        .save(Download {
            profile: profile(),
            exchange: None,
        })
        .expect("valid cache");
}

#[test]
fn canada_uses_remaining_allocation_and_leaves_financial_state_unchanged() {
    let directory = tempfile::tempdir().expect("directory");
    let store = EconomicStore::new(directory.path());
    save(&store);
    let mut state = state();
    state.plans[0].monthly_savings = amount(30_000);
    state.income.push(IncomeEntry {
        id: "income".into(),
        date: state.start_date,
        amount: amount(30_000),
    });
    let today = date("2024-01-01");
    let personal =
        crate::forecast::forecast(&state, today, "target", None).expect("personal forecast");
    assert!(personal.allocated > 0);
    let before = state.clone();
    let result =
        forecast(&state, &store.read(), today, "target", "CA", "CAD").expect("standard forecast");
    assert_eq!(result.remaining, personal.remaining);
    assert_eq!(result.converted_remaining, Some(personal.remaining));
    assert_eq!(result.monthly_net_income, Some(572_818));
    assert_eq!(result.status, "ready");
    let days = result.completion_days.expect("completion days");
    assert_eq!(
        result.completion_date,
        Some(today.add_days(days).expect("date").iso().expect("ISO"))
    );
    let capacity = i128::from(result.monthly_saving.expect("saving capacity"));
    assert!(capacity * i128::from(days) * 1200 >= i128::from(personal.remaining) * DAYS_PER_MONTH);
    if days > 0 {
        assert!(
            capacity * i128::from(days - 1) * 1200
                < i128::from(personal.remaining) * DAYS_PER_MONTH
        );
    }
    assert_eq!(state, before);
}

#[test]
fn missing_country_cache_does_not_invent_completion() {
    let directory = tempfile::tempdir().expect("directory");
    let store = EconomicStore::new(directory.path());
    let state = state();
    for country in COUNTRIES.iter().map(|profile| profile.code) {
        let result = forecast(
            &state,
            &store.read(),
            state.start_date,
            "target",
            country,
            "CAD",
        )
        .expect("forecast");
        assert_eq!(result.status, "initial_connection");
        assert_eq!(result.completion_days, None);
        assert_eq!(result.monthly_net_income, None);
    }
    save(&store);
    let result = forecast(
        &state,
        &store.read(),
        state.start_date,
        "target",
        "CA",
        "TOMAN",
    )
    .expect("forecast");
    assert_eq!(result.status, "conversion_required");
    assert_eq!(result.completion_days, None);
}

#[test]
fn offline_cache_recovers_and_invalid_refresh_preserves_last_valid_data() {
    let directory = tempfile::tempdir().expect("directory");
    let store = EconomicStore::new(directory.path());
    save(&store);
    let mut invalid = profile();
    invalid.observations[0].period = "2026".into();
    assert!(
        store
            .save(Download {
                profile: invalid,
                exchange: None
            })
            .is_err()
    );
    assert!(store.read().profile("CA").is_some());
    save(&store);
    std::fs::write(
        directory.path().join("economic-profiles-v1.json"),
        b"damaged",
    )
    .expect("write");
    let cached = store.read();
    assert!(cached.warning());
    assert!(cached.profile("CA").is_some());
    std::fs::remove_file(directory.path().join("economic-profiles-v1.json")).expect("remove");
    assert!(store.read().profile("CA").is_some());
}

#[test]
fn refresh_keeps_custom_assumptions_and_zero_capacity_has_no_completion() {
    let directory = tempfile::tempdir().expect("directory");
    let store = EconomicStore::new(directory.path());
    let mut state = state();
    state.economic_assumptions.insert(
        "CA".into(),
        Assumptions {
            currency: "CAD".into(),
            monthly_net_income: 100_000,
            monthly_essential: 100_000,
            daily_spending: 100,
            goal_currency: "CAD".into(),
            exchange_rate_trillionths: None,
        },
    );
    let before = state.clone();
    save(&store);
    let result = forecast(
        &state,
        &store.read(),
        state.start_date,
        "target",
        "CA",
        "CAD",
    )
    .expect("forecast");
    assert!(result.customized);
    assert_eq!(result.monthly_net_income, Some(100_000));
    assert_eq!(result.monthly_saving, Some(0));
    assert_eq!(result.completion_days, None);
    assert_eq!(state, before);
}

#[test]
fn small_custom_toman_conversion_remains_precise_and_explicit() {
    let directory = tempfile::tempdir().expect("directory");
    let store = EconomicStore::new(directory.path());
    let mut state = state();
    state.planned[0].amount = amount(1_000_000_000);
    state.economic_assumptions.insert(
        "CA".into(),
        Assumptions {
            currency: "CAD".into(),
            monthly_net_income: 500_000,
            monthly_essential: 200_000,
            daily_spending: 1000,
            goal_currency: "TOMAN".into(),
            exchange_rate_trillionths: Some(8_771_234),
        },
    );
    let result = forecast(
        &state,
        &store.read(),
        state.start_date,
        "target",
        "CA",
        "TOMAN",
    )
    .expect("forecast");
    assert!(result.customized);
    assert_eq!(result.converted_remaining, Some(8772));
    assert_eq!(result.exchange_rate_trillionths, Some(8_771_234));
}

#[test]
fn json_backup_preserves_custom_profiles_and_rejects_invalid_assumptions() {
    let mut state = state();
    state.economic_assumptions.insert(
        "IR".into(),
        Assumptions {
            currency: "TOMAN".into(),
            monthly_net_income: 10_000_000,
            monthly_essential: 5_000_000,
            daily_spending: 10_000,
            goal_currency: "CAD".into(),
            exchange_rate_trillionths: Some(114_000_000_000_000_000),
        },
    );
    let text = crate::backup::export_json(&state).expect("backup");
    assert_eq!(crate::backup::import_json(&text).expect("restored"), state);
    let mut document: serde_json::Value = serde_json::from_str(&text).expect("JSON");
    document["economicAssumptions"]["IR"]["monthlyNetIncome"] = serde_json::json!(-1);
    assert!(crate::backup::import_json(&document.to_string()).is_err());
}

#[test]
fn cached_exchange_is_available_offline_and_rejected_rates_cannot_replace_it() {
    let directory = tempfile::tempdir().expect("directory");
    let store = EconomicStore::new(directory.path());
    let exchange = ExchangeRate {
        currency: "USD".into(),
        cad_per_unit: 1.4246,
        date: "2026-10-02".into(),
        downloaded: "2026-10-04".into(),
    };
    store
        .save(Download {
            profile: profile(),
            exchange: Some(exchange.clone()),
        })
        .expect("save");
    let state = state();
    let result = forecast(
        &state,
        &store.read(),
        state.start_date,
        "target",
        "CA",
        "USD",
    )
    .expect("forecast");
    assert_eq!(result.converted_remaining, Some(142460));
    let mut invalid = exchange;
    invalid.cad_per_unit = f64::NAN;
    assert!(
        store
            .save(Download {
                profile: profile(),
                exchange: Some(invalid)
            })
            .is_err()
    );
    assert_eq!(
        store
            .read()
            .exchange("USD")
            .expect("cached rate")
            .cad_per_unit,
        1.4246
    );
}
