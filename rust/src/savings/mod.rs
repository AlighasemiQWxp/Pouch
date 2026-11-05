use crate::{AppState, Date, PouchResult, budget::total, models::SavingsAllocation};

fn raw_balance(state: &AppState, date: Date) -> PouchResult<i64> {
    let allocated = state
        .allocations
        .iter()
        .filter(|item| item.date <= date)
        .try_fold(0, |sum, item| total(sum, item.amount))?;
    let payments = state.days.range(..=date).try_fold(0, |sum, (date, day)| {
        day.purchases
            .iter()
            .filter(|purchase| {
                purchase.funded_by_goal
                    || state
                        .financial_metadata
                        .savings_purchases
                        .contains(&purchase_key(*date, &purchase.id))
            })
            .try_fold(sum, |sum, item| total(sum, item.amount.hundredths()))
    })?;
    total(allocated, -payments)
}

pub fn recorded_balance(state: &AppState, date: Date) -> PouchResult<i64> {
    Ok(raw_balance(state, date)?.max(0))
}

pub fn balance(state: &AppState, date: Date) -> PouchResult<i64> {
    Ok(crate::budget::funding(state, date)?.savings)
}

pub fn essential(state: &AppState, date: Date) -> PouchResult<i64> {
    Ok(crate::budget::funding(state, date)?.essential)
}

pub fn reconcile(state: &mut AppState, date: Date) -> PouchResult<()> {
    let through = state
        .allocations
        .iter()
        .map(|item| item.date)
        .max()
        .unwrap_or(date)
        .max(date);
    rebuild_from(state, date, through)
}

fn reconcile_at(state: &mut AppState, date: Date) -> PouchResult<()> {
    let period = match crate::periods::at(state, date) {
        Ok(period) => period,
        Err(crate::PouchError::MissingPeriod) => return Ok(()),
        Err(error) => return Err(error),
    };
    state
        .allocations
        .retain(|item| item.date != date || item.period_id != period.id);
    let raw = raw_balance(state, date)?;
    let current = raw.max(0);
    let funding = crate::budget::funding(state, date)?;
    let available = (funding.cash - funding.reserved).max(0);
    let contributed = state
        .allocations
        .iter()
        .filter(|item| item.period_id == period.id && item.date <= date)
        .try_fold(0, |sum, item| total(sum, item.amount))?;
    let payments = state
        .days
        .range(period.start..=date)
        .try_fold(0, |sum, (date, day)| {
            day.purchases
                .iter()
                .filter(|item| {
                    item.funded_by_goal
                        || state
                            .financial_metadata
                            .savings_purchases
                            .contains(&purchase_key(*date, &item.id))
                })
                .try_fold(sum, |sum, item| total(sum, item.amount.hundredths()))
        })?;
    let opening = if period.start > state.start_date {
        recorded_balance(state, period.start.add_days(-1)?)?
    } else {
        0
    };
    let contributed = contributed.max((payments - opening).max(0));
    let minimum = crate::budget::plan_at(state, date).savings.hundredths();
    let target = total(current, (minimum - contributed).max(0))?;
    let adjustment = target.min(available) - raw;
    if adjustment != 0 {
        state.allocations.push(SavingsAllocation {
            period_id: period.id,
            date,
            amount: adjustment,
        });
    }
    Ok(())
}

pub(crate) fn rebuild_from(state: &mut AppState, from: Date, through: Date) -> PouchResult<()> {
    let mut dates = std::collections::BTreeSet::from([from, through]);
    dates.extend(state.allocations.iter().map(|item| item.date));
    dates.extend(state.plans.iter().map(|item| item.effective));
    dates.extend(state.periods.iter().map(|period| period.start));
    dates.extend(state.income.iter().map(|item| item.date));
    dates.extend(state.days.keys().copied());
    state
        .allocations
        .retain(|item| item.date < from || item.date > through);
    for date in dates.range(from..=through) {
        reconcile_at(state, *date)?;
    }
    Ok(())
}

pub fn purchase_key(date: Date, id: &str) -> String {
    format!("{}/{}", date.day_offset(), id)
}

pub fn validate_goal_assignments(state: &AppState, date: Date) -> PouchResult<()> {
    let assigned = state
        .financial_metadata
        .goal_allocations
        .iter()
        .filter(|(id, _)| {
            state
                .planned
                .iter()
                .any(|item| &item.id == *id && item.status == crate::models::PlannedStatus::Pending)
        })
        .try_fold(0, |sum, (_, amount)| total(sum, *amount))?;
    if assigned > balance(state, date)? {
        return Err(crate::PouchError::InvalidEntry);
    }
    Ok(())
}
