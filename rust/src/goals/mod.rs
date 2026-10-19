use crate::{
    AppState, Date, PouchResult,
    models::{PlannedKind, PlannedStatus},
};

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct GoalForecast {
    pub id: String,
    pub periods: i32,
    pub required_per_period: Option<i64>,
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
    let mut result = Vec::new();
    for goal in goals {
        let forecast = crate::forecast::forecast(state, as_of, &goal.id, None)?;
        let days = as_of.days_until(goal.date).max(0);
        let length = forecast.cycle_days.max(1);
        result.push(GoalForecast {
            id: goal.id.clone(),
            periods: (days + length - 1) / length,
            required_per_period: forecast.period_saving,
            projected: forecast.allocated,
            percent: ((i128::from(forecast.allocated) * 100) / i128::from(goal.amount.hundredths()))
                as i32,
            difference: forecast.income_gap,
            on_track: forecast.on_track,
            completion_days: forecast.completion_days,
            daily_reduction: forecast.spending_reduction,
        });
    }
    Ok(result)
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
        crate::periods::create(
            &mut state,
            start,
            start.add_days(31).unwrap(),
            crate::models::Recurrence::Monthly,
            Calendar::Gregorian,
        )
        .unwrap();
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
                essential_id: None,
            });
        }
        state
    }

    #[test]
    fn unfunded_goals_have_no_progress_or_completion_estimate() {
        let mut state = state();
        let day = state.start_date;
        crate::savings::reconcile(&mut state, day).expect("allocate savings");
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
        let day = state.start_date;
        crate::savings::reconcile(&mut state, day).expect("allocate savings");
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
                purchases: vec![crate::models::Purchase {
                    id: "purchase".into(),
                    description: "Purchase".into(),
                    amount: Money::from_hundredths(25_000).expect("valid amount"),
                    category: Category::Other,
                    funded_by_goal: false,
                }],
            },
        );
        let day = state.start_date;
        crate::savings::reconcile(&mut state, day).expect("allocate savings");
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
        let day = state.start_date;
        crate::savings::reconcile(&mut state, day).expect("allocate savings");
        crate::expenses::mark_paid(
            &mut state,
            "car",
            "car-purchase".into(),
            Date::parse_iso("2024-01-01").expect("valid date"),
            Money::from_hundredths(20_000).expect("valid amount"),
        )
        .expect("goal purchase recorded");
        let day = state.start_date;
        crate::savings::reconcile(&mut state, day).expect("allocate savings");
        let goals = forecast(&state, state.start_date).expect("valid forecast");
        assert_eq!(goals.len(), 1);
        assert_eq!(goals[0].id, "home");
        assert_eq!(goals[0].projected, 5_000);
    }
}
