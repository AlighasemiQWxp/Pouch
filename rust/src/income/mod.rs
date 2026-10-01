use chrono::Local;

use crate::{
    AppState, Date, Money, PouchError, PouchResult,
    models::{ExpectedIncomeEntry, IncomeEntry},
};

pub fn record(state: &mut AppState, id: String, date: Date, amount: Money) -> PouchResult<()> {
    date.to_naive_date()?;
    let today = Date::from_naive_date(Local::now().date_naive())?;
    if id.trim().is_empty()
        || date > today
        || amount.hundredths() == 0
        || state
            .expected_income
            .iter()
            .any(|entry| entry.id == id || entry.date == date)
        || state
            .income
            .iter()
            .any(|entry| entry.id == id || entry.date == date)
    {
        return Err(PouchError::InvalidEntry);
    }
    state.include_record_date(date);
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
    if date > today
        || amount.hundredths() == 0
        || state
            .income
            .iter()
            .enumerate()
            .any(|(other_index, entry)| other_index != index && entry.date == date)
        || state.expected_income.iter().any(|entry| entry.date == date)
    {
        return Err(PouchError::InvalidEntry);
    }
    state.include_record_date(date);
    state.income[index].date = date;
    state.income[index].amount = amount;
    state.income.sort_by_key(|entry| entry.date);
    Ok(())
}

pub fn schedule(state: &mut AppState, id: String, date: Date, amount: Money) -> PouchResult<()> {
    date.to_naive_date()?;
    let today = Date::from_naive_date(Local::now().date_naive())?;
    if id.trim().is_empty()
        || date < today
        || date < state.start_date
        || amount.hundredths() == 0
        || state
            .income
            .iter()
            .any(|entry| entry.id == id || entry.date == date)
        || state
            .expected_income
            .iter()
            .any(|entry| entry.id == id || entry.date == date)
    {
        return Err(PouchError::InvalidEntry);
    }
    state
        .expected_income
        .push(ExpectedIncomeEntry { id, date, amount });
    state.expected_income.sort_by_key(|entry| entry.date);
    Ok(())
}

pub fn edit_expected(state: &mut AppState, id: &str, date: Date, amount: Money) -> PouchResult<()> {
    date.to_naive_date()?;
    let today = Date::from_naive_date(Local::now().date_naive())?;
    let Some(index) = state
        .expected_income
        .iter()
        .position(|entry| entry.id == id)
    else {
        return Err(PouchError::InvalidEntry);
    };
    let previous_date = state.expected_income[index].date;
    if date < state.start_date
        || (date < today && date != previous_date)
        || amount.hundredths() == 0
        || state
            .expected_income
            .iter()
            .enumerate()
            .any(|(other_index, entry)| other_index != index && entry.date == date)
        || state.income.iter().any(|entry| entry.date == date)
    {
        return Err(PouchError::InvalidEntry);
    }
    state.expected_income[index].date = date;
    state.expected_income[index].amount = amount;
    state.expected_income.sort_by_key(|entry| entry.date);
    Ok(())
}

pub fn mark_expected_received(
    state: &mut AppState,
    id: &str,
    received_date: Date,
) -> PouchResult<()> {
    received_date.to_naive_date()?;
    let today = Date::from_naive_date(Local::now().date_naive())?;
    let Some(index) = state
        .expected_income
        .iter()
        .position(|entry| entry.id == id)
    else {
        return Err(PouchError::InvalidEntry);
    };
    let expected = state.expected_income[index].clone();
    if received_date > today
        || state
            .income
            .iter()
            .any(|entry| entry.id == expected.id || entry.date == received_date)
        || state
            .expected_income
            .iter()
            .enumerate()
            .any(|(other_index, entry)| other_index != index && entry.date == received_date)
    {
        return Err(PouchError::InvalidEntry);
    }
    state.include_record_date(received_date);
    state.expected_income.remove(index);
    state.income.push(IncomeEntry {
        id: expected.id,
        date: received_date,
        amount: expected.amount,
    });
    state.income.sort_by_key(|entry| entry.date);
    Ok(())
}

pub fn remove_expected(state: &mut AppState, id: &str) -> PouchResult<()> {
    let original_length = state.expected_income.len();
    state.expected_income.retain(|entry| entry.id != id);
    if state.expected_income.len() == original_length {
        return Err(PouchError::InvalidEntry);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::{edit, mark_expected_received, schedule};
    use crate::{
        AppState, Date, Money,
        models::{ExpectedIncomeEntry, IncomeEntry},
    };
    use chrono::Local;

    #[test]
    fn editing_and_receiving_income_can_extend_history() {
        let today = Date::from_naive_date(Local::now().date_naive()).expect("today is valid");
        let earlier = today.add_days(-5).expect("the earlier date is valid");
        let mut state = AppState::fresh(today);
        super::record(
            &mut state,
            "salary".into(),
            today,
            Money::from_hundredths(1000).expect("amount is valid"),
        )
        .expect("income is recorded");
        edit(
            &mut state,
            "salary",
            earlier,
            Money::from_hundredths(1000).expect("amount is valid"),
        )
        .expect("income can be moved before first use");
        assert_eq!(state.start_date, earlier);
        state.validate().expect("edited history is valid");

        schedule(
            &mut state,
            "expected".into(),
            today.add_days(2).expect("the future date is valid"),
            Money::from_hundredths(2000).expect("amount is valid"),
        )
        .expect("income is scheduled");
        let received = earlier.add_days(-2).expect("the received date is valid");
        mark_expected_received(&mut state, "expected", received)
            .expect("expected income can be received before first use");
        assert_eq!(state.start_date, received);
        assert_eq!(state.plans[0].effective, received);
        state.validate().expect("received history is valid");

        assert!(
            super::record(
                &mut state,
                "future".into(),
                today.add_days(1).expect("the future date is valid"),
                Money::from_hundredths(100).expect("amount is valid"),
            )
            .is_err()
        );
        assert_eq!(state.start_date, received);
    }

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

    #[test]
    fn scheduled_income_stays_out_of_recorded_income_until_received() {
        let today = Date::from_naive_date(Local::now().date_naive()).expect("today is valid");
        let start = today.add_days(-1).expect("the start date is valid");
        let future = today.add_days(2).expect("the future date is valid");
        let mut state = AppState::fresh(start);

        schedule(
            &mut state,
            "expected".into(),
            future,
            Money::from_hundredths(100).expect("amount is valid"),
        )
        .expect("future income can be scheduled");

        assert!(state.income.is_empty());
        assert_eq!(state.expected_income.len(), 1);
    }

    #[test]
    fn receiving_expected_income_moves_it_to_recorded_income() {
        let today = Date::from_naive_date(Local::now().date_naive()).expect("today is valid");
        let start = today.add_days(-1).expect("the start date is valid");
        let future = today.add_days(2).expect("the future date is valid");
        let mut state = AppState::fresh(start);
        state.expected_income.push(ExpectedIncomeEntry {
            id: "expected".into(),
            date: future,
            amount: Money::from_hundredths(100).expect("amount is valid"),
        });

        mark_expected_received(&mut state, "expected", today)
            .expect("expected income can be marked received");

        assert!(state.expected_income.is_empty());
        assert_eq!(state.income.len(), 1);
        assert_eq!(state.income[0].date, today);
    }
}
