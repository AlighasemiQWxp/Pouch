use crate::{
    AppState, Date, PouchError, PouchResult,
    budget::{Period, plan_at},
    calendar,
    models::{PlannedKind, PlannedStatus},
};

pub fn reservation(state: &AppState, period: Period) -> PouchResult<i64> {
    if !period.funded {
        return Ok(0);
    }
    let saved = balance_before(state, period.start)?;
    desired(
        state,
        period.start,
        period.end,
        saved,
        state.plans[period.plan_index].monthly_savings.hundredths(),
    )
}

pub fn balance(state: &AppState, date: Date) -> PouchResult<i64> {
    balance_before(state, date.add_days(1)?)
}

pub(crate) fn balance_before(state: &AppState, through: Date) -> PouchResult<i64> {
    if through <= state.start_date {
        return Ok(0);
    }
    let mut saved = 0_i64;
    let mut cursor = state.start_date;
    for (index, income) in state.income.iter().enumerate() {
        if income.date >= through {
            break;
        }
        saved = (saved - goal_payments(state, cursor, income.date)?).max(0);
        let end = match state.income.get(index + 1) {
            Some(next) => next.date,
            None => calendar::add_months_anchored(income.date, 1, state.preferences.calendar)?,
        };
        let reserve = desired(
            state,
            income.date,
            end,
            saved,
            plan_at(state, income.date).monthly_savings.hundredths(),
        )?;
        let required = essential(state, income.date)?;
        let spent = crate::budget::spent(state, income.date, end.min(through))?;
        let pending = state
            .planned
            .iter()
            .filter(|item| {
                item.kind == PlannedKind::Expense
                    && item.status == PlannedStatus::Pending
                    && item.date >= income.date
                    && item.date < end
            })
            .try_fold(0, |sum, item| total(sum, item.amount.hundredths()))?;
        let available = (income.amount.hundredths() - required - spent - pending).max(0);
        saved = total(saved, reserve.min(available))?;
        cursor = income.date;
    }
    let saved = (saved - goal_payments(state, cursor, through)?).max(0);
    let income = state
        .income
        .iter()
        .filter(|item| item.date < through)
        .try_fold(0, |sum, item| total(sum, item.amount.hundredths()))?;
    let essentials = state
        .income
        .iter()
        .filter(|item| item.date < through)
        .try_fold(0, |sum, item| total(sum, essential(state, item.date)?))?;
    let spent = crate::budget::spent(state, state.start_date, through)?;
    let paid = goal_payments(state, state.start_date, through)?;
    let horizon = match state.income.iter().rev().find(|item| item.date < through) {
        Some(item) => {
            calendar::add_months_anchored(item.date, 1, state.preferences.calendar)?.max(through)
        }
        None => through,
    };
    let pending = state
        .planned
        .iter()
        .filter(|item| {
            item.kind == PlannedKind::Expense
                && item.status == PlannedStatus::Pending
                && item.date < horizon
        })
        .try_fold(0, |sum, item| total(sum, item.amount.hundredths()))?;
    Ok(saved.min((income - essentials - spent - paid - pending).max(0)))
}

pub fn essential(state: &AppState, date: Date) -> PouchResult<i64> {
    plan_at(state, date)
        .expenses
        .iter()
        .try_fold(0, |sum, item| total(sum, item.amount.hundredths()))
}

fn goal_payments(state: &AppState, start: Date, end: Date) -> PouchResult<i64> {
    state.days.range(start..end).try_fold(0, |sum, (_, day)| {
        day.purchases
            .iter()
            .filter(|item| item.funded_by_goal)
            .try_fold(sum, |sum, item| total(sum, item.amount.hundredths()))
    })
}

fn desired(state: &AppState, start: Date, end: Date, saved: i64, minimum: i64) -> PouchResult<i64> {
    let length = i64::from(start.days_until(end));
    if length <= 0 {
        return Err(PouchError::InvalidDate);
    }
    let mut goals: Vec<_> = state
        .planned
        .iter()
        .filter(|item| {
            item.kind == PlannedKind::Goal
                && (item.status == PlannedStatus::Pending
                    || item.paid_date.is_some_and(|date| date >= start))
        })
        .collect();
    goals.sort_by(|a, b| a.date.cmp(&b.date).then_with(|| a.id.cmp(&b.id)));
    let mut target = 0;
    let mut reserve = minimum;
    for goal in goals {
        target = total(target, goal.amount.hundredths())?;
        let days = i64::from(start.days_until(goal.date).saturating_add(1)).max(1);
        let needed = (target - saved).max(0);
        let amount =
            (i128::from(needed) * i128::from(length) + i128::from(days) - 1) / i128::from(days);
        reserve = reserve.max(
            i64::try_from(amount.min(i128::from(needed))).map_err(|_| PouchError::TotalTooLarge)?,
        );
    }
    Ok(reserve)
}

fn total(left: i64, right: i64) -> PouchResult<i64> {
    left.checked_add(right)
        .filter(|value| *value <= 9_007_199_254_740_991)
        .ok_or(PouchError::TotalTooLarge)
}
