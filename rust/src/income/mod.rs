use chrono::Local;

use crate::{
    AppState, Date, Money, PouchError, PouchResult,
    models::{ExpectedIncomeEntry, IncomeEntry},
    pagination::{Page, Pagination},
};

pub fn list(state: &AppState, pagination: Pagination) -> PouchResult<Page<IncomeEntry>> {
    pagination.validate()?;
    let mut items = state.income.clone();
    items.sort_by(|a, b| b.date.cmp(&a.date).then_with(|| a.id.cmp(&b.id)));
    pagination.paginate(items)
}

pub fn list_expected(
    state: &AppState,
    pagination: Pagination,
) -> PouchResult<Page<ExpectedIncomeEntry>> {
    pagination.validate()?;
    let mut items = state.expected_income.clone();
    items.sort_by(|a, b| b.date.cmp(&a.date).then_with(|| a.id.cmp(&b.id)));
    pagination.paginate(items)
}

pub fn record(state: &mut AppState, id: String, date: Date, amount: Money) -> PouchResult<()> {
    date.to_naive_date()?;
    let today = Date::from_naive_date(Local::now().date_naive())?;
    if id.trim().is_empty()
        || date > today
        || amount.hundredths() == 0
        || state.expected_income.iter().any(|entry| entry.id == id)
        || state.income.iter().any(|entry| entry.id == id)
    {
        return Err(PouchError::InvalidEntry);
    }
    state.include_record_date(date);
    state.income.push(IncomeEntry { id, date, amount });
    state.income.sort_by_key(|entry| entry.date);
    crate::savings::reconcile(state, date)?;
    Ok(())
}

pub fn receive(
    state: &mut AppState,
    id: String,
    date: Date,
    amount: Money,
    existing_period: Option<&str>,
    new_period: Option<(Date, crate::models::Recurrence, crate::models::Calendar)>,
    expected: bool,
) -> PouchResult<()> {
    let mut next = state.clone();
    match (existing_period, new_period) {
        (Some(period_id), None) => {
            crate::periods::find(&next, period_id)?;
        }
        (None, Some((end, recurrence, calendar))) => {
            crate::periods::create(&mut next, date, end, recurrence, calendar)?;
        }
        _ => return Err(PouchError::InvalidPeriod),
    }
    if expected {
        mark_expected_received(&mut next, &id, date)?;
        next.income
            .iter_mut()
            .find(|entry| entry.id == id)
            .ok_or(PouchError::InvalidEntry)?
            .amount = amount;
    } else {
        record(&mut next, id.clone(), date, amount)?;
    }
    let period_id = match existing_period {
        Some(id) => id.to_owned(),
        None => crate::periods::at(&next, date)?.id,
    };
    crate::periods::context::assign_income(&mut next, &id, &period_id)?;
    crate::savings::reconcile(&mut next, date)?;
    next.validate()?;
    *state = next;
    Ok(())
}

pub fn remove(state: &mut AppState, id: &str) -> PouchResult<()> {
    let date = state
        .income
        .iter()
        .find(|entry| entry.id == id)
        .ok_or(PouchError::InvalidEntry)?
        .date;
    let original_length = state.income.len();
    state.income.retain(|entry| entry.id != id);
    state.period_context.income.remove(id);
    state.receipts.retain(|receipt| receipt.income_id != id);
    if state.income.len() == original_length {
        return Err(PouchError::InvalidEntry);
    }
    crate::savings::reconcile(state, date)?;
    Ok(())
}

pub fn edit(state: &mut AppState, id: &str, date: Date, amount: Money) -> PouchResult<()> {
    date.to_naive_date()?;
    let today = Date::from_naive_date(Local::now().date_naive())?;
    let Some(index) = state.income.iter().position(|entry| entry.id == id) else {
        return Err(PouchError::InvalidEntry);
    };
    if date > today || amount.hundredths() == 0 {
        return Err(PouchError::InvalidEntry);
    }
    let previous_date = state.income[index].date;
    state.include_record_date(date);
    state.income[index].date = date;
    state.income[index].amount = amount;
    state.income.sort_by_key(|entry| entry.date);
    crate::savings::reconcile(state, previous_date)?;
    if previous_date != date {
        crate::savings::reconcile(state, date)?;
    }
    Ok(())
}

pub fn schedule(state: &mut AppState, id: String, date: Date, amount: Money) -> PouchResult<()> {
    date.to_naive_date()?;
    let today = Date::from_naive_date(Local::now().date_naive())?;
    if id.trim().is_empty()
        || date < today
        || date < state.start_date
        || amount.hundredths() == 0
        || state.income.iter().any(|entry| entry.id == id)
        || state.expected_income.iter().any(|entry| entry.id == id)
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
    if received_date > today {
        return Err(PouchError::InvalidEntry);
    }
    state.include_record_date(received_date);
    state.receipts.push(crate::models::IncomeReceipt {
        income_id: expected.id.clone(),
        expected_date: expected.date,
        expected_amount: expected.amount,
    });
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
    state.period_context.income.remove(id);
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
    fn income_pages_sort_each_list_without_changing_state() {
        let start = Date::parse_iso("2024-01-01").expect("valid date");
        let later = start.add_days(1).expect("valid date");
        let amount = Money::from_hundredths(100).expect("valid amount");
        let mut state = AppState::fresh(start);
        for (id, date) in [("old", start), ("b", later), ("a", later)] {
            state.income.push(IncomeEntry {
                id: id.into(),
                date,
                amount,
            });
            state.expected_income.push(ExpectedIncomeEntry {
                id: id.into(),
                date,
                amount,
            });
        }
        let before = state.clone();
        let pagination = crate::pagination::Pagination {
            page: 2,
            page_size: 1,
        };
        let received = super::list(&state, pagination).expect("valid page");
        let expected = super::list_expected(&state, pagination).expect("valid page");
        assert_eq!(received.total_items, 3);
        assert_eq!(expected.total_items, 3);
        assert_eq!(received.items[0].id, "b");
        assert_eq!(expected.items[0].id, "b");
        assert_eq!(state, before);
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
