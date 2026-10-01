use std::collections::BTreeMap;

use chrono::Local;
use serde_json::Value;

use crate::{
    AppState, Date, PouchError, PouchResult,
    models::{
        BudgetPlan, Calendar, Category, Country, Currency, DailyRecord, ExpectedIncomeEntry,
        IncomeEntry, Language, PlannedItem, PlannedKind, PlannedStatus, Preferences, Purchase,
        RequiredExpense, WeekStart,
    },
    money::Money,
};

const MAX_BACKUP_BYTES: usize = 5_000_000;

pub fn from_versioned_json(contents: &str) -> PouchResult<AppState> {
    let contents = contents.strip_prefix('\u{feff}').unwrap_or(contents);
    if contents.len() > MAX_BACKUP_BYTES {
        return Err(PouchError::BackupTooLarge);
    }
    let mut source: Value =
        serde_json::from_str(contents).map_err(|_| PouchError::InvalidBackup)?;
    let version = field(&source, "version")?
        .as_i64()
        .ok_or(PouchError::InvalidBackup)?;
    match version {
        5 => from_v5(&source),
        4 => from_v4(&source),
        3 => {
            upgrade_v3(&mut source)?;
            from_v4(&source)
        }
        1 | 2 => from_v1_or_v2(&source, version),
        _ => Err(PouchError::UnsupportedBackupVersion),
    }
}

fn upgrade_v3(source: &mut Value) -> PouchResult<()> {
    let object = source.as_object_mut().ok_or(PouchError::InvalidBackup)?;
    object.insert("version".into(), Value::from(4));
    object.insert("income".into(), Value::Array(Vec::new()));
    let plans = object
        .get_mut("plans")
        .and_then(Value::as_array_mut)
        .ok_or(PouchError::InvalidBackup)?;
    for plan in plans {
        let plan = plan.as_object_mut().ok_or(PouchError::InvalidBackup)?;
        let salary_is_null = plan
            .get("salary")
            .ok_or(PouchError::InvalidBackup)?
            .is_null();
        let budget = plan
            .get("dailyBudget")
            .and_then(Value::as_i64)
            .ok_or(PouchError::InvalidBackup)?;
        if !plan.contains_key("legacy") {
            plan.insert("legacy".into(), Value::Bool(salary_is_null && budget > 0));
        }
        plan.insert("savings".into(), Value::from(0));
    }
    let planned = object
        .get_mut("planned")
        .and_then(Value::as_array_mut)
        .ok_or(PouchError::InvalidBackup)?;
    for item in planned {
        let item = item.as_object_mut().ok_or(PouchError::InvalidBackup)?;
        if !item.contains_key("kind") {
            item.insert("kind".into(), Value::String("expense".into()));
        }
    }
    Ok(())
}

fn from_v1_or_v2(source: &Value, version: i64) -> PouchResult<AppState> {
    let start_date = date_string(source, "startDate")?;
    let start = Date::parse_iso(start_date)?;
    let today = Date::from_naive_date(Local::now().date_naive())?;
    let mut state = AppState::fresh(start);
    state.preferences.country = Country::Custom;
    state.preferences.currency = currency(source, "currency")?;
    state.preferences.calendar = Calendar::Gregorian;
    state.preferences.week_start = WeekStart::Monday;
    state.plans[0].calendar = Calendar::Gregorian;
    let first_plan = state.plans.first_mut().ok_or(PouchError::InvalidState)?;
    first_plan.daily_budget = money(source, "dailyBudget")?;
    first_plan.legacy = true;
    if version == 2 {
        first_plan.fallback_salary = optional_money(source, "monthlySalary")?;
        first_plan.expenses = expenses(source.get("expenses").ok_or(PouchError::InvalidBackup)?)?;
    }

    let source_days = field(source, "days")?
        .as_object()
        .ok_or(PouchError::InvalidBackup)?;
    let mut planned = Vec::new();
    for (date_text, day) in source_days {
        let date = Date::parse_iso(date_text)?;
        let day = day.as_object().ok_or(PouchError::InvalidBackup)?;
        let budget = match day.get("budget") {
            Some(Value::Null) | None => None,
            Some(value) => Some(money_value(value)?),
        };
        let source_purchases = day
            .get("purchases")
            .and_then(Value::as_array)
            .ok_or(PouchError::InvalidBackup)?;
        let mut purchases = Vec::new();
        for item in source_purchases {
            let purchase = legacy_purchase(item, true)?;
            if date > today {
                planned.push(PlannedItem {
                    id: format!("{}:{}", date_text, purchase.id),
                    description: purchase.description,
                    amount: purchase.amount,
                    category: Category::Other,
                    kind: PlannedKind::Expense,
                    date,
                    status: PlannedStatus::Pending,
                    paid_date: None,
                    purchase_id: None,
                });
            } else {
                purchases.push(purchase);
            }
        }
        state.days.insert(
            date,
            DailyRecord {
                budget_override: budget,
                purchases,
            },
        );
    }
    state.planned = planned;
    state.validate()?;
    Ok(state)
}

fn from_v4(source: &Value) -> PouchResult<AppState> {
    from_document(source, false)
}

fn from_v5(source: &Value) -> PouchResult<AppState> {
    from_document(source, true)
}

fn from_document(source: &Value, includes_regional_data: bool) -> PouchResult<AppState> {
    let mut state = AppState {
        schema_version: AppState::CURRENT_SCHEMA_VERSION,
        start_date: Date::parse_iso(date_string(source, "startDate")?)?,
        preferences: Preferences {
            country: if includes_regional_data {
                country(source, "country")?
            } else {
                Country::Custom
            },
            currency: currency(source, "currency")?,
            language: language(source, "language")?,
            calendar: calendar(source, "calendar")?,
            week_start: week_start(source, "weekStart")?,
        },
        income: Vec::new(),
        expected_income: Vec::new(),
        plans: Vec::new(),
        days: BTreeMap::new(),
        planned: Vec::new(),
    };

    for entry in array(source, "income")? {
        state.income.push(IncomeEntry {
            id: string(entry, "id")?.to_owned(),
            date: Date::parse_iso(date_string(entry, "date")?)?,
            amount: money(entry, "amount")?,
        });
    }
    if includes_regional_data {
        for entry in array(source, "expectedIncome")? {
            state.expected_income.push(ExpectedIncomeEntry {
                id: string(entry, "id")?.to_owned(),
                date: Date::parse_iso(date_string(entry, "date")?)?,
                amount: money(entry, "amount")?,
            });
        }
    }
    for plan in array(source, "plans")? {
        state.plans.push(BudgetPlan {
            effective: Date::parse_iso(date_string(plan, "effective")?)?,
            fallback_salary: optional_money(plan, "salary")?,
            daily_budget: money(plan, "dailyBudget")?,
            expenses: expenses(field(plan, "expenses")?)?,
            monthly_savings: money(plan, "savings")?,
            payday: u8::try_from(integer(plan, "payday")?)
                .map_err(|_| PouchError::InvalidBackup)?,
            calendar: calendar(plan, "calendar")?,
            legacy: field(plan, "legacy")?
                .as_bool()
                .ok_or(PouchError::InvalidBackup)?,
        });
    }
    let days = field(source, "days")?
        .as_object()
        .ok_or(PouchError::InvalidBackup)?;
    for (date_text, day) in days {
        let date = Date::parse_iso(date_text)?;
        let budget_override = match day.get("budget") {
            Some(Value::Null) | None => None,
            Some(value) => Some(money_value(value)?),
        };
        let purchases = array(day, "purchases")?
            .iter()
            .map(|purchase| legacy_purchase(purchase, false))
            .collect::<PouchResult<Vec<_>>>()?;
        state.days.insert(
            date,
            DailyRecord {
                budget_override,
                purchases,
            },
        );
    }
    for item in array(source, "planned")? {
        state.planned.push(PlannedItem {
            id: string(item, "id")?.to_owned(),
            description: string(item, "description")?.to_owned(),
            amount: money(item, "amount")?,
            category: category(item, "category")?,
            kind: planned_kind(item.get("kind"))?,
            date: Date::parse_iso(date_string(item, "date")?)?,
            status: planned_status(item, "status")?,
            paid_date: optional_date(item, "paidDate")?,
            purchase_id: optional_string(item, "purchaseId")?.map(str::to_owned),
        });
    }
    state.validate()?;
    Ok(state)
}

fn expenses(value: &Value) -> PouchResult<Vec<RequiredExpense>> {
    value
        .as_array()
        .ok_or(PouchError::InvalidBackup)?
        .iter()
        .map(|entry| {
            Ok(RequiredExpense {
                id: string(entry, "id")?.to_owned(),
                name: string(entry, "name")?.to_owned(),
                amount: money(entry, "amount")?,
            })
        })
        .collect()
}

fn legacy_purchase(value: &Value, force_other: bool) -> PouchResult<Purchase> {
    Ok(Purchase {
        id: string(value, "id")?.to_owned(),
        description: string(value, "description")?.to_owned(),
        amount: money(value, "amount")?,
        category: if force_other {
            Category::Other
        } else {
            category(value, "category")?
        },
        funded_by_goal: value
            .get("fundedByGoal")
            .and_then(Value::as_bool)
            .unwrap_or(false),
    })
}

fn field<'a>(value: &'a Value, key: &str) -> PouchResult<&'a Value> {
    value.get(key).ok_or(PouchError::InvalidBackup)
}

fn string<'a>(value: &'a Value, key: &str) -> PouchResult<&'a str> {
    field(value, key)?.as_str().ok_or(PouchError::InvalidBackup)
}

fn date_string<'a>(value: &'a Value, key: &str) -> PouchResult<&'a str> {
    string(value, key)
}

fn integer(value: &Value, key: &str) -> PouchResult<i64> {
    field(value, key)?.as_i64().ok_or(PouchError::InvalidBackup)
}

fn money(value: &Value, key: &str) -> PouchResult<Money> {
    Money::from_hundredths(integer(value, key)?).map_err(|_| PouchError::InvalidBackup)
}

fn money_value(value: &Value) -> PouchResult<Money> {
    Money::from_hundredths(value.as_i64().ok_or(PouchError::InvalidBackup)?)
        .map_err(|_| PouchError::InvalidBackup)
}

fn optional_money(value: &Value, key: &str) -> PouchResult<Option<Money>> {
    match field(value, key)? {
        Value::Null => Ok(None),
        value => Ok(Some(money_value(value)?)),
    }
}

fn optional_date(value: &Value, key: &str) -> PouchResult<Option<Date>> {
    match field(value, key)? {
        Value::Null => Ok(None),
        Value::String(value) => Ok(Some(Date::parse_iso(value)?)),
        _ => Err(PouchError::InvalidBackup),
    }
}

fn optional_string<'a>(value: &'a Value, key: &str) -> PouchResult<Option<&'a str>> {
    match field(value, key)? {
        Value::Null => Ok(None),
        Value::String(value) => Ok(Some(value)),
        _ => Err(PouchError::InvalidBackup),
    }
}

fn array<'a>(value: &'a Value, key: &str) -> PouchResult<&'a Vec<Value>> {
    field(value, key)?
        .as_array()
        .ok_or(PouchError::InvalidBackup)
}

fn currency(value: &Value, key: &str) -> PouchResult<Currency> {
    match string(value, key)? {
        "TOMAN" => Ok(Currency::Toman),
        "CAD" => Ok(Currency::Cad),
        "USD" => Ok(Currency::Usd),
        "EUR" => Ok(Currency::Eur),
        "GBP" => Ok(Currency::Gbp),
        "AUD" => Ok(Currency::Aud),
        "NZD" => Ok(Currency::Nzd),
        _ => Err(PouchError::InvalidBackup),
    }
}

fn country(value: &Value, key: &str) -> PouchResult<Country> {
    match string(value, key)? {
        "iran" => Ok(Country::Iran),
        "canada" => Ok(Country::Canada),
        "united_states" => Ok(Country::UnitedStates),
        "united_kingdom" => Ok(Country::UnitedKingdom),
        "germany" => Ok(Country::Germany),
        "australia" => Ok(Country::Australia),
        "new_zealand" => Ok(Country::NewZealand),
        "custom" => Ok(Country::Custom),
        _ => Err(PouchError::InvalidBackup),
    }
}

fn language(value: &Value, key: &str) -> PouchResult<Language> {
    match string(value, key)? {
        "en" => Ok(Language::English),
        "fa" => Ok(Language::Persian),
        _ => Err(PouchError::InvalidBackup),
    }
}

fn calendar(value: &Value, key: &str) -> PouchResult<Calendar> {
    match string(value, key)? {
        "gregory" => Ok(Calendar::Gregorian),
        "persian" => Ok(Calendar::Jalali),
        _ => Err(PouchError::InvalidBackup),
    }
}

fn week_start(value: &Value, key: &str) -> PouchResult<WeekStart> {
    match integer(value, key)? {
        0 => Ok(WeekStart::Sunday),
        1 => Ok(WeekStart::Monday),
        6 => Ok(WeekStart::Saturday),
        _ => Err(PouchError::InvalidBackup),
    }
}

fn category(value: &Value, key: &str) -> PouchResult<Category> {
    match string(value, key)? {
        "other" => Ok(Category::Other),
        "food" => Ok(Category::Food),
        "transport" => Ok(Category::Transport),
        "shopping" => Ok(Category::Shopping),
        "health" => Ok(Category::Health),
        "entertainment" => Ok(Category::Entertainment),
        "bills" => Ok(Category::Bills),
        _ => Err(PouchError::InvalidBackup),
    }
}

fn planned_kind(value: Option<&Value>) -> PouchResult<PlannedKind> {
    match value.and_then(Value::as_str).unwrap_or("expense") {
        "expense" => Ok(PlannedKind::Expense),
        "goal" => Ok(PlannedKind::Goal),
        _ => Err(PouchError::InvalidBackup),
    }
}

fn planned_status(value: &Value, key: &str) -> PouchResult<PlannedStatus> {
    match string(value, key)? {
        "pending" => Ok(PlannedStatus::Pending),
        "paid" => Ok(PlannedStatus::Paid),
        _ => Err(PouchError::InvalidBackup),
    }
}

#[cfg(test)]
mod tests {
    use chrono::Local;
    use serde_json::json;

    use super::from_versioned_json;
    use crate::models::{PlannedKind, PlannedStatus};

    #[test]
    fn version_one_future_purchases_become_pending_expenses() {
        let today = Local::now().date_naive();
        let start = today.format("%Y-%m-%d").to_string();
        let future = (today + chrono::Duration::days(1))
            .format("%Y-%m-%d")
            .to_string();
        let contents = json!({
            "version": 1,
            "startDate": start,
            "currency": "TOMAN",
            "dailyBudget": 1_500,
            "days": {
                (future): {
                    "budget": null,
                    "purchases": [{"id": "future-coffee", "description": "Coffee", "amount": 250}]
                }
            }
        })
        .to_string();

        let state = from_versioned_json(&contents).expect("the version 1 backup imports");

        assert!(state.days.values().all(|day| day.purchases.is_empty()));
        assert_eq!(state.planned.len(), 1);
        assert_eq!(state.planned[0].description, "Coffee");
        assert_eq!(state.planned[0].status, PlannedStatus::Pending);
        assert_eq!(state.planned[0].kind, PlannedKind::Expense);
    }

    #[test]
    fn version_three_plans_gain_legacy_behavior_and_zero_savings() {
        let today = Local::now().date_naive().format("%Y-%m-%d").to_string();
        let contents = json!({
            "version": 3,
            "startDate": today,
            "currency": "TOMAN",
            "language": "en",
            "calendar": "gregory",
            "weekStart": 1,
            "plans": [{
                "effective": today,
                "salary": null,
                "dailyBudget": 900,
                "expenses": [],
                "payday": 1,
                "calendar": "gregory"
            }],
            "days": {},
            "planned": [{
                "id": "pending",
                "description": "Bill",
                "amount": 300,
                "category": "bills",
                "date": today,
                "status": "pending",
                "paidDate": null,
                "purchaseId": null
            }]
        })
        .to_string();

        let state = from_versioned_json(&contents).expect("the version 3 backup imports");

        assert!(state.plans[0].legacy);
        assert_eq!(state.plans[0].monthly_savings.hundredths(), 0);
        assert_eq!(state.planned[0].kind, PlannedKind::Expense);
    }

    #[test]
    fn version_five_restores_country_and_expected_income() {
        let today = Local::now().date_naive();
        let start = today.format("%Y-%m-%d").to_string();
        let expected_date = (today + chrono::Duration::days(3))
            .format("%Y-%m-%d")
            .to_string();
        let contents = json!({
            "version": 5,
            "startDate": start,
            "country": "iran",
            "currency": "TOMAN",
            "language": "en",
            "calendar": "persian",
            "weekStart": 6,
            "income": [],
            "expectedIncome": [{
                "id": "next-payday",
                "date": expected_date,
                "amount": 12500
            }],
            "plans": [{
                "effective": start,
                "salary": null,
                "dailyBudget": 0,
                "expenses": [],
                "savings": 0,
                "payday": 1,
                "calendar": "persian",
                "legacy": false
            }],
            "days": {},
            "planned": []
        })
        .to_string();

        let state = from_versioned_json(&contents).expect("version 5 imports");

        assert_eq!(state.preferences.country, crate::models::Country::Iran);
        assert_eq!(state.expected_income.len(), 1);
        assert_eq!(state.expected_income[0].id, "next-payday");
        assert_eq!(state.expected_income[0].amount.hundredths(), 12500);
    }
}
