mod versioned_json;

use serde_json::{Map, Value, json};

use crate::{AppState, PouchError, PouchResult, models::*};

pub fn export_json(state: &AppState) -> PouchResult<String> {
    state.validate()?;
    let mut days = Map::new();
    for (date, day) in &state.days {
        let purchases = day
            .purchases
            .iter()
            .map(|purchase| {
                json!({
                    "id": purchase.id,
                    "description": purchase.description,
                    "amount": purchase.amount.hundredths(),
                    "category": category_name(purchase.category),
                    "fundedByGoal": purchase.funded_by_goal,
                })
            })
            .collect::<Vec<_>>();
        days.insert(
            date.iso()?,
            json!({
                "budget": day.budget_override.map(|amount| amount.hundredths()),
                "purchases": purchases,
            }),
        );
    }
    let document = json!({
        "version": 6,
        "economicAssumptions": state.economic_assumptions,
        "startDate": state.start_date.iso()?,
        "country": country_name(state.preferences.country),
        "currency": currency_name(state.preferences.currency),
        "language": language_name(state.preferences.language),
        "calendar": calendar_name(state.preferences.calendar),
        "weekStart": week_start_number(state.preferences.week_start),
        "income": state.income.iter().map(|entry| Ok(json!({
            "id": entry.id,
            "date": entry.date.iso()?,
            "amount": entry.amount.hundredths(),
        }))).collect::<PouchResult<Vec<Value>>>()?,
        "expectedIncome": state.expected_income.iter().map(|entry| Ok(json!({
            "id": entry.id,
            "date": entry.date.iso()?,
            "amount": entry.amount.hundredths(),
        }))).collect::<PouchResult<Vec<Value>>>()?,
        "plans": state.plans.iter().map(|plan| Ok(json!({
            "effective": plan.effective.iso()?,
            "salary": plan.fallback_salary.map(|amount| amount.hundredths()),
            "dailyBudget": plan.daily_budget.hundredths(),
            "expenses": plan.expenses.iter().map(|expense| json!({
                "id": expense.id,
                "name": expense.name,
                "amount": expense.amount.hundredths(),
            })).collect::<Vec<_>>(),
            "savings": plan.monthly_savings.hundredths(),
            "payday": plan.payday,
            "calendar": calendar_name(plan.calendar),
            "legacy": plan.legacy,
        }))).collect::<PouchResult<Vec<Value>>>()?,
        "days": days,
        "planned": state.planned.iter().map(|item| Ok(json!({
            "id": item.id,
            "description": item.description,
            "amount": item.amount.hundredths(),
            "category": category_name(item.category),
            "kind": planned_kind_name(item.kind),
            "date": item.date.iso()?,
            "status": planned_status_name(item.status),
            "paidDate": item.paid_date.map(|date| date.iso()).transpose()?,
            "purchaseId": item.purchase_id,
        }))).collect::<PouchResult<Vec<Value>>>()?,
    });
    let text = serde_json::to_string_pretty(&document).map_err(|_| PouchError::InvalidBackup)?;
    if text.len() > 5_000_000 {
        return Err(PouchError::BackupTooLarge);
    }
    Ok(text)
}

pub fn import_json(contents: &str) -> PouchResult<AppState> {
    versioned_json::from_versioned_json(contents)
}

fn currency_name(value: Currency) -> &'static str {
    match value {
        Currency::Toman => "TOMAN",
        Currency::Cad => "CAD",
        Currency::Usd => "USD",
        Currency::Eur => "EUR",
        Currency::Gbp => "GBP",
        Currency::Aud => "AUD",
        Currency::Nzd => "NZD",
    }
}

fn country_name(value: Country) -> &'static str {
    match value {
        Country::Iran => "iran",
        Country::Canada => "canada",
        Country::UnitedStates => "united_states",
        Country::UnitedKingdom => "united_kingdom",
        Country::Germany => "germany",
        Country::Australia => "australia",
        Country::NewZealand => "new_zealand",
        Country::Custom => "custom",
    }
}

fn language_name(value: Language) -> &'static str {
    match value {
        Language::English => "en",
        Language::Persian => "fa",
    }
}

fn calendar_name(value: Calendar) -> &'static str {
    match value {
        Calendar::Gregorian => "gregory",
        Calendar::Jalali => "persian",
    }
}

fn week_start_number(value: WeekStart) -> i32 {
    match value {
        WeekStart::Sunday => 0,
        WeekStart::Monday => 1,
        WeekStart::Saturday => 6,
    }
}

fn category_name(value: Category) -> &'static str {
    match value {
        Category::Other => "other",
        Category::Food => "food",
        Category::Transport => "transport",
        Category::Shopping => "shopping",
        Category::Health => "health",
        Category::Entertainment => "entertainment",
        Category::Bills => "bills",
    }
}

fn planned_kind_name(value: PlannedKind) -> &'static str {
    match value {
        PlannedKind::Expense => "expense",
        PlannedKind::Goal => "goal",
    }
}

fn planned_status_name(value: PlannedStatus) -> &'static str {
    match value {
        PlannedStatus::Pending => "pending",
        PlannedStatus::Paid => "paid",
    }
}

#[cfg(test)]
mod tests {
    use super::{export_json, import_json};
    use crate::{AppState, Date};

    #[test]
    fn portable_backup_round_trip_keeps_application_state() {
        let date = Date::parse_iso("2026-09-21").expect("the date is valid");
        let expected = AppState::fresh(date);

        let contents = export_json(&expected).expect("the backup should export");
        let restored = import_json(&contents).expect("the backup should import");

        assert_eq!(restored, expected);
    }

    #[test]
    fn unsupported_backup_is_rejected() {
        assert!(import_json("{\"version\":99}").is_err());
    }
}
