use chrono::Local;

use crate::{
    AppState, Date, Money, PouchError, PouchResult,
    models::{Category, PlannedStatus, Purchase},
    pagination::{Page, Pagination},
};

pub fn list(state: &AppState, date: Date, pagination: Pagination) -> PouchResult<Page<Purchase>> {
    pagination.validate()?;
    date.to_naive_date()?;
    let mut items = state
        .days
        .get(&date)
        .map(|day| day.purchases.clone())
        .unwrap_or_default();
    items.sort_by(|a, b| a.id.cmp(&b.id));
    pagination.paginate(items)
}

pub fn add(
    state: &mut AppState,
    id: String,
    date: Date,
    description: String,
    amount: Money,
    category: Category,
) -> PouchResult<()> {
    validate_new_purchase(&id, date, &description, amount)?;
    state.include_record_date(date);
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
    crate::savings::reconcile(state, date)?;
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
    validate_new_purchase(id, date, &description, amount)?;
    let purchase = state
        .days
        .get_mut(&date)
        .and_then(|day| day.purchases.iter_mut().find(|purchase| purchase.id == id))
        .ok_or(PouchError::InvalidEntry)?;
    purchase.description = description.trim().to_owned();
    purchase.amount = amount;
    purchase.category = category;
    crate::savings::reconcile(state, date)?;
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
    crate::savings::reconcile(state, date)?;
    Ok(())
}

fn validate_new_purchase(
    id: &str,
    date: Date,
    description: &str,
    amount: Money,
) -> PouchResult<()> {
    let today = Date::from_naive_date(Local::now().date_naive())?;
    date.to_naive_date()?;
    if id.trim().is_empty()
        || date > today
        || description.trim().is_empty()
        || description.encode_utf16().count() > 120
        || amount.hundredths() == 0
    {
        return Err(PouchError::InvalidEntry);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use crate::{
        AppState, Date, Money,
        models::{Category, Purchase},
        pagination::Pagination,
    };

    #[test]
    fn purchase_pages_select_one_day_and_sort_by_id() {
        let date = Date::parse_iso("2024-01-01").expect("valid date");
        let mut state = AppState::fresh(date);
        let next_day = date.add_days(1).expect("valid date");
        for (day, id) in [(date, "b"), (date, "a"), (next_day, "c")] {
            state.days.entry(day).or_default().purchases.push(Purchase {
                id: id.into(),
                description: id.into(),
                amount: Money::from_hundredths(100).expect("valid amount"),
                category: Category::Other,
                funded_by_goal: false,
            });
        }
        let before = state.clone();
        let pagination = Pagination {
            page: 1,
            page_size: 1,
        };
        let result = super::list(&state, date, pagination).expect("valid page");
        assert_eq!(result.total_items, 2);
        assert_eq!(result.items[0].id, "a");
        let empty = super::list(&state, date.add_days(2).expect("valid date"), pagination)
            .expect("valid page");
        assert!(empty.items.is_empty());
        assert_eq!(empty.total_items, 0);
        assert_eq!(state, before);
    }
}
