use chrono::Local;

use crate::{
    AppState, Date, Money, PouchError, PouchResult,
    models::{Category, PlannedStatus, Purchase},
};

pub fn add(
    state: &mut AppState,
    id: String,
    date: Date,
    description: String,
    amount: Money,
    category: Category,
) -> PouchResult<()> {
    validate_new_purchase(state, &id, date, &description, amount)?;
    let day = state.days.entry(date).or_default();
    if day.purchases.iter().any(|purchase| purchase.id == id) {
        return Err(PouchError::InvalidEntry);
    }
    day.purchases.push(Purchase {
        id,
        description: description.trim().to_owned(),
        amount,
        category,
        funded_by_goal: false,
    });
    Ok(())
}

pub fn edit(
    state: &mut AppState,
    date: Date,
    id: &str,
    description: String,
    amount: Money,
    category: Category,
) -> PouchResult<()> {
    validate_new_purchase(state, id, date, &description, amount)?;
    let purchase = state
        .days
        .get_mut(&date)
        .and_then(|day| day.purchases.iter_mut().find(|purchase| purchase.id == id))
        .ok_or(PouchError::InvalidEntry)?;
    purchase.description = description.trim().to_owned();
    purchase.amount = amount;
    purchase.category = category;
    Ok(())
}

pub fn remove(state: &mut AppState, date: Date, id: &str) -> PouchResult<()> {
    let day = state.days.get_mut(&date).ok_or(PouchError::InvalidEntry)?;
    let original_length = day.purchases.len();
    day.purchases.retain(|purchase| purchase.id != id);
    if day.purchases.len() == original_length {
        return Err(PouchError::InvalidEntry);
    }
    for planned in &mut state.planned {
        if planned.status == PlannedStatus::Paid
            && planned.paid_date == Some(date)
            && planned.purchase_id.as_deref() == Some(id)
        {
            planned.status = PlannedStatus::Pending;
            planned.paid_date = None;
            planned.purchase_id = None;
        }
    }
    Ok(())
}

pub fn set_daily_override(
    state: &mut AppState,
    date: Date,
    amount: Option<Money>,
) -> PouchResult<()> {
    let today = Date::from_naive_date(Local::now().date_naive())?;
    if date < today || date < state.start_date {
        return Err(PouchError::InvalidDate);
    }
    date.to_naive_date()?;
    let day = state.days.entry(date).or_default();
    day.budget_override = amount;
    Ok(())
}

fn validate_new_purchase(
    state: &AppState,
    id: &str,
    date: Date,
    description: &str,
    amount: Money,
) -> PouchResult<()> {
    let today = Date::from_naive_date(Local::now().date_naive())?;
    date.to_naive_date()?;
    if id.trim().is_empty()
        || date < state.start_date
        || date > today
        || description.trim().is_empty()
        || description.encode_utf16().count() > 120
        || amount.hundredths() == 0
    {
        return Err(PouchError::InvalidEntry);
    }
    Ok(())
}
