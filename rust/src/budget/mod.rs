use chrono::Local;
use std::collections::BTreeSet;

use crate::{
    AppState, Date, Money, PouchError, PouchResult,
    calendar::{self, CalendarParts},
    models::{BudgetPlan, Calendar, PlannedKind, PlannedStatus},
};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Period {
    pub start: Date,
    pub end: Date,
    pub income_index: Option<usize>,
    pub funded: bool,
    pub plan_index: usize,
}

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
    pub recommendation: i64,
    pub shortfall: i64,
}

pub fn plan_at(state: &AppState, date: Date) -> &BudgetPlan {
    let index = state.plans.partition_point(|plan| plan.effective <= date);
    &state.plans[index.saturating_sub(1)]
}

pub fn save_plan(state: &mut AppState, mut plan: BudgetPlan) -> PouchResult<()> {
    plan.effective.to_naive_date()?;
    if plan.effective < state.start_date {
        return Err(PouchError::InvalidDate);
    }
    plan.calendar = state.preferences.calendar;
    if let Some(existing) = state
        .plans
        .iter_mut()
        .find(|item| item.effective == plan.effective)
    {
        *existing = plan;
    } else {
        state.plans.push(plan);
        state.plans.sort_by_key(|item| item.effective);
    }
    Ok(())
}

pub fn remove_plan(state: &mut AppState, effective: Date) -> PouchResult<()> {
    let today = Date::from_naive_date(Local::now().date_naive())?;
    if effective <= today {
        return Err(PouchError::InvalidEntry);
    }
    let Some(index) = state
        .plans
        .iter()
        .position(|plan| plan.effective == effective)
    else {
        return Err(PouchError::InvalidEntry);
    };
    if index == 0 {
        return Err(PouchError::InvalidEntry);
    }
    state.plans.remove(index);
    Ok(())
}

pub fn period_at(state: &AppState, date: Date) -> PouchResult<Period> {
    let plan_index = state
        .plans
        .partition_point(|plan| plan.effective <= date)
        .saturating_sub(1);
    let income_index = state.income.partition_point(|entry| entry.date <= date);
    if income_index == 0 {
        let (start, end) = cycle(date, 1, state.preferences.calendar)?;
        return Ok(Period {
            start,
            end,
            income_index: None,
            funded: false,
            plan_index,
        });
    }
    salary_period(state, date, income_index - 1, plan_index)
}

fn salary_period(
    state: &AppState,
    date: Date,
    index: usize,
    plan_index: usize,
) -> PouchResult<Period> {
    let income = &state.income[index];
    let next = state.income.get(index + 1);
    let period_calendar = state.preferences.calendar;
    let mut start = income.date;
    let mut end = match next {
        Some(next) => next.date,
        None => calendar::add_months_anchored(income.date, 1, period_calendar)?,
    };
    if next.is_some() || date < end {
        return Ok(Period {
            start,
            end,
            income_index: Some(index),
            funded: true,
            plan_index,
        });
    }

    let start_parts = calendar::parts(income.date, period_calendar)?;
    let date_parts = calendar::parts(date, period_calendar)?;
    let offset = month_difference(start_parts, date_parts).max(1);
    end = calendar::add_months_anchored(income.date, offset, period_calendar)?;
    if date < end {
        if offset > 1 {
            start = calendar::add_months_anchored(income.date, offset - 1, period_calendar)?;
        }
        return Ok(Period {
            start,
            end,
            income_index: Some(index),
            funded: false,
            plan_index,
        });
    }
    start = end;
    end = calendar::add_months_anchored(income.date, offset + 1, period_calendar)?;
    Ok(Period {
        start,
        end,
        income_index: Some(index),
        funded: false,
        plan_index,
    })
}

fn month_difference(start: CalendarParts, date: CalendarParts) -> i32 {
    (date.year - start.year) * 12 + date.month as i32 - start.month as i32
}

fn cycle(date: Date, payday: u8, calendar_type: Calendar) -> PouchResult<(Date, Date)> {
    let mut start = payday_in_month(date, payday, calendar_type)?;
    if date < start {
        let previous_month = calendar::month_start(date, calendar_type)?.add_days(-1)?;
        start = payday_in_month(previous_month, payday, calendar_type)?;
    }
    let next_month = calendar::month_end_exclusive(start, calendar_type)?;
    let end = payday_in_month(next_month, payday, calendar_type)?;
    Ok((start, end))
}

fn payday_in_month(date: Date, payday: u8, calendar_type: Calendar) -> PouchResult<Date> {
    let start = calendar::month_start(date, calendar_type)?;
    let end = calendar::month_end_exclusive(date, calendar_type)?;
    let month_length = start.days_until(end);
    start.add_days(i32::from(payday).min(month_length) - 1)
}

pub fn base(state: &AppState, date: Date) -> PouchResult<i64> {
    let period = period_at(state, date)?;
    let plan = &state.plans[period.plan_index];
    let salary = period_salary(state, &period);
    allowance_portion(state, plan, salary, period, date, date.add_days(1)?)
}

fn period_salary(state: &AppState, period: &Period) -> Money {
    match period.income_index {
        Some(index) if period.funded => state.income[index].amount,
        _ => Money::default(),
    }
}

fn period_net(
    state: &AppState,
    plan: &BudgetPlan,
    salary: Money,
    period: Period,
) -> PouchResult<i64> {
    let required = plan.expenses.iter().try_fold(0_i64, |sum, expense| {
        checked_total(sum, expense.amount.hundredths())
    })?;
    let savings = crate::savings::reservation(state, period)?;
    let income = salary.hundredths();
    Ok((income - checked_total(required, savings)?).max(0))
}

fn allowance_portion(
    state: &AppState,
    plan: &BudgetPlan,
    salary: Money,
    period: Period,
    start: Date,
    stop: Date,
) -> PouchResult<i64> {
    let length = period.start.days_until(period.end);
    let count = start.days_until(stop);
    if length <= 0 || count < 0 {
        return Err(PouchError::InvalidDate);
    }
    let net = period_net(state, plan, salary, period)?;
    let mut total = (net / i64::from(length))
        .checked_mul(i64::from(count))
        .ok_or(PouchError::TotalTooLarge)?;
    {
        let remainder = net % i64::from(length);
        let through_stop = i64::from(stop.days_until(period.start).saturating_neg()).min(remainder);
        let through_start =
            i64::from(start.days_until(period.start).saturating_neg()).min(remainder);
        total = checked_total(total, (through_stop - through_start).max(0))?;
    }
    Ok(total)
}

pub fn base_between(state: &AppState, start: Date, end: Date) -> PouchResult<i64> {
    if end < start {
        return Err(PouchError::InvalidDate);
    }
    let mut total = 0_i64;
    let mut cursor = start;
    while cursor < end {
        let period = period_at(state, cursor)?;
        let plan = &state.plans[period.plan_index];
        let mut stop = period.end.min(end);
        if let Some(next_plan) = state.plans.iter().find(|plan| plan.effective > cursor) {
            stop = stop.min(next_plan.effective);
        }
        if stop <= cursor {
            return Err(PouchError::InvalidState);
        }
        let salary = period_salary(state, &period);
        total = checked_total(
            total,
            allowance_portion(state, plan, salary, period, cursor, stop)?,
        )?;
        cursor = stop;
    }
    Ok(total)
}

pub fn allowance(state: &AppState, date: Date) -> PouchResult<i64> {
    base(state, date)
}

pub fn allowance_between(state: &AppState, start: Date, end: Date) -> PouchResult<i64> {
    base_between(state, start, end)
}

pub fn spent(state: &AppState, start: Date, end: Date) -> PouchResult<i64> {
    let mut total = 0_i64;
    for (date, day) in &state.days {
        if *date >= start && *date < end {
            for purchase in &day.purchases {
                if !purchase.funded_by_goal {
                    total = checked_total(total, purchase.amount.hundredths())?;
                }
            }
        }
    }
    Ok(total)
}

pub fn recommend(state: &AppState, date: Date) -> PouchResult<BudgetSummary> {
    let period = period_at(state, date)?;
    let plan = &state.plans[period.plan_index];
    let daily = allowance(state, date)?;
    let carry = checked_total(
        base_between(state, state.start_date, date)?,
        -spent(state, state.start_date, date)?,
    )?;
    let day = state.days.get(&date);
    let spent_today = day
        .into_iter()
        .flat_map(|day| day.purchases.iter())
        .filter(|purchase| !purchase.funded_by_goal)
        .try_fold(0_i64, |sum, purchase| {
            checked_total(sum, purchase.amount.hundredths())
        })?;
    let remaining = checked_total(checked_total(carry, daily)?, -spent_today)?;
    let income = period
        .income_index
        .map(|index| {
            if period.funded {
                state.income[index].amount.hundredths()
            } else {
                0
            }
        })
        .unwrap_or(0);
    let savings = crate::savings::reservation(state, period)?;
    let required = plan.expenses.iter().try_fold(0_i64, |sum, expense| {
        checked_total(sum, expense.amount.hundredths())
    })?;
    let count = date.days_until(period.end);
    if count <= 0 {
        return Err(PouchError::InvalidDate);
    }
    let pending: Vec<_> = state
        .planned
        .iter()
        .filter(|item| item.status == PlannedStatus::Pending && item.kind != PlannedKind::Goal)
        .collect();
    let reserved = pending
        .iter()
        .filter(|item| item.date < period.end)
        .try_fold(0_i64, |sum, item| {
            checked_total(sum, item.amount.hundredths())
        })?;
    let funds = checked_total(
        checked_total(carry, base_between(state, date, period.end)?)?,
        -spent(state, date, period.end)?,
    )?;
    let free = checked_total(funds, -reserved)?;
    let commitments = if income > 0 {
        (checked_total(required, savings)? - income).max(0)
    } else {
        0
    };
    let reserved_payments = state
        .planned
        .iter()
        .filter(|item| {
            item.kind != PlannedKind::Goal
                && item.status == PlannedStatus::Paid
                && item.paid_date == Some(date)
        })
        .filter_map(|item| {
            let purchase_id = item.purchase_id.as_deref()?;
            state
                .days
                .get(&date)?
                .purchases
                .iter()
                .find(|purchase| purchase.id == purchase_id)
        })
        .try_fold(0_i64, |sum, purchase| {
            checked_total(sum, purchase.amount.hundredths())
        })?;
    let discretionary_spent = spent_today - reserved_payments;
    let initial_daily_total = checked_total(free, discretionary_spent)?;
    let mut limit = div_floor(initial_daily_total, i64::from(count)) - discretionary_spent;
    let mut shortfall = commitments.max(-free);
    let later_dates: BTreeSet<Date> = pending
        .iter()
        .filter(|item| item.date >= period.end)
        .map(|item| item.date)
        .collect();
    for due_date in later_dates {
        let through_due = due_date.add_days(1)?;
        let future_reserve = pending
            .iter()
            .filter(|item| item.date <= due_date)
            .try_fold(0_i64, |sum, item| {
                checked_total(sum, item.amount.hundredths())
            })?;
        let future_funds = checked_total(
            base_between(state, period.end, through_due)?,
            -spent(state, period.end, through_due)?,
        )?;
        let reserve_gap = checked_total(future_reserve, -reserved)?;
        let required_now = checked_total(reserve_gap, -future_funds)?.max(0);
        let available_now =
            checked_total(checked_total(free, -required_now)?, discretionary_spent)?;
        limit = limit.min(div_floor(available_now, i64::from(count)) - discretionary_spent);
        shortfall = shortfall.max(required_now - free);
    }
    if commitments > 0 {
        limit = 0;
    }
    Ok(BudgetSummary {
        date,
        period_end: period.end.add_days(-1)?,
        days_remaining: count,
        carry,
        daily,
        spent: spent_today,
        remaining,
        income,
        required_expenses: required,
        savings,
        funds,
        reserved,
        recommendation: limit.max(0),
        shortfall: shortfall.max(0),
    })
}

fn div_floor(numerator: i64, denominator: i64) -> i64 {
    numerator.div_euclid(denominator)
}

fn checked_total(current: i64, additional: i64) -> PouchResult<i64> {
    let total = current
        .checked_add(additional)
        .ok_or(PouchError::TotalTooLarge)?;
    if total.unsigned_abs() > 9_007_199_254_740_991_u64 {
        return Err(PouchError::TotalTooLarge);
    }
    Ok(total)
}

#[cfg(test)]
mod tests {
    use chrono::Local;

    use super::{base, period_at, recommend, remove_plan, save_plan};
    use crate::{
        AppState, Date, Money,
        models::{
            Calendar, Category, DailyRecord, IncomeEntry, PlannedItem, PlannedKind, PlannedStatus,
            Purchase, RequiredExpense,
        },
    };

    #[test]
    fn effective_dated_budget_changes_can_be_scheduled_in_the_future() {
        let today = Date::from_naive_date(Local::now().date_naive()).expect("today is supported");
        let tomorrow = today.add_days(1).expect("tomorrow is supported");
        let mut state = AppState::fresh(today);
        state.preferences.calendar = Calendar::Jalali;
        let mut plan = state.plans[0].clone();
        plan.effective = tomorrow;
        plan.daily_budget = Money::from_hundredths(2500).expect("amount is valid");
        plan.calendar = Calendar::Gregorian;

        save_plan(&mut state, plan).expect("a future plan can be scheduled");

        assert_eq!(state.plans.len(), 2);
        assert_eq!(state.plans[1].effective, tomorrow);
        assert_eq!(state.plans[1].calendar, Calendar::Jalali);
    }

    #[test]
    fn scheduled_plan_can_be_removed_without_rewriting_history() {
        let today = Date::from_naive_date(Local::now().date_naive()).expect("today is supported");
        let tomorrow = today.add_days(1).expect("tomorrow is supported");
        let mut state = AppState::fresh(today);
        let mut plan = state.plans[0].clone();
        plan.effective = tomorrow;
        save_plan(&mut state, plan).expect("the future plan can be saved");

        remove_plan(&mut state, tomorrow).expect("the future plan can be removed");

        assert_eq!(state.plans.len(), 1);
        assert_eq!(state.plans[0].effective, today);
    }

    #[test]
    fn salary_cycles_use_the_calendar_preference() {
        let start = Date::parse_iso("2024-03-21").expect("the date is valid");
        let date = Date::parse_iso("2024-04-22").expect("the date is valid");
        let mut state = AppState::fresh(start);
        state.plans[0].calendar = Calendar::Gregorian;
        state.income.push(IncomeEntry {
            id: "salary".into(),
            date: start,
            amount: Money::from_hundredths(100_000).expect("amount is valid"),
        });
        state.preferences.calendar = Calendar::Jalali;

        let period = period_at(&state, date).expect("the salary period can be calculated");

        assert_eq!(period.start.iso().expect("date formats"), "2024-04-21");
    }

    #[test]
    fn monthly_expenses_and_savings_are_reserved_before_daily_allowance() {
        let start = Date::parse_iso("2024-01-01").expect("the date is valid");
        let mut state = AppState::fresh(start);
        state.preferences.calendar = Calendar::Gregorian;
        state.plans[0].expenses.push(RequiredExpense {
            id: "rent".into(),
            name: "Rent".into(),
            amount: Money::from_hundredths(3100).expect("amount is valid"),
        });
        state.plans[0].monthly_savings = Money::from_hundredths(3100).expect("amount is valid");
        state.income.push(IncomeEntry {
            id: "salary".into(),
            date: start,
            amount: Money::from_hundredths(31_000).expect("amount is valid"),
        });

        let allowance = base(&state, start).expect("the allowance can be calculated");

        assert_eq!(allowance, 800);
    }

    #[test]
    fn earlier_overspending_reduces_the_later_recommendation() {
        let start = Date::parse_iso("2024-01-01").expect("the date is valid");
        let next_day = Date::parse_iso("2024-01-02").expect("the date is valid");
        let mut state = AppState::fresh(start);
        state.preferences.calendar = Calendar::Gregorian;
        state.income.push(IncomeEntry {
            id: "salary".into(),
            date: state.start_date,
            amount: Money::from_hundredths(3100).expect("amount is valid"),
        });
        state.days.insert(
            start,
            DailyRecord {
                budget_override: None,
                purchases: vec![Purchase {
                    id: "purchase".into(),
                    description: "Lunch".into(),
                    amount: Money::from_hundredths(150).expect("amount is valid"),
                    category: Category::Food,
                    funded_by_goal: false,
                }],
            },
        );

        let summary = recommend(&state, next_day).expect("the day can be recommended");

        assert_eq!(summary.carry, -50);
        assert_eq!(summary.recommendation, 98);
        assert_eq!(summary.remaining, 50);
    }

    #[test]
    fn pending_expenses_reserve_funds_until_the_actual_payment_is_recorded() {
        let date = Date::parse_iso("2024-01-01").expect("the date is valid");
        let mut state = AppState::fresh(date);
        state.preferences.calendar = Calendar::Gregorian;
        state.income.push(IncomeEntry {
            id: "salary".into(),
            date: state.start_date,
            amount: Money::from_hundredths(3100).expect("amount is valid"),
        });
        state.planned.push(PlannedItem {
            id: "rent".into(),
            description: "Rent".into(),
            amount: Money::from_hundredths(1500).expect("amount is valid"),
            category: Category::Bills,
            kind: PlannedKind::Expense,
            date,
            status: PlannedStatus::Pending,
            paid_date: None,
            purchase_id: None,
        });

        let reserved = recommend(&state, date).expect("the budget can be calculated");
        assert_eq!(reserved.reserved, 1500);
        assert_eq!(reserved.recommendation, 51);

        crate::expenses::mark_paid(
            &mut state,
            "rent",
            "rent-payment".into(),
            date,
            Money::from_hundredths(900).expect("amount is valid"),
        )
        .expect("the actual payment is recorded");
        let paid = recommend(&state, date).expect("the paid budget can be calculated");
        assert_eq!(paid.reserved, 0);
        assert_eq!(paid.spent, 900);
    }

    #[test]
    fn legacy_allowances_and_overrides_do_not_invent_received_income() {
        let date = Date::parse_iso("2024-01-01").expect("valid date");
        let mut state = AppState::fresh(date);
        state.preferences.calendar = Calendar::Gregorian;
        state.plans[0].fallback_salary =
            Some(Money::from_hundredths(31_000).expect("valid amount"));
        state.plans[0].daily_budget = Money::from_hundredths(100).expect("valid amount");
        state.days.insert(
            date,
            DailyRecord {
                budget_override: Some(Money::from_hundredths(500).expect("valid amount")),
                purchases: Vec::new(),
            },
        );
        let summary = recommend(&state, date).expect("valid summary");
        assert_eq!(summary.income, 0);
        assert_eq!(summary.recommendation, 0);
    }

    #[test]
    fn a_goal_automatically_reduces_daily_spending_without_double_counting_savings() {
        let date = Date::parse_iso("2024-01-01").expect("valid date");
        let mut state = AppState::fresh(date);
        state.preferences.calendar = Calendar::Gregorian;
        state.income.push(IncomeEntry {
            id: "salary".into(),
            date,
            amount: Money::from_hundredths(31_000).expect("valid amount"),
        });
        state.plans[0].monthly_savings = Money::from_hundredths(3100).expect("valid amount");
        state.planned.push(PlannedItem {
            id: "car".into(),
            description: "Car".into(),
            amount: Money::from_hundredths(6200).expect("valid amount"),
            category: Category::Other,
            kind: PlannedKind::Goal,
            date: Date::parse_iso("2024-01-31").expect("valid date"),
            status: PlannedStatus::Pending,
            paid_date: None,
            purchase_id: None,
        });
        let summary = recommend(&state, date).expect("valid summary");
        assert_eq!(summary.savings, 6200);
        assert_eq!(summary.reserved, 0);
        assert_eq!(summary.recommendation, 800);
    }
}
