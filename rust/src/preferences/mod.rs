use crate::{
    AppState, PouchError, PouchResult,
    models::{Calendar, Country, Currency, Language, Preferences, WeekStart},
};

pub fn update(state: &mut AppState, mut next: Preferences) -> PouchResult<()> {
    if next.country != state.preferences.country {
        apply_country_defaults(&mut next);
    }
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

fn apply_country_defaults(preferences: &mut Preferences) {
    let defaults = match preferences.country {
        Country::Iran => Some((Currency::Toman, Calendar::Jalali, WeekStart::Saturday)),
        Country::Canada => Some((Currency::Cad, Calendar::Gregorian, WeekStart::Sunday)),
        Country::UnitedStates => Some((Currency::Usd, Calendar::Gregorian, WeekStart::Sunday)),
        Country::UnitedKingdom => Some((Currency::Gbp, Calendar::Gregorian, WeekStart::Monday)),
        Country::Germany => Some((Currency::Eur, Calendar::Gregorian, WeekStart::Monday)),
        Country::Australia => Some((Currency::Aud, Calendar::Gregorian, WeekStart::Monday)),
        Country::NewZealand => Some((Currency::Nzd, Calendar::Gregorian, WeekStart::Monday)),
        Country::Custom => None,
    };
    if let Some((currency, calendar, week_start)) = defaults {
        preferences.currency = currency;
        preferences.calendar = calendar;
        preferences.week_start = week_start;
    }
}

fn has_recorded_amounts(state: &AppState) -> bool {
    !state.income.is_empty()
        || !state.expected_income.is_empty()
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
        models::{Calendar, Country, Currency, Language, Preferences, WeekStart},
    };

    #[test]
    fn persian_language_switch_selects_jalali_once_and_keeps_manual_choice() {
        let date = Date::parse_iso("2024-01-01").expect("the date is valid");
        let mut state = AppState::fresh(date);
        let persian = Preferences {
            country: state.preferences.country,
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

    #[test]
    fn selecting_iran_applies_regional_defaults() {
        let date = Date::parse_iso("2024-01-01").expect("the date is valid");
        let mut state = AppState::fresh(date);
        state.preferences.country = Country::Custom;
        state.preferences.currency = Currency::Usd;
        state.preferences.calendar = Calendar::Gregorian;
        state.preferences.week_start = WeekStart::Monday;

        let selected = Preferences {
            country: Country::Iran,
            ..state.preferences.clone()
        };
        update(&mut state, selected).expect("the regional defaults can be selected");

        assert_eq!(state.preferences.currency, Currency::Toman);
        assert_eq!(state.preferences.calendar, Calendar::Jalali);
        assert_eq!(state.preferences.week_start, WeekStart::Saturday);
    }
}
