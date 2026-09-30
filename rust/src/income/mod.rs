use chrono::Local;

use crate::{AppState, Date, Money, PouchError, PouchResult, models::IncomeEntry};

pub fn record(state: &mut AppState, id: String, date: Date, amount: Money) -> PouchResult<()> {
    date.to_naive_date()?;
    let today = Date::from_naive_date(Local::now().date_naive())?;
    if id.trim().is_empty()
        || date < state.start_date
        || date > today
        || amount.hundredths() == 0
        || state
            .income
            .iter()
            .any(|entry| entry.id == id || entry.date == date)
    {
        return Err(PouchError::InvalidEntry);
    }
    state.income.push(IncomeEntry { id, date, amount });
    state.income.sort_by_key(|entry| entry.date);
    Ok(())
}

pub fn remove(state: &mut AppState, id: &str) -> PouchResult<()> {
    let original_length = state.income.len();
    state.income.retain(|entry| entry.id != id);
    if state.income.len() == original_length {
        return Err(PouchError::InvalidEntry);
    }
    Ok(())
}

pub fn edit(state: &mut AppState, id: &str, date: Date, amount: Money) -> PouchResult<()> {
    date.to_naive_date()?;
    let today = Date::from_naive_date(Local::now().date_naive())?;
    let Some(index) = state.income.iter().position(|entry| entry.id == id) else {
        return Err(PouchError::InvalidEntry);
    };
    if date < state.start_date
        || date > today
        || amount.hundredths() == 0
        || state
            .income
            .iter()
            .enumerate()
            .any(|(other_index, entry)| other_index != index && entry.date == date)
    {
        return Err(PouchError::InvalidEntry);
    }
    state.income[index].date = date;
    state.income[index].amount = amount;
    state.income.sort_by_key(|entry| entry.date);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::edit;
    use crate::{AppState, Date, Money, models::IncomeEntry};

    #[test]
    fn editing_income_updates_amount_and_resorts_entries() {
        let start = Date::parse_iso("2024-01-01").expect("the date is valid");
        let mut state = AppState::fresh(start);
        state.income = vec![
            IncomeEntry {
                id: "first".into(),
                date: Date::parse_iso("2024-01-01").expect("the date is valid"),
                amount: Money::from_hundredths(100).expect("amount is valid"),
            },
            IncomeEntry {
                id: "second".into(),
                date: Date::parse_iso("2024-02-01").expect("the date is valid"),
                amount: Money::from_hundredths(200).expect("amount is valid"),
            },
        ];

        edit(
            &mut state,
            "second",
            Date::parse_iso("2024-01-15").expect("the date is valid"),
            Money::from_hundredths(300).expect("amount is valid"),
        )
        .expect("the income can be updated");

        assert_eq!(state.income[1].id, "second");
        assert_eq!(state.income[1].amount.hundredths(), 300);
    }

    #[test]
    fn editing_income_rejects_another_entrys_date() {
        let start = Date::parse_iso("2024-01-01").expect("the date is valid");
        let mut state = AppState::fresh(start);
        state.income = vec![
            IncomeEntry {
                id: "first".into(),
                date: Date::parse_iso("2024-01-01").expect("the date is valid"),
                amount: Money::from_hundredths(100).expect("amount is valid"),
            },
            IncomeEntry {
                id: "second".into(),
                date: Date::parse_iso("2024-02-01").expect("the date is valid"),
                amount: Money::from_hundredths(200).expect("amount is valid"),
            },
        ];

        assert!(
            edit(
                &mut state,
                "second",
                Date::parse_iso("2024-01-01").expect("the date is valid"),
                Money::from_hundredths(300).expect("amount is valid"),
            )
            .is_err()
        );
    }
}
