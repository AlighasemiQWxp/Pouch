use chrono::Local;

use crate::{
    AppState, Date, Money, PouchError, PouchResult,
    models::{Category, PlannedItem, PlannedKind, PlannedStatus, Purchase},
    pagination::{Page, Pagination},
};

pub fn list_planned(
    state: &AppState,
    kind: Option<PlannedKind>,
    status: Option<PlannedStatus>,
    pagination: Pagination,
) -> PouchResult<Page<PlannedItem>> {
    pagination.validate()?;
    let today = Date::from_naive_date(Local::now().date_naive())?;
    let horizon = crate::periods::at(state, today)
        .map(|period| period.end)
        .unwrap_or(today);
    let mut items: Vec<_> = obligations(state, horizon)?
        .into_iter()
        .filter(|item| kind.is_none_or(|kind| item.kind == kind))
        .filter(|item| status.is_none_or(|status| item.status == status))
        .collect();
    items.sort_by(|a, b| a.date.cmp(&b.date).then_with(|| a.id.cmp(&b.id)));
    pagination.paginate(items)
}

pub fn save_planned(state: &mut AppState, item: PlannedItem) -> PouchResult<()> {
    item.date.to_naive_date()?;
    if item.id.starts_with("essential/")
        || item.essential_id.is_some()
        || item.id.trim().is_empty()
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
        let essential_id = existing.essential_id.clone();
        *existing = PlannedItem {
            essential_id,
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
    if state.planned[index].status != PlannedStatus::Pending
        || state.planned[index].essential_id.is_some()
    {
        return Err(PouchError::InvalidEntry);
    }
    state.planned.remove(index);
    state.period_context.planned.remove(id);
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
    if !state.planned.iter().any(|item| item.id == plan_id) {
        let horizon = crate::periods::at(state, paid_date)
            .map(|period| period.end)
            .unwrap_or(paid_date);
        let item = obligations(state, horizon)?
            .into_iter()
            .find(|item| item.id == plan_id)
            .ok_or(PouchError::InvalidEntry)?;
        state.planned.push(item);
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
    let day = state.days.entry(paid_date).or_default();
    day.purchases.push(purchase);
    planned.status = PlannedStatus::Paid;
    planned.paid_date = Some(paid_date);
    planned.purchase_id = Some(purchase_id);
    crate::savings::reconcile(state, paid_date)?;
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
        essential_id: None,
    }
}

pub fn save_essential(
    state: &mut AppState,
    expense: crate::models::RequiredExpense,
) -> PouchResult<()> {
    expense.date.to_naive_date()?;
    crate::periods::validate_recurrence(expense.recurrence)?;
    if expense.id.trim().is_empty()
        || expense.name.trim().is_empty()
        || expense.amount.hundredths() <= 0
        || expense.name.encode_utf16().count() > 120
    {
        return Err(PouchError::InvalidEntry);
    }
    state.include_record_date(expense.date);
    if let Some(existing) = state
        .essentials
        .iter_mut()
        .find(|item| item.id == expense.id)
    {
        *existing = expense;
    } else {
        state.essentials.push(expense);
    }
    Ok(())
}

pub fn stop_essential(state: &mut AppState, id: &str, date: Date) -> PouchResult<()> {
    date.to_naive_date()?;
    let existing: std::collections::BTreeSet<String> =
        state.planned.iter().map(|item| item.id.clone()).collect();
    let retained: Vec<_> = obligations(state, date)?
        .into_iter()
        .filter(|item| {
            item.essential_id.as_deref() == Some(id)
                && item.date <= date
                && !existing.contains(&item.id)
        })
        .collect();
    state.planned.extend(retained);
    let expense = state
        .essentials
        .iter_mut()
        .find(|item| item.id == id)
        .ok_or(PouchError::InvalidEntry)?;
    expense.until = Some(date.max(expense.date));
    Ok(())
}

pub fn obligations(state: &AppState, through: Date) -> PouchResult<Vec<PlannedItem>> {
    let mut items = state.planned.clone();
    let mut ids: std::collections::BTreeSet<String> =
        items.iter().map(|item| item.id.clone()).collect();
    for expense in &state.essentials {
        let mut index = 0;
        loop {
            let date = crate::periods::boundary(
                expense.date,
                expense.recurrence,
                expense.calendar,
                index,
            )?;
            if expense.until.is_some_and(|until| date >= until) {
                break;
            }
            let id = format!("essential/{}/{}", expense.id, date.day_offset());
            if ids.insert(id.clone()) {
                items.push(PlannedItem {
                    id,
                    description: expense.name.clone(),
                    amount: expense.amount,
                    category: Category::Bills,
                    kind: PlannedKind::Expense,
                    date,
                    status: PlannedStatus::Pending,
                    paid_date: None,
                    purchase_id: None,
                    essential_id: Some(expense.id.clone()),
                });
            }
            if items.len() > 100_000 {
                return Err(PouchError::TotalTooLarge);
            }
            if date >= through || expense.recurrence == crate::models::Recurrence::Once {
                break;
            }
            index += 1;
        }
    }
    items.sort_by(|a, b| a.date.cmp(&b.date).then_with(|| a.id.cmp(&b.id)));
    Ok(items)
}

pub fn outstanding(state: &AppState, as_of: Date, through: Date) -> PouchResult<Vec<PlannedItem>> {
    Ok(obligations(state, through)?
        .into_iter()
        .filter(|item| {
            item.kind == PlannedKind::Expense
                && (item.date <= as_of
                    || crate::periods::at(state, as_of).is_ok_and(|period| {
                        crate::periods::context::planned_matches(state, item, &period.id)
                    })
                    || crate::periods::context::planned_period(state, item).is_none())
                && (item.status == PlannedStatus::Pending
                    || item.paid_date.is_some_and(|paid| paid > as_of))
        })
        .collect())
}

#[cfg(test)]
mod tests {
    use super::{create_planned, list_planned};
    use crate::{
        AppState, Date, Money,
        models::{Category, PlannedKind, PlannedStatus},
        pagination::Pagination,
    };
    #[test]
    fn planned_pages_count_filtered_items_and_use_stable_due_date_order() {
        let date = Date::parse_iso("2024-01-01").expect("valid date");
        let mut state = AppState::fresh(date);
        for (id, kind, status) in [
            ("b", PlannedKind::Expense, PlannedStatus::Pending),
            ("goal", PlannedKind::Goal, PlannedStatus::Pending),
            ("paid", PlannedKind::Expense, PlannedStatus::Paid),
            ("a", PlannedKind::Expense, PlannedStatus::Pending),
        ] {
            let mut item = create_planned(
                id.into(),
                id.into(),
                Money::from_hundredths(100).expect("valid amount"),
                Category::Other,
                kind,
                date,
            );
            item.status = status;
            state.planned.push(item);
        }
        let before = state.clone();
        let pagination = Pagination {
            page: 2,
            page_size: 1,
        };
        let result = list_planned(
            &state,
            Some(PlannedKind::Expense),
            Some(PlannedStatus::Pending),
            pagination,
        )
        .expect("valid page");
        assert_eq!(result.total_items, 2);
        assert_eq!(result.items[0].id, "b");
        let all = list_planned(&state, None, None, pagination).expect("valid page");
        assert_eq!(all.total_items, 4);
        assert_eq!(state, before);
    }
}
