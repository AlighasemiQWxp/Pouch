use std::collections::BTreeMap;

use serde::Serialize;

use crate::{AppState, Date, PouchResult, budget::total, calendar};

use super::range::{Range, label};

#[derive(Clone, Debug, Default)]
struct Movement {
    income: i64,
    expenses: i64,
    contributions: i64,
    releases: i64,
    goal_payments: i64,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Point {
    pub from: String,
    pub through: String,
    pub label: String,
    pub end_label: String,
    pub income: i64,
    pub expenses: i64,
    pub contributions: i64,
    pub releases: i64,
    pub cash: i64,
    pub savings: i64,
}

pub fn build(state: &AppState, range: Range) -> PouchResult<Vec<Point>> {
    if range.from > range.as_of {
        return Ok(Vec::new());
    }
    let mut ledger = BTreeMap::<Date, Movement>::new();
    for item in state.income.iter().filter(|item| item.date <= range.as_of) {
        let day = ledger.entry(item.date).or_default();
        day.income = total(day.income, item.amount.hundredths())?;
    }
    for (date, record) in state.days.range(..=range.as_of) {
        let day = ledger.entry(*date).or_default();
        for item in &record.purchases {
            day.expenses = total(day.expenses, item.amount.hundredths())?;
            if item.funded_by_goal {
                day.goal_payments = total(day.goal_payments, item.amount.hundredths())?;
            }
        }
    }
    for item in state
        .allocations
        .iter()
        .filter(|item| item.date <= range.as_of)
    {
        let day = ledger.entry(item.date).or_default();
        if item.amount >= 0 {
            day.contributions = total(day.contributions, item.amount)?;
        } else {
            day.releases = total(day.releases, -item.amount)?;
        }
    }
    let mut cash = 0;
    let mut savings = 0;
    let mut records = ledger.into_iter().peekable();
    while records.peek().is_some_and(|(date, _)| *date < range.from) {
        if let Some((_, movement)) = records.next() {
            advance(&mut cash, &mut savings, &movement)?;
        }
    }
    let length = range.from.days_until(range.as_of) + 1;
    let mut start = range.from;
    let mut points = Vec::new();
    while start <= range.as_of {
        let end = if length <= 90 {
            start
        } else if length <= 730 {
            start.add_days(6)?.min(range.as_of)
        } else {
            calendar::month_end_exclusive(start, state.preferences.calendar)?
                .add_days(-1)?
                .min(range.as_of)
        };
        let mut movement = Movement::default();
        while records.peek().is_some_and(|(date, _)| *date <= end) {
            if let Some((_, next)) = records.next() {
                advance(&mut cash, &mut savings, &next)?;
                movement.income = total(movement.income, next.income)?;
                movement.expenses = total(movement.expenses, next.expenses)?;
                movement.contributions = total(movement.contributions, next.contributions)?;
                movement.releases = total(movement.releases, next.releases)?;
            }
        }
        points.push(Point {
            from: start.iso()?,
            through: end.iso()?,
            label: label(state, start)?,
            end_label: label(state, end)?,
            income: movement.income,
            expenses: movement.expenses,
            contributions: movement.contributions,
            releases: movement.releases,
            cash,
            savings: savings.max(0),
        });
        start = end.add_days(1)?;
    }
    Ok(points)
}

fn advance(cash: &mut i64, savings: &mut i64, movement: &Movement) -> PouchResult<()> {
    *cash = total(total(*cash, movement.income)?, -movement.expenses)?;
    *savings = total(
        total(total(*savings, movement.contributions)?, -movement.releases)?,
        -movement.goal_payments,
    )?;
    Ok(())
}
