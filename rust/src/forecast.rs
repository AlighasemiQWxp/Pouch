use crate::{
    AppState, Date, Money, PouchError, PouchResult,
    budget::{period_at, plan_at},
    models::{PlannedKind, PlannedStatus},
};

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct FinancialForecast {
    pub controllable_spending: i64,
    pub essential_expenses: i64,
    pub configured_savings: i64,
    pub extra_days: Option<i32>,
    pub faster_days: Option<i32>,
    pub monthly_income: i64,
    pub daily_allowance: i64,
    pub required_income: Option<i64>,
    pub daily_limit: i64,
    pub monthly_saving: Option<i64>,
    pub income_gap: Option<i64>,
    pub spending_reduction: i64,
    pub allocated: i64,
    pub remaining: i64,
    pub completion_days: Option<i32>,
    pub completion_date: Option<String>,
    pub on_track: bool,
    pub overdue: bool,
    pub cycle_days: i32,
    pub contribution: i64,
}

pub fn forecast(
    state: &AppState,
    as_of: Date,
    selected_id: &str,
    daily_allowance: Option<Money>,
) -> PouchResult<FinancialForecast> {
    forecast_mode(state, as_of, selected_id, daily_allowance, true)
}

pub fn forecast_mode(
    state: &AppState,
    as_of: Date,
    selected_id: &str,
    daily_allowance: Option<Money>,
    recommended: bool,
) -> PouchResult<FinancialForecast> {
    forecast_plan(
        state,
        as_of,
        selected_id,
        daily_allowance,
        recommended,
        false,
        false,
    )
}

pub fn preview(
    state: &AppState,
    as_of: Date,
    selected_id: &str,
    recommended: bool,
    income_required: bool,
) -> PouchResult<FinancialForecast> {
    let income_required = recommended && income_required;
    let mut result = forecast_plan(
        state,
        as_of,
        selected_id,
        None,
        recommended,
        income_required,
        true,
    )?;
    if recommended {
        let current = forecast_mode(state, as_of, selected_id, None, false)?;
        result.faster_days = current
            .completion_days
            .zip(result.completion_days)
            .map(|(current, proposed)| current - proposed);
    }
    Ok(result)
}

fn forecast_plan(
    state: &AppState,
    as_of: Date,
    selected_id: &str,
    daily_allowance: Option<Money>,
    recommended: bool,
    income_required: bool,
    simplify: bool,
) -> PouchResult<FinancialForecast> {
    let selected = state
        .planned
        .iter()
        .find(|item| item.id == selected_id && item.status == PlannedStatus::Pending)
        .ok_or(PouchError::InvalidEntry)?;
    let period = period_at(state, as_of)?;
    let length = i64::from(period.start.days_until(period.end)).max(1);
    let plan = plan_at(state, as_of);
    let essential = crate::savings::essential(state, as_of)?;
    let income = match period.income_index {
        Some(index) if period.funded => state.income[index].amount.hundredths(),
        _ => 0,
    };
    let spent = crate::budget::spent(state, period.start, as_of.add_days(1)?)?;
    let elapsed = i64::from(period.start.days_until(as_of).saturating_add(1)).max(1);
    let daily = match daily_allowance {
        Some(amount) => amount.hundredths(),
        None if spent > 0 => ceiling(spent, 1, elapsed)?,
        None => crate::budget::recommend(state, as_of)?.recommendation,
    };
    let living = ceiling(daily, length, 1)?;
    let saved = crate::savings::balance(state, as_of)?;
    let saved_before = crate::savings::balance_before(state, period.start)?;
    let current_saved = (saved - saved_before).max(0);
    let days_left = i64::from(as_of.days_until(period.end)).max(0);
    let summary = crate::budget::recommend(state, as_of)?;
    let expense_pool = summary
        .funds
        .max(0)
        .min((income - essential - spent - current_saved - ceiling(daily, days_left, 1)?).max(0));
    let mut items: Vec<_> = state
        .planned
        .iter()
        .filter(|item| item.status == PlannedStatus::Pending)
        .collect();
    items.sort_by(|a, b| a.date.cmp(&b.date).then_with(|| a.id.cmp(&b.id)));
    let mut goal_total = 0;
    let mut expense_total = 0;
    let mut goal_rate = plan.monthly_savings.hundredths();
    let mut expense_rate = 0;
    let mut deadline_possible = true;
    let mut selected_remaining = 0;
    let mut selected_cumulative = 0;
    let mut selected_rate = None;
    let mut selected_allocated = 0;
    for item in items {
        let (total, pool, rate) = match item.kind {
            PlannedKind::Goal => (&mut goal_total, saved, &mut goal_rate),
            PlannedKind::Expense => (&mut expense_total, expense_pool, &mut expense_rate),
        };
        let earlier = *total;
        *total = add(*total, item.amount.hundredths())?;
        let allocated = (pool - earlier).max(0).min(item.amount.hundredths());
        let remaining = (*total - pool).max(0);
        let days = i64::from(as_of.days_until(item.date)).max(0);
        let needed = if remaining == 0 {
            Some(0)
        } else if days > 0 {
            Some(ceiling(remaining, length, days)?)
        } else {
            None
        };
        if let Some(needed) = needed {
            *rate = (*rate).max(needed);
        } else {
            deadline_possible = false;
            *rate = (*rate).max(remaining);
        }
        if item.id == selected_id {
            selected_allocated = allocated;
            selected_remaining = item.amount.hundredths() - allocated;
            selected_cumulative = remaining;
            selected_rate = needed;
        }
    }
    let commitments = add(goal_rate, expense_rate)?;
    let required = add(add(essential, living)?, commitments)?;
    let required_income = if deadline_possible {
        Some(required)
    } else {
        None
    };
    let proposed_daily = if simplify && recommended && !income_required {
        ceiling(daily, 9, 10)?
    } else {
        daily
    };
    let projected_income = if income_required {
        required_income.unwrap_or(income)
    } else {
        income
    };
    let available = (projected_income - essential - ceiling(proposed_daily, length, 1)?).max(0);
    let available_capacity = match selected.kind {
        PlannedKind::Goal => (available - expense_rate).max(0),
        PlannedKind::Expense => (available - goal_rate).max(0),
    };
    let capacity = if income_required && required_income.is_none() {
        0
    } else if recommended {
        available_capacity
    } else {
        match selected.kind {
            PlannedKind::Goal => available_capacity.min(plan.monthly_savings.hundredths()),
            PlannedKind::Expense => (available - plan.monthly_savings.hundredths()).max(0),
        }
    };
    let completion_days = if selected_cumulative == 0 {
        Some(0)
    } else if capacity > 0 {
        i32::try_from(ceiling(selected_cumulative, length, capacity)?).ok()
    } else {
        None
    };
    let completion_date =
        completion_days.and_then(|days| as_of.add_days(days).and_then(Date::iso).ok());
    let completion_days = completion_days.filter(|_| completion_date.is_some());
    let daily_limit = ((income - essential - commitments).max(0) / length)
        .min(daily)
        .min(summary.recommendation);
    Ok(FinancialForecast {
        controllable_spending: ceiling(proposed_daily, length, 1)?,
        essential_expenses: essential,
        configured_savings: plan.monthly_savings.hundredths(),
        extra_days: completion_days.map(|days| {
            if selected_remaining == 0 {
                return 0;
            }
            days.saturating_sub(as_of.days_until(selected.date)).max(0)
        }),
        faster_days: None,
        monthly_income: income,
        daily_allowance: proposed_daily,
        required_income,
        daily_limit: if simplify {
            proposed_daily
        } else {
            daily_limit
        },
        monthly_saving: selected_rate,
        income_gap: required_income.map(|required| (required - income).max(0)),
        spending_reduction: if simplify {
            daily - proposed_daily
        } else {
            (daily - daily_limit).max(0)
        },
        allocated: selected_allocated,
        remaining: selected_remaining,
        completion_days,
        completion_date,
        on_track: completion_days
            .is_some_and(|days| days <= as_of.days_until(selected.date).max(0)),
        overdue: selected_remaining > 0 && selected.date <= as_of,
        cycle_days: i32::try_from(length).map_err(|_| PouchError::InvalidDate)?,
        contribution: capacity,
    })
}

fn add(left: i64, right: i64) -> PouchResult<i64> {
    left.checked_add(right)
        .filter(|amount| *amount <= 9_007_199_254_740_991)
        .ok_or(PouchError::TotalTooLarge)
}

fn ceiling(amount: i64, multiplier: i64, divisor: i64) -> PouchResult<i64> {
    let value = (i128::from(amount) * i128::from(multiplier) + i128::from(divisor) - 1)
        / i128::from(divisor);
    i64::try_from(value)
        .ok()
        .filter(|value| *value <= 9_007_199_254_740_991)
        .ok_or(PouchError::TotalTooLarge)
}

#[cfg(test)]
mod tests {
    use super::forecast;
    use crate::{
        AppState, Date, Money,
        models::{Calendar, Category, IncomeEntry, PlannedItem, PlannedKind, PlannedStatus},
    };

    fn amount(value: i64) -> Money {
        Money::from_hundredths(value).expect("valid amount")
    }

    #[test]
    fn recommendation_preserves_allocations_and_essential_costs() {
        let mut state = state(PlannedKind::Goal);
        state.income.push(IncomeEntry {
            id: "salary".into(),
            date: state.start_date,
            amount: amount(70_000),
        });
        let before = serde_json::to_string(&state).expect("state");
        let current =
            super::preview(&state, state.start_date, "target", false, false).expect("current");
        let proposed =
            super::preview(&state, state.start_date, "target", true, false).expect("proposed");
        assert_eq!(current.allocated, proposed.allocated);
        assert_eq!(current.remaining, proposed.remaining);
        assert_eq!(current.essential_expenses, proposed.essential_expenses);
        assert_eq!(current.monthly_income, proposed.monthly_income);
        assert!(proposed.daily_allowance <= current.daily_allowance);
        assert!(proposed.contribution >= current.contribution);
        assert_eq!(serde_json::to_string(&state).expect("state"), before);
    }

    #[test]
    fn required_income_is_a_preview_that_protects_earlier_commitments() {
        let mut state = state(PlannedKind::Goal);
        let mut earlier = state.planned[0].clone();
        earlier.id = "earlier".into();
        earlier.date = state.start_date.add_days(10).expect("date");
        state.planned.push(earlier);
        let current =
            super::preview(&state, state.start_date, "target", false, false).expect("current");
        let required =
            super::preview(&state, state.start_date, "target", true, true).expect("required");
        assert_eq!(required.monthly_income, 0);
        assert_eq!(required.allocated, current.allocated);
        assert_eq!(required.daily_allowance, current.daily_allowance);
        assert!(
            required.required_income.expect("income") > required.monthly_saving.expect("saving")
        );
        assert!(required.on_track);
        state.planned[0].date = state.start_date;
        let overdue =
            super::preview(&state, state.start_date, "target", true, true).expect("overdue");
        assert_eq!(overdue.required_income, None);
        assert_eq!(overdue.completion_date, None);
    }

    #[test]
    fn personal_savings_follow_the_configured_contribution() {
        let mut state = state(PlannedKind::Goal);
        state.income.push(IncomeEntry {
            id: "salary".into(),
            date: state.start_date,
            amount: amount(70_000),
        });
        state.plans[0].monthly_savings = amount(5_000);
        let personal = super::forecast_mode(
            &state,
            state.start_date,
            "target",
            Some(amount(1000)),
            false,
        )
        .expect("personal forecast");
        let recommended =
            super::forecast_mode(&state, state.start_date, "target", Some(amount(1000)), true)
                .expect("recommended forecast");
        assert_eq!(personal.contribution, 5_000);
        assert!(recommended.contribution > personal.contribution);
        assert!(personal.completion_days > recommended.completion_days);
        state.plans[0].monthly_savings = amount(0);
        let zero = super::forecast_mode(
            &state,
            state.start_date,
            "target",
            Some(amount(1000)),
            false,
        )
        .expect("zero contribution");
        assert_eq!(zero.completion_date, None);
    }

    #[test]
    fn personal_contribution_cannot_exceed_affordable_surplus() {
        let mut state = state(PlannedKind::Goal);
        state.income.push(IncomeEntry {
            id: "salary".into(),
            date: state.start_date,
            amount: amount(70_000),
        });
        state.plans[0].monthly_savings = amount(100_000);
        let result = super::forecast_mode(
            &state,
            state.start_date,
            "target",
            Some(amount(1000)),
            false,
        )
        .expect("constrained forecast");
        assert_eq!(result.contribution, 39_000);
    }

    fn state(kind: PlannedKind) -> AppState {
        let start = Date::parse_iso("2024-01-01").expect("valid date");
        let mut state = AppState::fresh(start);
        state.preferences.calendar = Calendar::Gregorian;
        state.planned.push(PlannedItem {
            id: "target".into(),
            description: "Target".into(),
            amount: amount(100_000),
            category: Category::Other,
            kind,
            date: Date::parse_iso("2024-03-01").expect("valid date"),
            status: PlannedStatus::Pending,
            paid_date: None,
            purchase_id: None,
        });
        state
    }

    #[test]
    fn unfunded_forecasts_show_requirements_without_inventing_completion() {
        for kind in [PlannedKind::Goal, PlannedKind::Expense] {
            let state = state(kind);
            let result = forecast(&state, state.start_date, "target", Some(amount(1000)))
                .expect("valid forecast");
            assert_eq!(result.monthly_income, 0);
            assert_eq!(result.allocated, 0);
            assert_eq!(result.required_income, Some(82_667));
            assert_eq!(result.completion_days, None);
            assert_eq!(result.completion_date, None);
        }
    }

    #[test]
    fn completion_date_matches_remaining_days_across_leap_day() {
        let mut state = state(PlannedKind::Goal);
        state.income.push(IncomeEntry {
            id: "salary".into(),
            date: state.start_date,
            amount: amount(50_000),
        });
        let result = forecast(&state, state.start_date, "target", Some(amount(1000)))
            .expect("valid forecast");
        let days = result.completion_days.expect("positive saving capacity");
        assert!(days > 59);
        assert_eq!(
            result.completion_date,
            Some(
                state
                    .start_date
                    .add_days(days)
                    .expect("valid date")
                    .iso()
                    .expect("ISO date")
            ),
        );
    }

    #[test]
    fn goals_do_not_each_receive_the_same_saved_money() {
        let mut state = state(PlannedKind::Goal);
        let mut second = state.planned[0].clone();
        second.id = "later".into();
        second.date = Date::parse_iso("2024-04-01").expect("valid date");
        state.planned.push(second);
        state.income.push(IncomeEntry {
            id: "salary".into(),
            date: state.start_date,
            amount: amount(70_000),
        });
        let first = forecast(&state, state.start_date, "target", Some(amount(1000)))
            .expect("valid forecast");
        let later = forecast(&state, state.start_date, "later", Some(amount(1000)))
            .expect("valid forecast");
        assert_eq!(later.allocated, 0);
        assert!(later.completion_days > first.completion_days);
        assert_eq!(later.required_income, first.required_income);
    }

    #[test]
    fn higher_living_costs_delay_completion_and_can_remove_capacity() {
        let mut state = state(PlannedKind::Expense);
        state.income.push(IncomeEntry {
            id: "salary".into(),
            date: state.start_date,
            amount: amount(70_000),
        });
        let lower = forecast(&state, state.start_date, "target", Some(amount(1000)))
            .expect("valid forecast");
        let higher = forecast(&state, state.start_date, "target", Some(amount(2000)))
            .expect("valid forecast");
        let impossible = forecast(&state, state.start_date, "target", Some(amount(3000)))
            .expect("valid forecast");
        assert!(higher.completion_days > lower.completion_days);
        assert_eq!(impossible.completion_days, None);
        assert_eq!(impossible.daily_limit, 0);
    }

    #[test]
    fn overdue_deadlines_do_not_produce_a_finite_required_income() {
        let mut state = state(PlannedKind::Expense);
        state.planned[0].date = state.start_date;
        let result = forecast(&state, state.start_date, "target", Some(amount(1000)))
            .expect("valid forecast");
        assert!(result.overdue);
        assert_eq!(result.required_income, None);
        assert_eq!(result.monthly_saving, None);
    }

    #[test]
    fn funded_expenses_are_ready_today_and_paid_items_are_not_forecast() {
        let mut state = state(PlannedKind::Expense);
        state.income.push(IncomeEntry {
            id: "salary".into(),
            date: state.start_date,
            amount: amount(200_000),
        });
        let result = forecast(&state, state.start_date, "target", Some(amount(1000)))
            .expect("valid forecast");
        assert_eq!(result.remaining, 0);
        assert_eq!(result.completion_days, Some(0));
        assert_eq!(result.completion_date, Some("2024-01-01".into()));
        state.planned[0].status = PlannedStatus::Paid;
        assert!(forecast(&state, state.start_date, "target", None).is_err());
    }

    #[test]
    fn earlier_deadlines_and_minimum_savings_are_protected() {
        let mut state = state(PlannedKind::Goal);
        state.planned[0].date = Date::parse_iso("2024-01-11").expect("valid date");
        let mut later = state.planned[0].clone();
        later.id = "later".into();
        later.date = Date::parse_iso("2024-05-01").expect("valid date");
        state.planned.push(later);
        state.plans[0].monthly_savings = amount(400_000);
        let result = forecast(&state, state.start_date, "later", Some(amount(1000)))
            .expect("valid forecast");
        assert_eq!(result.monthly_saving, Some(51_240));
        assert_eq!(result.required_income, Some(431_000));
    }

    #[test]
    fn preview_does_not_change_state_or_use_expected_income() {
        let mut state = state(PlannedKind::Goal);
        state
            .expected_income
            .push(crate::models::ExpectedIncomeEntry {
                id: "expected".into(),
                date: state.start_date,
                amount: amount(200_000),
            });
        let before = serde_json::to_string(&state).expect("serializable state");
        let result = forecast(&state, state.start_date, "target", Some(amount(1000)))
            .expect("valid forecast");
        assert_eq!(result.monthly_income, 0);
        assert_eq!(result.completion_date, None);
        assert_eq!(
            serde_json::to_string(&state).expect("serializable state"),
            before
        );
    }

    #[test]
    fn monthly_requirement_subtracts_registered_savings_and_is_zero_when_funded() {
        let mut state = state(PlannedKind::Goal);
        state.income.push(IncomeEntry {
            id: "salary".into(),
            date: state.start_date,
            amount: amount(70_000),
        });
        let result =
            forecast(&state, state.start_date, "target", Some(amount(1000))).expect("forecast");
        assert!(result.allocated > 0);
        assert_eq!(
            result.monthly_saving,
            Some(super::ceiling(result.remaining, 31, 60).expect("monthly requirement"))
        );
        state.income[0].amount = amount(200_000);
        state.plans[0].monthly_savings = amount(100_000);
        let funded =
            forecast(&state, state.start_date, "target", Some(amount(1000))).expect("forecast");
        assert_eq!(funded.remaining, 0);
        assert_eq!(funded.monthly_saving, Some(0));
        assert_eq!(funded.completion_days, Some(0));
    }
}
