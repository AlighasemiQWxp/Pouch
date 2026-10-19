pub mod context;

use crate::{
    AppState, Date, PouchError, PouchResult, calendar,
    models::{BudgetPeriod, Calendar, Recurrence},
};

pub fn validate_recurrence(recurrence: Recurrence) -> PouchResult<()> {
    if matches!(recurrence, Recurrence::Custom(0 | 3661..=u16::MAX)) {
        return Err(PouchError::InvalidPeriod);
    }
    Ok(())
}

pub fn boundary(
    anchor: Date,
    recurrence: Recurrence,
    calendar: Calendar,
    index: i32,
) -> PouchResult<Date> {
    validate_recurrence(recurrence)?;
    let days = match recurrence {
        Recurrence::Monthly => return calendar::add_months_anchored(anchor, index, calendar),
        Recurrence::Weekly => 7,
        Recurrence::Biweekly => 14,
        Recurrence::Custom(days) => i32::from(days),
        Recurrence::Once if index == 0 => return Ok(anchor),
        Recurrence::Once => return Err(PouchError::InvalidPeriod),
    };
    let date = anchor.add_days(index.checked_mul(days).ok_or(PouchError::InvalidDate)?)?;
    date.to_naive_date()?;
    Ok(date)
}

pub fn at(state: &AppState, date: Date) -> PouchResult<BudgetPeriod> {
    date.to_naive_date()?;
    state
        .periods
        .iter()
        .find(|period| date >= period.start && date < period.end)
        .cloned()
        .ok_or(PouchError::MissingPeriod)
}

pub fn find<'a>(state: &'a AppState, id: &str) -> PouchResult<&'a BudgetPeriod> {
    state
        .periods
        .iter()
        .find(|period| period.id == id)
        .ok_or(PouchError::MissingPeriod)
}

pub fn horizon(
    start: Date,
    recurrence: Recurrence,
    calendar: Calendar,
    through: Option<Date>,
) -> PouchResult<Date> {
    validate_recurrence(recurrence)?;
    let end = match through {
        Some(date) => date.add_days(1)?,
        None => boundary(start, recurrence, calendar, 1)?,
    };
    if end <= start || start.days_until(end) > 3660 {
        return Err(PouchError::InvalidPeriod);
    }
    end.to_naive_date()?;
    Ok(end)
}

pub fn create(
    state: &mut AppState,
    start: Date,
    end: Date,
    recurrence: Recurrence,
    calendar: Calendar,
) -> PouchResult<String> {
    let mut next = state.clone();
    if end <= start {
        return Err(PouchError::InvalidPeriod);
    }
    if next.periods.iter().any(|period| period.start == start) {
        return Err(PouchError::PeriodAlreadyStarts);
    }
    let number = next
        .periods
        .iter()
        .filter_map(|period| {
            period
                .id
                .strip_prefix("BP-")
                .and_then(|id| id.parse::<u64>().ok())
        })
        .max()
        .unwrap_or(0)
        .checked_add(1)
        .ok_or(PouchError::TotalTooLarge)?;
    let id = format!("BP-{number:03}");
    let index = next.periods.partition_point(|period| period.start < start);
    if let Some(previous) = index
        .checked_sub(1)
        .and_then(|index| next.periods.get_mut(index))
    {
        previous.end = start;
    }
    let end = next
        .periods
        .get(index)
        .map(|period| period.start)
        .unwrap_or(end);
    next.periods.insert(
        index,
        BudgetPeriod {
            id: id.clone(),
            start,
            end,
            recurrence,
            calendar,
        },
    );
    next.include_record_date(start.min(Date::from_naive_date(chrono::Local::now().date_naive())?));
    rebind(&mut next)?;
    context::synchronize(&mut next);
    next.validate()?;
    *state = next;
    Ok(id)
}

pub fn edit(
    state: &mut AppState,
    id: &str,
    start: Date,
    end: Date,
    recurrence: Recurrence,
    calendar: Calendar,
) -> PouchResult<()> {
    let mut next = state.clone();
    let index = next
        .periods
        .iter()
        .position(|period| period.id == id)
        .ok_or(PouchError::MissingPeriod)?;
    if index > 0 && start <= next.periods[index - 1].start {
        return Err(PouchError::InvalidPeriod);
    }
    if next
        .periods
        .get(index + 1)
        .is_some_and(|period| end >= period.end || start >= period.end)
    {
        return Err(PouchError::InvalidPeriod);
    }
    next.periods[index] = BudgetPeriod {
        id: id.into(),
        start,
        end,
        recurrence,
        calendar,
    };
    if index > 0 {
        next.periods[index - 1].end = start;
    }
    if let Some(next_period) = next.periods.get_mut(index + 1) {
        next_period.start = end;
    }
    next.include_record_date(start.min(Date::from_naive_date(chrono::Local::now().date_naive())?));
    rebind(&mut next)?;
    next.validate()?;
    *state = next;
    Ok(())
}

pub fn remove(state: &mut AppState, id: &str) -> PouchResult<()> {
    let period = find(state, id)?;
    let contains = |date: Date| date >= period.start && date < period.end;
    let linked = state.plans.iter().any(|item| item.period_id == id)
        || state.allocations.iter().any(|item| item.period_id == id)
        || state
            .income
            .iter()
            .any(|item| context::income_period(state, &item.id, item.date) == Some(id))
        || state
            .expected_income
            .iter()
            .any(|item| context::income_period(state, &item.id, item.date) == Some(id))
        || state
            .period_context
            .planned
            .values()
            .any(|value| value == id)
        || state
            .days
            .iter()
            .any(|(date, day)| contains(*date) && !day.purchases.is_empty())
        || state
            .planned
            .iter()
            .any(|item| context::planned_period(state, item).is_none() && contains(item.date));
    if linked {
        return Err(PouchError::PeriodContainsPlan);
    }
    let mut next = state.clone();
    let index = next
        .periods
        .iter()
        .position(|item| item.id == id)
        .ok_or(PouchError::MissingPeriod)?;
    let removed = next.periods.remove(index);
    if index > 0 {
        next.periods[index - 1].end = removed.end;
    } else if let Some(first) = next.periods.first_mut() {
        first.start = removed.start;
    }
    rebind(&mut next)?;
    context::synchronize(&mut next);
    next.validate()?;
    *state = next;
    Ok(())
}

fn rebind(state: &mut AppState) -> PouchResult<()> {
    let periods = state.periods.clone();
    for plan in &mut state.plans {
        let period = periods
            .iter()
            .find(|period| plan.effective >= period.start && plan.effective < period.end)
            .ok_or(PouchError::PeriodContainsPlan)?;
        plan.period_id = period.id.clone();
    }
    for allocation in &mut state.allocations {
        let period = periods
            .iter()
            .find(|period| allocation.date >= period.start && allocation.date < period.end)
            .ok_or(PouchError::PeriodContainsPlan)?;
        allocation.period_id = period.id.clone();
    }
    Ok(())
}

pub fn validate(state: &AppState) -> PouchResult<()> {
    if state.periods.len() > 1000 {
        return Err(PouchError::InvalidPeriod);
    }
    let mut ids = std::collections::BTreeSet::new();
    for (index, period) in state.periods.iter().enumerate() {
        period.start.to_naive_date()?;
        period.end.to_naive_date()?;
        validate_recurrence(period.recurrence)?;
        if period.id.trim().is_empty()
            || period.id.len() > 120
            || !ids.insert(&period.id)
            || period.end <= period.start
            || period.start.days_until(period.end) > 3660
        {
            return Err(PouchError::InvalidPeriod);
        }
        if state
            .periods
            .get(index + 1)
            .is_some_and(|next| next.start != period.end)
        {
            return Err(PouchError::InvalidPeriod);
        }
    }
    Ok(())
}
