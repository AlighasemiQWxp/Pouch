use chrono::Local;

use crate::{
    AppState, Date, Money, PouchError, PouchResult,
    models::{Category, DailyRecord, PlannedItem, PlannedKind, PlannedStatus, Purchase},
};

pub fn save_planned(state: &mut AppState, item: PlannedItem) -> PouchResult<()> {
    item.date.to_naive_date()?;
    if item.id.trim().is_empty()
        || item.date < state.start_date
        || item.description.trim().is_empty()
        || item.description.encode_utf16().count() > 120
        || item.amount.hundredths() == 0
        || item.status != PlannedStatus::Pending
        || item.paid_date.is_some()
        || item.purchase_id.is_some()
    {
        return Err(PouchError::InvalidEntry);
    }
    if let Some(existing) = state
        .planned
        .iter_mut()
        .find(|existing| existing.id == item.id)
    {
        if existing.status != PlannedStatus::Pending {
            return Err(PouchError::InvalidEntry);
        }
        *existing = PlannedItem {
            description: item.description.trim().to_owned(),
            ..item
        };
        return Ok(());
    }
    state.planned.push(PlannedItem {
        description: item.description.trim().to_owned(),
        ..item
    });
    Ok(())
}

pub fn remove_planned(state: &mut AppState, id: &str) -> PouchResult<()> {
    let Some(index) = state.planned.iter().position(|item| item.id == id) else {
        return Err(PouchError::InvalidEntry);
    };
    if state.planned[index].status != PlannedStatus::Pending {
        return Err(PouchError::InvalidEntry);
    }
    state.planned.remove(index);
    Ok(())
}

pub fn mark_paid(
    state: &mut AppState,
    plan_id: &str,
    purchase_id: String,
    paid_date: Date,
    actual_amount: Money,
) -> PouchResult<()> {
    let today = Date::from_naive_date(Local::now().date_naive())?;
    paid_date.to_naive_date()?;
    if purchase_id.trim().is_empty()
        || paid_date < state.start_date
        || paid_date > today
        || actual_amount.hundredths() == 0
        || state.days.get(&paid_date).is_some_and(|day| {
            day.purchases
                .iter()
                .any(|purchase| purchase.id == purchase_id)
        })
    {
        return Err(PouchError::InvalidEntry);
    }
    let planned = state
        .planned
        .iter_mut()
        .find(|item| item.id == plan_id && item.status == PlannedStatus::Pending)
        .ok_or(PouchError::InvalidEntry)?;
    let purchase = Purchase {
        id: purchase_id.clone(),
        description: planned.description.clone(),
        amount: actual_amount,
        category: planned.category,
        funded_by_goal: planned.kind == PlannedKind::Goal,
    };
    let day = state
        .days
        .entry(paid_date)
        .or_insert_with(DailyRecord::default);
    day.purchases.push(purchase);
    planned.status = PlannedStatus::Paid;
    planned.paid_date = Some(paid_date);
    planned.purchase_id = Some(purchase_id);
    Ok(())
}

pub fn create_planned(
    id: String,
    description: String,
    amount: Money,
    category: Category,
    kind: PlannedKind,
    date: Date,
) -> PlannedItem {
    PlannedItem {
        id,
        description,
        amount,
        category,
        kind,
        date,
        status: PlannedStatus::Pending,
        paid_date: None,
        purchase_id: None,
    }
}
