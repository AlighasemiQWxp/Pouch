use crate::{
    AppState, Date, PouchError, PouchResult,
    budget::plan_at,
    calendar::{self, CalendarParts},
    models::{Calendar, PlannedKind, PlannedStatus},
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
}

pub fn forecast(state: &AppState, as_of: Date) -> PouchResult<Vec<GoalForecast>> {
    let mut goals: Vec<_> = state
        .planned
        .iter()
        .filter(|item| item.kind == PlannedKind::Goal && item.status == PlannedStatus::Pending)
        .collect();
    goals.sort_by(|left, right| {
        left.date
            .cmp(&right.date)
            .then_with(|| left.id.cmp(&right.id))
    });
    let active_plan = plan_at(state, as_of);
    let current_savings = active_plan.monthly_savings.hundredths();
    let calendar = state.preferences.calendar;
    let mut cumulative = 0_i64;
    let mut result = Vec::with_capacity(goals.len());
    for goal in goals {
        cumulative = cumulative
            .checked_add(goal.amount.hundredths())
            .filter(|value| *value <= 9_007_199_254_740_991)
            .ok_or(PouchError::TotalTooLarge)?;
        let (periods, total) = projected_schedule(state, goal.date, as_of, calendar)?;
        let required_monthly = if periods > 0 {
            let periods = i64::from(periods);
            let remainder = if cumulative % periods == 0 { 0 } else { 1 };
            Some(cumulative / periods + remainder)
        } else {
            None
        };
        let earlier_goals = cumulative - goal.amount.hundredths();
        let available = (total - earlier_goals).max(0);
        let reached = available.min(goal.amount.hundredths());
        let percent =
            ((i128::from(reached) * 100) / i128::from(goal.amount.hundredths())).min(100) as i32;
        let difference = required_monthly.map(|required| (required - current_savings).max(0));
        result.push(GoalForecast {
            id: goal.id.clone(),
            periods,
            required_monthly,
            projected: available,
            percent,
            difference,
            on_track: required_monthly.is_some_and(|required| current_savings >= required),
        });
    }
    Ok(result)
}

fn projected_schedule(
    state: &AppState,
    target: Date,
    as_of: Date,
    calendar_type: Calendar,
) -> PouchResult<(i32, i64)> {
    if target < as_of {
        return Ok((0, 0));
    }
    let mut anchor = as_of;
    let mut first_offset = 1;
    let actual_index = state.income.partition_point(|entry| entry.date <= as_of);
    let mut current_period = false;
    if actual_index > 0 {
        let latest = &state.income[actual_index - 1];
        let next_expected = calendar::add_months_anchored(latest.date, 1, calendar_type)?;
        anchor = latest.date;
        if as_of < next_expected {
            current_period = true;
        } else {
            let anchor_parts = calendar::parts(anchor, calendar_type)?;
            let as_of_parts = calendar::parts(as_of, calendar_type)?;
            first_offset = month_difference(anchor_parts, as_of_parts).max(1);
            let first_date = calendar::add_months_anchored(anchor, first_offset, calendar_type)?;
            if first_date < as_of {
                first_offset += 1;
            }
        }
    }
    let anchor_parts = calendar::parts(anchor, calendar_type)?;
    let target_parts = calendar::parts(target, calendar_type)?;
    let mut last_offset = month_difference(anchor_parts, target_parts);
    if last_offset < first_offset {
        last_offset = first_offset - 1;
    }
    if last_offset >= first_offset
        && calendar::add_months_anchored(anchor, last_offset, calendar_type)? > target
    {
        last_offset -= 1;
    }
    let future_count = if last_offset >= first_offset {
        last_offset - first_offset + 1
    } else {
        0
    };
    let current_count = if current_period { 1 } else { 0 };
    let periods = future_count + current_count;
    let total = plan_at(state, as_of)
        .monthly_savings
        .hundredths()
        .checked_mul(i64::from(periods))
        .filter(|value| *value <= 9_007_199_254_740_991)
        .ok_or(PouchError::TotalTooLarge)?;
    Ok((periods, total))
}

fn month_difference(start: CalendarParts, date: CalendarParts) -> i32 {
    (date.year - start.year) * 12 + date.month as i32 - start.month as i32
}

#[cfg(test)]
mod tests {
    use super::forecast;
    use crate::{
        AppState, Date, Money,
        models::{Category, PlannedItem, PlannedKind, PlannedStatus},
    };

    #[test]
    fn multiple_goals_share_the_monthly_savings_projection() {
        let start = Date::parse_iso("2024-01-01").expect("the date is valid");
        let mut state = AppState::fresh(start);
        state.plans[0].monthly_savings = Money::from_hundredths(15_000).expect("amount is valid");
        for (id, target) in [("car", "2024-02-01"), ("home", "2024-03-01")] {
            state.planned.push(PlannedItem {
                id: id.into(),
                description: id.into(),
                amount: Money::from_hundredths(20_000).expect("amount is valid"),
                category: Category::Other,
                kind: PlannedKind::Goal,
                date: Date::parse_iso(target).expect("the date is valid"),
                status: PlannedStatus::Pending,
                paid_date: None,
                purchase_id: None,
            });
        }

        let values = forecast(&state, start).expect("the goals can be forecast");

        assert_eq!(values.len(), 2);
        assert_eq!(values[0].projected, 15_000);
        assert_eq!(values[1].projected, 10_000);
        assert_eq!(values[0].required_monthly, Some(20_000));
        assert_eq!(values[1].required_monthly, Some(20_000));
    }
}
