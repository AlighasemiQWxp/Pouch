use crate::{
    AppState, Date, PouchError, PouchResult,
    budget::{period_at, plan_at},
    models::{PlannedKind, PlannedStatus},
};

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct GoalForecast {
    pub id: String,
    pub periods: i32,
    pub required_monthly: Option<i64>,
    pub projected: i64,
    pub percent: i32,
    pub difference: Option<i64>,
    pub on_track: bool,
    pub completion_days: Option<i32>,
    pub daily_reduction: i64,
}

pub fn forecast(state: &AppState, as_of: Date) -> PouchResult<Vec<GoalForecast>> {
    let mut goals: Vec<_> = state
        .planned
        .iter()
        .filter(|item| item.kind == PlannedKind::Goal && item.status == PlannedStatus::Pending)
        .collect();
    goals.sort_by(|a, b| a.date.cmp(&b.date).then_with(|| a.id.cmp(&b.id)));
    let period = period_at(state, as_of)?;
    let length = i64::from(period.start.days_until(period.end)).max(1);
    let saved = crate::savings::balance(state, as_of)?;
    let saved_before = crate::savings::balance_before(state, period.start)?;
    let reserve = crate::savings::reservation(state, period)?;
    let income = match period.income_index {
        Some(index) if period.funded => state.income[index].amount.hundredths(),
        _ => 0,
    };
    let essential = crate::savings::essential(state, as_of)?;
    let pending = state
        .planned
        .iter()
        .filter(|item| {
            item.kind == PlannedKind::Expense
                && item.status == PlannedStatus::Pending
                && item.date < period.end
        })
        .try_fold(0_i64, |sum, item| {
            sum.checked_add(item.amount.hundredths())
                .ok_or(PouchError::TotalTooLarge)
        })?;
    let elapsed = i64::from(period.start.days_until(as_of).saturating_add(1)).max(1);
    let spent = crate::budget::spent(state, period.start, as_of.add_days(1)?)?;
    let spending_rate = ceiling(i128::from(spent) * i128::from(length), elapsed)?;
    let sustainable = reserve.min((income - essential - pending - spending_rate).max(0));
    let configured = plan_at(state, as_of).monthly_savings.hundredths();
    let mut cumulative = 0_i64;
    let mut previous_rate = 0_i64;
    let mut result = Vec::with_capacity(goals.len());
    for goal in goals {
        cumulative = cumulative
            .checked_add(goal.amount.hundredths())
            .filter(|value| *value <= 9_007_199_254_740_991)
            .ok_or(PouchError::TotalTooLarge)?;
        let earlier = cumulative - goal.amount.hundredths();
        let reached = (saved - earlier).max(0).min(goal.amount.hundredths());
        let remaining = (cumulative - saved).max(0);
        let days = i64::from(as_of.days_until(goal.date)).max(0);
        let required_monthly = if remaining == 0 {
            Some(0)
        } else if days > 0 {
            Some(ceiling(i128::from(remaining) * i128::from(length), days)?)
        } else {
            None
        };
        let completion_days = if remaining == 0 {
            Some(0)
        } else if sustainable > 0 {
            i32::try_from(ceiling(
                i128::from(remaining) * i128::from(length),
                sustainable,
            )?)
            .ok()
        } else {
            None
        };
        let deadline_days = i64::from(period.start.days_until(goal.date).saturating_add(1)).max(1);
        let cycle_needed = ceiling(
            i128::from((cumulative - saved_before).max(0)) * i128::from(length),
            deadline_days,
        )?
        .min((cumulative - saved_before).max(0));
        let required_rate = ceiling(i128::from((cycle_needed - configured).max(0)), length)?;
        let daily_reduction = (required_rate - previous_rate).max(0);
        previous_rate = previous_rate.max(required_rate);
        result.push(GoalForecast {
            id: goal.id.clone(),
            periods: i32::try_from((days + length - 1) / length)
                .map_err(|_| PouchError::InvalidDate)?,
            required_monthly,
            projected: reached,
            percent: ((i128::from(reached) * 100) / i128::from(goal.amount.hundredths())) as i32,
            difference: required_monthly.map(|required| (required - sustainable).max(0)),
            on_track: completion_days.is_some_and(|estimate| i64::from(estimate) <= days),
            completion_days,
            daily_reduction,
        });
    }
    Ok(result)
}

fn ceiling(amount: i128, divisor: i64) -> PouchResult<i64> {
    i64::try_from((amount + i128::from(divisor) - 1) / i128::from(divisor))
        .map_err(|_| PouchError::TotalTooLarge)
}

#[cfg(test)]
mod tests {
    use super::forecast;
    use crate::{
        AppState, Date, Money,
        models::{Calendar, Category, IncomeEntry, PlannedItem, PlannedKind, PlannedStatus},
    };

    fn state() -> AppState {
        let start = Date::parse_iso("2024-01-01").expect("valid date");
        let mut state = AppState::fresh(start);
        state.preferences.calendar = Calendar::Gregorian;
        for id in ["car", "home"] {
            state.planned.push(PlannedItem {
                id: id.into(),
                description: id.into(),
                amount: Money::from_hundredths(20_000).expect("valid amount"),
                category: Category::Other,
                kind: PlannedKind::Goal,
                date: Date::parse_iso("2024-02-01").expect("valid date"),
                status: PlannedStatus::Pending,
                paid_date: None,
                purchase_id: None,
            });
        }
        state
    }

    #[test]
    fn unfunded_goals_have_no_progress_or_completion_estimate() {
        let state = state();
        let goals = forecast(&state, state.start_date).expect("valid forecast");
        assert!(
            goals
                .iter()
                .all(|goal| goal.percent == 0 && goal.completion_days.is_none())
        );
    }

    #[test]
    fn goals_share_received_funds_in_target_order() {
        let mut state = state();
        state.income.push(IncomeEntry {
            id: "salary".into(),
            date: state.start_date,
            amount: Money::from_hundredths(25_000).expect("valid amount"),
        });
        let goals = forecast(&state, state.start_date).expect("valid forecast");
        assert_eq!(goals[0].projected, 20_000);
        assert_eq!(goals[1].projected, 5_000);
        assert_eq!(goals[0].completion_days, Some(0));
        assert_eq!(goals[1].percent, 25);
        assert!(goals[1].completion_days.is_some());
    }

    #[test]
    fn overspending_reduces_funded_progress_and_stops_the_completion_estimate() {
        let mut state = state();
        state.income.push(IncomeEntry {
            id: "salary".into(),
            date: state.start_date,
            amount: Money::from_hundredths(25_000).expect("valid amount"),
        });
        state.days.insert(
            state.start_date,
            crate::models::DailyRecord {
                budget_override: None,
                purchases: vec![crate::models::Purchase {
                    id: "purchase".into(),
                    description: "Purchase".into(),
                    amount: Money::from_hundredths(25_000).expect("valid amount"),
                    category: Category::Other,
                    funded_by_goal: false,
                }],
            },
        );
        let goals = forecast(&state, state.start_date).expect("valid forecast");
        assert!(
            goals
                .iter()
                .all(|goal| goal.percent == 0 && goal.completion_days.is_none())
        );
    }

    #[test]
    fn goal_purchases_consume_the_shared_allocation() {
        let mut state = state();
        state.income.push(IncomeEntry {
            id: "salary".into(),
            date: state.start_date,
            amount: Money::from_hundredths(25_000).expect("valid amount"),
        });
        crate::expenses::mark_paid(
            &mut state,
            "car",
            "car-purchase".into(),
            Date::parse_iso("2024-01-01").expect("valid date"),
            Money::from_hundredths(20_000).expect("valid amount"),
        )
        .expect("goal purchase recorded");
        let goals = forecast(&state, state.start_date).expect("valid forecast");
        assert_eq!(goals.len(), 1);
        assert_eq!(goals[0].id, "home");
        assert_eq!(goals[0].projected, 5_000);
    }
}
