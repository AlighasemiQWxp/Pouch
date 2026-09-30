use std::collections::BTreeMap;

use chrono::{Datelike, Local, NaiveDate};
use serde::{Deserialize, Serialize};

use crate::{PouchError, PouchResult, money::Money};

#[derive(Clone, Copy, Debug, Deserialize, Eq, Ord, PartialEq, PartialOrd, Serialize)]
#[serde(transparent)]
pub struct Date(i32);

impl Date {
    pub fn from_ymd(year: i32, month: u32, day: u32) -> PouchResult<Self> {
        let value = NaiveDate::from_ymd_opt(year, month, day).ok_or(PouchError::InvalidDate)?;
        Self::from_naive_date(value)
    }

    pub fn parse_iso(value: &str) -> PouchResult<Self> {
        if value.len() != 10
            || value.as_bytes().get(4) != Some(&b'-')
            || value.as_bytes().get(7) != Some(&b'-')
        {
            return Err(PouchError::InvalidDate);
        }
        let date =
            NaiveDate::parse_from_str(value, "%Y-%m-%d").map_err(|_| PouchError::InvalidDate)?;
        Self::from_naive_date(date)
    }

    pub fn from_naive_date(value: NaiveDate) -> PouchResult<Self> {
        if !(1900..=9998).contains(&value.year()) {
            return Err(PouchError::InvalidDate);
        }
        let epoch = NaiveDate::from_ymd_opt(1970, 1, 1).ok_or(PouchError::InvalidDate)?;
        let days = value.signed_duration_since(epoch).num_days();
        let days = i32::try_from(days).map_err(|_| PouchError::InvalidDate)?;
        Ok(Self(days))
    }

    pub fn to_naive_date(self) -> PouchResult<NaiveDate> {
        let epoch = NaiveDate::from_ymd_opt(1970, 1, 1).ok_or(PouchError::InvalidDate)?;
        let date = epoch
            .checked_add_signed(chrono::Duration::days(i64::from(self.0)))
            .ok_or(PouchError::InvalidDate)?;
        if !(1900..=9998).contains(&date.year()) {
            return Err(PouchError::InvalidDate);
        }
        Ok(date)
    }

    pub fn iso(self) -> PouchResult<String> {
        Ok(self.to_naive_date()?.format("%Y-%m-%d").to_string())
    }

    pub fn add_days(self, days: i32) -> PouchResult<Self> {
        let result = self.0.checked_add(days).ok_or(PouchError::InvalidDate)?;
        Ok(Self(result))
    }

    pub fn days_until(self, other: Self) -> i32 {
        other.0 - self.0
    }

    pub fn day_offset(self) -> i32 {
        self.0
    }
}

#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Calendar {
    #[default]
    Gregorian,
    Jalali,
}

#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Language {
    #[default]
    English,
    Persian,
}

#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum WeekStart {
    Sunday,
    #[default]
    Monday,
    Saturday,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Preferences {
    pub currency: Currency,
    pub language: Language,
    pub calendar: Calendar,
    pub week_start: WeekStart,
}

impl Default for Preferences {
    fn default() -> Self {
        Self {
            currency: Currency::Toman,
            language: Language::English,
            calendar: Calendar::Gregorian,
            week_start: WeekStart::Monday,
        }
    }
}

#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum Currency {
    #[default]
    Toman,
    Cad,
    Usd,
    Eur,
    Gbp,
    Aud,
    Nzd,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RequiredExpense {
    pub id: String,
    pub name: String,
    pub amount: Money,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BudgetPlan {
    pub effective: Date,
    pub fallback_salary: Option<Money>,
    pub daily_budget: Money,
    pub expenses: Vec<RequiredExpense>,
    pub monthly_savings: Money,
    pub payday: u8,
    pub calendar: Calendar,
    pub legacy: bool,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct IncomeEntry {
    pub id: String,
    pub date: Date,
    pub amount: Money,
}

#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Category {
    #[default]
    Other,
    Food,
    Transport,
    Shopping,
    Health,
    Entertainment,
    Bills,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Purchase {
    pub id: String,
    pub description: String,
    pub amount: Money,
    pub category: Category,
    pub funded_by_goal: bool,
}

#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DailyRecord {
    pub budget_override: Option<Money>,
    pub purchases: Vec<Purchase>,
}

#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum PlannedKind {
    #[default]
    Expense,
    Goal,
}

#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum PlannedStatus {
    #[default]
    Pending,
    Paid,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PlannedItem {
    pub id: String,
    pub description: String,
    pub amount: Money,
    pub category: Category,
    pub kind: PlannedKind,
    pub date: Date,
    pub status: PlannedStatus,
    pub paid_date: Option<Date>,
    pub purchase_id: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AppState {
    pub schema_version: u16,
    pub start_date: Date,
    pub preferences: Preferences,
    pub income: Vec<IncomeEntry>,
    pub plans: Vec<BudgetPlan>,
    pub days: BTreeMap<Date, DailyRecord>,
    pub planned: Vec<PlannedItem>,
}

impl AppState {
    pub const CURRENT_SCHEMA_VERSION: u16 = 1;

    pub fn fresh(start_date: Date) -> Self {
        Self {
            schema_version: Self::CURRENT_SCHEMA_VERSION,
            start_date,
            preferences: Preferences::default(),
            income: Vec::new(),
            plans: vec![BudgetPlan {
                effective: start_date,
                fallback_salary: None,
                daily_budget: Money::default(),
                expenses: Vec::new(),
                monthly_savings: Money::default(),
                payday: 1,
                calendar: Calendar::Gregorian,
                legacy: false,
            }],
            days: BTreeMap::new(),
            planned: Vec::new(),
        }
    }

    pub fn validate(&self) -> PouchResult<()> {
        if self.schema_version != Self::CURRENT_SCHEMA_VERSION
            || self.plans.is_empty()
            || self.plans.len() > 1000
            || self.planned.len() > 100_000
            || self.income.len() > 10_000
            || self.plans[0].effective != self.start_date
        {
            return Err(PouchError::InvalidState);
        }
        self.start_date.to_naive_date()?;
        let today = Date::from_naive_date(Local::now().date_naive())?;
        if self.start_date > today {
            return Err(PouchError::InvalidState);
        }
        for plan in &self.plans {
            plan.effective.to_naive_date()?;
            if plan.effective < self.start_date
                || plan.payday == 0
                || plan.payday > 31
                || !validate_optional_money(plan.fallback_salary)
                || !validate_money(plan.daily_budget, false)
                || !validate_money(plan.monthly_savings, false)
            {
                return Err(PouchError::InvalidState);
            }
            let mut expense_total = 0_i64;
            let mut expense_ids = std::collections::BTreeSet::new();
            for expense in &plan.expenses {
                if expense.id.trim().is_empty()
                    || expense.name.trim().is_empty()
                    || expense.name.encode_utf16().count() > 120
                    || !expense_ids.insert(expense.id.as_str())
                    || !validate_money(expense.amount, true)
                {
                    return Err(PouchError::InvalidState);
                }
                expense_total = expense_total
                    .checked_add(expense.amount.hundredths())
                    .filter(|total| *total <= crate::money::MAX_HUNDREDTHS)
                    .ok_or(PouchError::InvalidState)?;
            }
        }
        if self
            .plans
            .windows(2)
            .any(|plans| plans[0].effective >= plans[1].effective)
        {
            return Err(PouchError::InvalidState);
        }
        if self
            .plans
            .windows(2)
            .any(|plans| plans[1].effective < self.start_date)
        {
            return Err(PouchError::InvalidState);
        }
        if self
            .income
            .windows(2)
            .any(|income| income[0].date >= income[1].date)
        {
            return Err(PouchError::InvalidState);
        }
        let mut income_ids = std::collections::BTreeSet::new();
        for income in &self.income {
            income.date.to_naive_date()?;
            if income.date < self.start_date
                || income.date > today
                || income.id.trim().is_empty()
                || !income_ids.insert(income.id.as_str())
                || !validate_money(income.amount, true)
            {
                return Err(PouchError::InvalidState);
            }
        }
        if self.days.keys().any(|date| *date < self.start_date) {
            return Err(PouchError::InvalidState);
        }
        let mut total_purchase_amount = 0_i64;
        let mut paid_links = std::collections::BTreeSet::new();
        let mut purchase_links = std::collections::BTreeSet::new();
        for (date, day) in &self.days {
            date.to_naive_date()?;
            if !validate_optional_money(day.budget_override) {
                return Err(PouchError::InvalidState);
            }
            let mut purchase_ids = std::collections::BTreeSet::new();
            let mut purchase_total = 0_i64;
            for purchase in &day.purchases {
                if purchase.id.trim().is_empty()
                    || purchase.description.trim().is_empty()
                    || purchase.description.encode_utf16().count() > 120
                    || !purchase_ids.insert(purchase.id.as_str())
                    || !validate_money(purchase.amount, true)
                {
                    return Err(PouchError::InvalidState);
                }
                purchase_total = purchase_total
                    .checked_add(purchase.amount.hundredths())
                    .filter(|total| *total <= crate::money::MAX_HUNDREDTHS)
                    .ok_or(PouchError::InvalidState)?;
                total_purchase_amount = total_purchase_amount
                    .checked_add(purchase.amount.hundredths())
                    .filter(|total| *total <= 9_007_199_254_740_991)
                    .ok_or(PouchError::InvalidState)?;
                if purchase.funded_by_goal {
                    paid_links.insert((date.day_offset(), purchase.id.as_str()));
                }
            }
        }
        let mut planned_ids = std::collections::BTreeSet::new();
        let mut planned_total = 0_i64;
        for planned in &self.planned {
            planned.date.to_naive_date()?;
            if planned.id.trim().is_empty()
                || planned.description.trim().is_empty()
                || planned.description.encode_utf16().count() > 120
                || planned.date < self.start_date
                || !planned_ids.insert(planned.id.as_str())
                || !validate_money(planned.amount, true)
            {
                return Err(PouchError::InvalidState);
            }
            planned_total = planned_total
                .checked_add(planned.amount.hundredths())
                .filter(|total| *total <= crate::money::MAX_HUNDREDTHS)
                .ok_or(PouchError::InvalidState)?;
            match planned.status {
                PlannedStatus::Pending => {
                    if planned.paid_date.is_some() || planned.purchase_id.is_some() {
                        return Err(PouchError::InvalidState);
                    }
                }
                PlannedStatus::Paid => {
                    let paid_date = planned.paid_date.ok_or(PouchError::InvalidState)?;
                    let purchase_id = planned
                        .purchase_id
                        .as_deref()
                        .ok_or(PouchError::InvalidState)?;
                    paid_date.to_naive_date()?;
                    let purchase = self
                        .days
                        .get(&paid_date)
                        .and_then(|day| {
                            day.purchases
                                .iter()
                                .find(|purchase| purchase.id == purchase_id)
                        })
                        .ok_or(PouchError::InvalidState)?;
                    let expected_goal_purchase = planned.kind == PlannedKind::Goal;
                    if paid_date < self.start_date
                        || paid_date > today
                        || purchase.funded_by_goal != expected_goal_purchase
                        || !purchase_links.insert((paid_date.day_offset(), purchase_id))
                    {
                        return Err(PouchError::InvalidState);
                    }
                    if expected_goal_purchase {
                        paid_links.remove(&(paid_date.day_offset(), purchase_id));
                    }
                }
            }
        }
        if !paid_links.is_empty() {
            return Err(PouchError::InvalidState);
        }
        Ok(())
    }
}

fn validate_money(value: Money, positive: bool) -> bool {
    let amount = value.hundredths();
    let minimum = if positive { 1 } else { 0 };
    amount >= minimum && amount <= crate::money::MAX_HUNDREDTHS
}

fn validate_optional_money(value: Option<Money>) -> bool {
    value.is_none_or(|amount| validate_money(amount, false))
}
