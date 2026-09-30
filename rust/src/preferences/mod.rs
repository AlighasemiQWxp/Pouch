use crate::{
    AppState, PouchError, PouchResult,
    models::{Calendar, Language, Preferences},
};

pub fn update(state: &mut AppState, mut next: Preferences) -> PouchResult<()> {
    if next.currency != state.preferences.currency && has_recorded_amounts(state) {
        return Err(PouchError::CurrencyLocked);
    }
    if next.language == Language::Persian
        && state.preferences.language != Language::Persian
        && next.calendar != Calendar::Jalali
    {
        next.calendar = Calendar::Jalali;
    }
    state.preferences = next;
    Ok(())
}

fn has_recorded_amounts(state: &AppState) -> bool {
    !state.income.is_empty()
        || state.plans.iter().any(|plan| {
            plan.fallback_salary.is_some()
                || plan.daily_budget.hundredths() > 0
                || plan.monthly_savings.hundredths() > 0
                || !plan.expenses.is_empty()
        })
        || !state.planned.is_empty()
        || state
            .days
            .values()
            .any(|day| day.budget_override.is_some() || !day.purchases.is_empty())
}

#[cfg(test)]
mod tests {
    use super::update;
    use crate::{
        AppState, Date,
        models::{Calendar, Language, Preferences, WeekStart},
    };

    #[test]
    fn persian_language_switch_selects_jalali_once_and_keeps_manual_choice() {
        let date = Date::parse_iso("2024-01-01").expect("the date is valid");
        let mut state = AppState::fresh(date);
        let persian = Preferences {
            currency: state.preferences.currency,
            language: Language::Persian,
            calendar: Calendar::Gregorian,
            week_start: WeekStart::Saturday,
        };

        update(&mut state, persian.clone()).expect("the language can be changed");

        assert_eq!(state.preferences.calendar, Calendar::Jalali);
        let manually_selected_gregorian = Preferences {
            calendar: Calendar::Gregorian,
            ..persian
        };
        update(&mut state, manually_selected_gregorian)
            .expect("the calendar can be changed after the language switch");

        assert_eq!(state.preferences.calendar, Calendar::Gregorian);
    }
}
