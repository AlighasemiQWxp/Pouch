use crate::{AppState, Date, Money, PouchError, PouchResult, models::BudgetPlan};

pub use crate::models::BudgetPeriod as Period;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BudgetSummary {
    pub date: Date,
    pub period_end: Date,
    pub days_remaining: i32,
    pub carry: i64,
    pub daily: i64,
    pub spent: i64,
    pub remaining: i64,
    pub income: i64,
    pub required_expenses: i64,
    pub savings: i64,
    pub funds: i64,
    pub reserved: i64,
    pub funded_expenses: i64,
    pub recommendation: i64,
    pub shortfall: i64,
}

#[derive(Clone, Debug)]
pub struct Funding {
    pub cash: i64,
    pub reserved: i64,
    pub essential: i64,
    pub savings: i64,
    pub free: i64,
}

pub fn period_at(state: &AppState, date: Date) -> PouchResult<Period> {
    crate::periods::at(state, date)
}

pub fn plan_at(state: &AppState, date: Date) -> BudgetPlan {
    let period_id = period_at(state, date)
        .map(|period| period.id)
        .unwrap_or_default();
    state
        .plans
        .iter()
        .filter(|plan| plan.period_id == period_id && plan.effective <= date)
        .max_by_key(|plan| plan.effective)
        .cloned()
        .unwrap_or(BudgetPlan {
            period_id,
            effective: date,
            savings: Money::default(),
        })
}

pub fn save_plan(state: &mut AppState, plan: BudgetPlan) -> PouchResult<()> {
    let plan_date = plan.effective;
    let period = period_at(state, plan.effective)?;
    if plan.period_id != period.id {
        return Err(PouchError::InvalidPeriod);
    }
    if let Some(existing) = state
        .plans
        .iter_mut()
        .find(|item| item.period_id == plan.period_id && item.effective == plan.effective)
    {
        *existing = plan;
    } else {
        state.plans.push(plan);
    }
    state.plans.sort_by_key(|plan| plan.effective);
    let today = Date::from_naive_date(chrono::Local::now().date_naive())?;
    if plan_date <= today {
        crate::savings::reconcile(state, plan_date)?;
    }
    Ok(())
}

pub fn remove_plan(state: &mut AppState, effective: Date) -> PouchResult<()> {
    let index = state
        .plans
        .iter()
        .position(|plan| plan.effective == effective)
        .ok_or(PouchError::InvalidEntry)?;
    let today = Date::from_naive_date(chrono::Local::now().date_naive())?;
    let mut next = state.clone();
    next.plans.remove(index);
    if effective <= today {
        crate::savings::rebuild_from(&mut next, effective, today)?;
    }
    next.validate()?;
    *state = next;
    Ok(())
}

pub fn income_between(state: &AppState, start: Date, end: Date) -> PouchResult<i64> {
    state
        .income
        .iter()
        .filter(|item| item.date >= start && item.date < end)
        .try_fold(0, |sum, item| total(sum, item.amount.hundredths()))
}

pub fn income_for_period(state: &AppState, period_id: &str, through: Date) -> PouchResult<i64> {
    state
        .income
        .iter()
        .filter(|item| {
            item.date <= through
                && crate::periods::context::income_period(state, &item.id, item.date)
                    == Some(period_id)
        })
        .try_fold(0, |sum, item| total(sum, item.amount.hundredths()))
}

pub fn spent(state: &AppState, start: Date, end: Date) -> PouchResult<i64> {
    state.days.range(start..end).try_fold(0, |sum, (_, day)| {
        day.purchases.iter().try_fold(sum, |sum, purchase| {
            total(sum, purchase.amount.hundredths())
        })
    })
}

pub fn cash(state: &AppState, date: Date) -> PouchResult<i64> {
    let end = date.add_days(1)?;
    if end <= state.start_date {
        return Ok(0);
    }
    total(
        income_between(state, state.start_date, end)?,
        -spent(state, state.start_date, end)?,
    )
}

pub fn funding(state: &AppState, date: Date) -> PouchResult<Funding> {
    let horizon = period_at(state, date)
        .map(|period| period.end)
        .unwrap_or(date);
    let pending = crate::expenses::outstanding(state, date, horizon)?;
    let reserved = pending
        .iter()
        .try_fold(0, |sum, item| total(sum, item.amount.hundredths()))?;
    let essential = pending
        .iter()
        .filter(|item| item.essential_id.is_some())
        .try_fold(0, |sum, item| total(sum, item.amount.hundredths()))?;
    let cash = cash(state, date)?;
    let savings = crate::savings::recorded_balance(state, date)?.min((cash - reserved).max(0));
    let free = total(total(cash, -reserved)?, -savings)?;
    Ok(Funding {
        cash,
        reserved,
        essential,
        savings,
        free,
    })
}

pub fn recommend(state: &AppState, date: Date) -> PouchResult<BudgetSummary> {
    let period = period_at(state, date);
    let funding = funding(state, date)?;
    let (end, count, start) = match period {
        Ok(period) => (period.end, date.days_until(period.end), period.start),
        Err(PouchError::MissingPeriod) => (date.add_days(1)?, 0, date),
        Err(error) => return Err(error),
    };
    let spent_today = spent(state, date, date.add_days(1)?)?;
    let linked: std::collections::BTreeSet<&str> = state
        .planned
        .iter()
        .filter(|item| item.paid_date == Some(date))
        .filter_map(|item| item.purchase_id.as_deref())
        .collect();
    let discretionary = state
        .days
        .get(&date)
        .into_iter()
        .flat_map(|day| &day.purchases)
        .filter(|purchase| !linked.contains(purchase.id.as_str()))
        .try_fold(0, |sum, item| total(sum, item.amount.hundredths()))?;
    let daily = if count > 0 {
        total(funding.free, discretionary)?
            .div_euclid(i64::from(count))
            .max(0)
    } else {
        0
    };
    let carry = if start > state.start_date {
        funding_before(state, start)?.free
    } else {
        0
    };
    Ok(BudgetSummary {
        date,
        period_end: end.add_days(-1)?,
        days_remaining: count,
        carry,
        daily,
        spent: spent_today,
        remaining: funding.free,
        income: match period_at(state, date) {
            Ok(period) => income_for_period(state, &period.id, date)?,
            Err(_) => income_between(state, start, date.add_days(1)?)?,
        },
        required_expenses: funding.essential,
        savings: funding.savings,
        funds: total(funding.cash, -funding.savings)?,
        reserved: funding.reserved,
        funded_expenses: funding.cash.max(0).min(funding.reserved),
        recommendation: (daily - discretionary).max(0),
        shortfall: (-funding.free).max(0),
    })
}

pub fn funding_before(state: &AppState, date: Date) -> PouchResult<Funding> {
    if date <= state.start_date {
        return Ok(Funding {
            cash: 0,
            reserved: 0,
            essential: 0,
            savings: 0,
            free: 0,
        });
    }
    funding(state, date.add_days(-1)?)
}

pub(crate) fn total(left: i64, right: i64) -> PouchResult<i64> {
    left.checked_add(right)
        .filter(|value| value.unsigned_abs() <= 9_007_199_254_740_991)
        .ok_or(PouchError::TotalTooLarge)
}
