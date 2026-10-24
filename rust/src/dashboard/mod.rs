pub mod range;
mod series;

use std::collections::BTreeMap;

use serde::Serialize;

use crate::{
    AppState, Date, PouchResult, budget,
    models::{Category, PlannedItem, PlannedKind, PlannedStatus},
};
use range::{DashboardQuery, Range, label};
use series::Point;

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Slice {
    pub key: String,
    pub amount: i64,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Progress {
    pub key: String,
    pub name: String,
    pub amount: i64,
    pub target: i64,
    pub basis_points: i32,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PeriodComparison {
    pub id: String,
    pub name: String,
    pub from: String,
    pub through: String,
    pub income: i64,
    pub expenses: i64,
    pub planned: i64,
    pub paid: i64,
    pub savings_target: i64,
    pub savings: i64,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DashboardSnapshot {
    pub from: String,
    pub through: String,
    pub as_of: String,
    pub from_label: String,
    pub through_label: String,
    pub as_of_label: String,
    pub period_id: Option<String>,
    pub income: i64,
    pub assigned_income: Option<i64>,
    pub expenses: i64,
    pub net: i64,
    pub cash: i64,
    pub free: i64,
    pub protected_savings: i64,
    pub reserved: i64,
    pub funded_expenses: i64,
    pub contributions: i64,
    pub releases: i64,
    pub has_activity: bool,
    pub future_only: bool,
    pub categories: Vec<Slice>,
    pub spending: Vec<Slice>,
    pub allocation: Vec<Slice>,
    pub points: Vec<Point>,
    pub progress: Vec<Progress>,
    pub goals: Vec<Progress>,
    pub goal_count: usize,
    pub comparisons: Vec<PeriodComparison>,
    pub comparison_count: usize,
}

pub fn snapshot(
    state: &AppState,
    query: &DashboardQuery,
    today: Date,
) -> PouchResult<DashboardSnapshot> {
    let range = range::resolve(state, query, today)?;
    let period_id = if query.mode == "period" {
        query.period_id.clone()
    } else {
        None
    };
    let future_only = range.from > range.as_of;
    let mut result = DashboardSnapshot {
        from: range.from.iso()?,
        through: range.through.iso()?,
        as_of: range.as_of.iso()?,
        from_label: label(state, range.from)?,
        through_label: label(state, range.through)?,
        as_of_label: label(state, range.as_of)?,
        period_id,
        income: 0,
        assigned_income: None,
        expenses: 0,
        net: 0,
        cash: 0,
        free: 0,
        protected_savings: 0,
        reserved: 0,
        funded_expenses: 0,
        contributions: 0,
        releases: 0,
        has_activity: false,
        future_only,
        categories: Vec::new(),
        spending: Vec::new(),
        allocation: Vec::new(),
        points: Vec::new(),
        progress: Vec::new(),
        goals: Vec::new(),
        goal_count: 0,
        comparisons: Vec::new(),
        comparison_count: 0,
    };
    if future_only {
        return Ok(result);
    }
    let end = range.as_of.add_days(1)?;
    result.income = budget::income_between(state, range.from, end)?;
    result.expenses = budget::spent(state, range.from, end)?;
    result.net = budget::total(result.income, -result.expenses)?;
    if let Some(id) = &result.period_id {
        result.assigned_income = Some(budget::income_for_period(state, id, range.as_of)?);
    }
    let funding = budget::funding(state, range.as_of)?;
    result.cash = funding.cash;
    result.free = funding.free;
    result.protected_savings = funding.savings;
    result.reserved = funding.reserved;
    result.funded_expenses = funding.cash.max(0).min(funding.reserved);
    result.allocation = vec![
        slice("dashboardAvailable", funding.free.max(0)),
        slice("protectedSavings", funding.savings),
        slice("dashboardFundedObligations", result.funded_expenses),
    ];
    let links = payment_links(state);
    let mut categories = BTreeMap::new();
    let mut essential = 0;
    for (date, day) in state.days.range(range.from..=range.as_of) {
        for purchase in &day.purchases {
            let key = category_key(purchase.category);
            let value = categories.entry(key).or_insert(0);
            *value = budget::total(*value, purchase.amount.hundredths())?;
            if links
                .get(&(*date, purchase.id.as_str()))
                .is_some_and(|item| item.essential_id.is_some())
            {
                essential = budget::total(essential, purchase.amount.hundredths())?;
            }
        }
    }
    result.categories = categories
        .into_iter()
        .map(|(key, amount)| slice(key, amount))
        .collect();
    result.spending = vec![
        slice("dashboardLinkedEssential", essential),
        slice("dashboardOtherSpending", result.expenses - essential),
    ];
    result.points = series::build(state, range)?;
    for point in &result.points {
        result.contributions = budget::total(result.contributions, point.contributions)?;
        result.releases = budget::total(result.releases, point.releases)?;
    }
    result.has_activity = result.income != 0
        || result.expenses != 0
        || result.contributions != 0
        || result.releases != 0;
    result.progress.push(progress(
        "dashboardUtilization",
        "",
        result.expenses,
        budget::total(result.expenses, result.free.max(0))?,
    ));
    result.progress.push(progress(
        "dashboardRemaining",
        "",
        result.free.max(0),
        budget::total(result.expenses, result.free.max(0))?,
    ));
    result.progress.push(progress(
        "dashboardObligationFunding",
        "",
        result.funded_expenses,
        result.reserved,
    ));
    let horizon = crate::periods::at(state, range.as_of)
        .map(|period| period.end)
        .unwrap_or(range.as_of);
    let obligations = crate::expenses::obligations(state, horizon.max(range.through))?;
    let (planned, paid) = commitments(
        state,
        &obligations,
        &links,
        range,
        result.period_id.as_deref(),
        true,
    )?;
    result
        .progress
        .push(progress("dashboardEssentialPayments", "", paid, planned));
    let mut essential_funded = 0;
    let mut essential_target = 0;
    for item in crate::expenses::outstanding(state, range.as_of, horizon)?
        .iter()
        .filter(|item| item.essential_id.is_some())
    {
        let forecast = crate::forecast::preview(state, range.as_of, &item.id, false, false)?;
        essential_funded = budget::total(essential_funded, forecast.allocated)?;
        essential_target = budget::total(essential_target, item.amount.hundredths())?;
    }
    result.progress.push(progress(
        "dashboardEssentialFunding",
        "",
        essential_funded,
        essential_target,
    ));
    let selected_id = result.period_id.clone();
    append_goals(state, range.as_of, selected_id.as_deref(), &mut result)?;
    let periods: Vec<_> = state
        .periods
        .iter()
        .filter(|period| period.start <= range.as_of && period.end > range.from)
        .collect();
    result.comparison_count = periods.len();
    for period in periods.iter().skip(periods.len().saturating_sub(24)) {
        let from = period.start.max(range.from);
        let through = period.end.add_days(-1)?.min(range.as_of);
        let comparison_range = Range {
            from,
            through,
            as_of: through,
        };
        let (planned, paid) = commitments(
            state,
            &obligations,
            &links,
            comparison_range,
            Some(&period.id),
            false,
        )?;
        let savings = state
            .allocations
            .iter()
            .filter(|item| item.period_id == period.id && item.date >= from && item.date <= through)
            .try_fold(0, |sum, item| budget::total(sum, item.amount))?;
        result.comparisons.push(PeriodComparison {
            id: period.id.clone(),
            name: state
                .period_context
                .names
                .get(&period.id)
                .unwrap_or(&period.id)
                .clone(),
            from: label(state, from)?,
            through: label(state, through)?,
            income: budget::income_between(state, from, through.add_days(1)?)?,
            expenses: budget::spent(state, from, through.add_days(1)?)?,
            planned,
            paid,
            savings_target: budget::plan_at(state, through).savings.hundredths(),
            savings,
        });
    }
    Ok(result)
}

fn append_goals(
    state: &AppState,
    as_of: Date,
    selected: Option<&str>,
    result: &mut DashboardSnapshot,
) -> PouchResult<()> {
    let period = crate::periods::at(state, as_of).ok();
    let id = selected
        .or_else(|| period.as_ref().map(|value| value.id.as_str()))
        .unwrap_or("");
    let mut goals: Vec<_> = state
        .planned
        .iter()
        .filter(|item| {
            item.kind == PlannedKind::Goal
                && (item.status == PlannedStatus::Pending
                    || item.paid_date.is_some_and(|date| date > as_of))
                && crate::periods::context::planned_matches(state, item, id)
        })
        .collect();
    goals.sort_by(|a, b| a.date.cmp(&b.date).then_with(|| a.id.cmp(&b.id)));
    result.goal_count = goals.len();
    for goal in goals.into_iter().take(20) {
        let forecast = crate::forecast::preview(state, as_of, &goal.id, false, false)?;
        result.goals.push(progress(
            &goal.id,
            &goal.description,
            forecast.allocated,
            goal.amount.hundredths(),
        ));
    }
    Ok(())
}

fn payment_links(state: &AppState) -> BTreeMap<(Date, &str), &PlannedItem> {
    state
        .planned
        .iter()
        .filter_map(|item| {
            item.paid_date
                .zip(item.purchase_id.as_deref())
                .map(|key| (key, item))
        })
        .collect()
}

fn commitments(
    state: &AppState,
    obligations: &[PlannedItem],
    links: &BTreeMap<(Date, &str), &PlannedItem>,
    range: Range,
    period_id: Option<&str>,
    essential_only: bool,
) -> PouchResult<(i64, i64)> {
    let matches = |item: &PlannedItem| {
        item.kind == PlannedKind::Expense
            && (!essential_only || item.essential_id.is_some())
            && if let Some(id) = period_id {
                match crate::periods::context::planned_period(state, item) {
                    Some(assigned) => assigned == id,
                    None => item.date >= range.from && item.date <= range.through,
                }
            } else {
                item.date >= range.from && item.date <= range.through
            }
    };
    let planned = obligations
        .iter()
        .filter(|item| matches(item))
        .try_fold(0, |sum, item| budget::total(sum, item.amount.hundredths()))?;
    let mut paid = 0;
    for (date, day) in state.days.range(..=range.as_of) {
        for purchase in &day.purchases {
            if links
                .get(&(*date, purchase.id.as_str()))
                .is_some_and(|item| matches(item))
            {
                paid = budget::total(paid, purchase.amount.hundredths())?;
            }
        }
    }
    Ok((planned, paid))
}

fn progress(key: &str, name: &str, amount: i64, target: i64) -> Progress {
    let basis_points = if target > 0 {
        ((i128::from(amount.max(0)) * 10_000) / i128::from(target)).min(10_000) as i32
    } else {
        0
    };
    Progress {
        key: key.into(),
        name: name.into(),
        amount,
        target,
        basis_points,
    }
}

fn slice(key: &str, amount: i64) -> Slice {
    Slice {
        key: key.into(),
        amount,
    }
}

fn category_key(category: Category) -> &'static str {
    match category {
        Category::Other => "other",
        Category::Food => "food",
        Category::Transport => "transport",
        Category::Shopping => "shopping",
        Category::Health => "health",
        Category::Entertainment => "entertainment",
        Category::Bills => "bills",
    }
}
