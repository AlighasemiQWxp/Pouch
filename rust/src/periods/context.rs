use std::{
    collections::{BTreeMap, BTreeSet, hash_map::RandomState},
    hash::{BuildHasher, Hasher},
};

use serde::{Deserialize, Serialize};

use crate::{AppState, Date, PouchError, PouchResult, models::PlannedItem};

#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PeriodContext {
    pub names: BTreeMap<String, String>,
    pub income: BTreeMap<String, String>,
    pub planned: BTreeMap<String, String>,
}

pub fn synchronize(state: &mut AppState) {
    let periods: BTreeSet<_> = state
        .periods
        .iter()
        .map(|period| period.id.clone())
        .collect();
    state
        .period_context
        .names
        .retain(|id, _| periods.contains(id));
    for id in &periods {
        if !state.period_context.names.contains_key(id) {
            let name = loop {
                let mut random = RandomState::new().build_hasher();
                random.write(id.as_bytes());
                let name = format!("P-{:08X}", random.finish() as u32);
                if !state
                    .period_context
                    .names
                    .values()
                    .any(|value| value == &name)
                {
                    break name;
                }
            };
            state.period_context.names.insert(id.clone(), name);
        }
    }
    let income: BTreeSet<_> = state
        .income
        .iter()
        .map(|item| item.id.as_str())
        .chain(state.expected_income.iter().map(|item| item.id.as_str()))
        .collect();
    state
        .period_context
        .income
        .retain(|id, period| income.contains(id.as_str()) && periods.contains(period));
    let planned: BTreeSet<_> = state.planned.iter().map(|item| item.id.as_str()).collect();
    state
        .period_context
        .planned
        .retain(|id, period| planned.contains(id.as_str()) && periods.contains(period));
}

pub fn validate(state: &AppState) -> PouchResult<()> {
    let mut names = BTreeSet::new();
    for (id, name) in &state.period_context.names {
        if !state.periods.iter().any(|period| &period.id == id)
            || name.trim().is_empty()
            || name.len() > 64
            || !names.insert(name)
        {
            return Err(PouchError::InvalidState);
        }
    }
    for (id, period) in &state.period_context.income {
        if !state.periods.iter().any(|item| &item.id == period)
            || !state.income.iter().any(|item| &item.id == id)
                && !state.expected_income.iter().any(|item| &item.id == id)
        {
            return Err(PouchError::InvalidState);
        }
    }
    for (id, period) in &state.period_context.planned {
        if !state.periods.iter().any(|item| &item.id == period)
            || !state
                .planned
                .iter()
                .any(|item| &item.id == id && item.essential_id.is_none())
        {
            return Err(PouchError::InvalidState);
        }
    }
    Ok(())
}

pub fn income_period<'a>(state: &'a AppState, id: &str, date: Date) -> Option<&'a str> {
    state
        .period_context
        .income
        .get(id)
        .map(String::as_str)
        .or_else(|| {
            state
                .periods
                .iter()
                .find(|period| date >= period.start && date < period.end)
                .map(|period| period.id.as_str())
        })
}

pub fn planned_period<'a>(state: &'a AppState, item: &PlannedItem) -> Option<&'a str> {
    state
        .period_context
        .planned
        .get(&item.id)
        .map(String::as_str)
}

pub fn planned_matches(state: &AppState, item: &PlannedItem, period_id: &str) -> bool {
    planned_period(state, item).is_none_or(|id| id == period_id)
}

pub fn assign_income(state: &mut AppState, id: &str, period_id: &str) -> PouchResult<()> {
    super::find(state, period_id)?;
    if !state.income.iter().any(|item| item.id == id)
        && !state.expected_income.iter().any(|item| item.id == id)
    {
        return Err(PouchError::InvalidEntry);
    }
    state
        .period_context
        .income
        .insert(id.into(), period_id.into());
    Ok(())
}

pub fn assign_planned(state: &mut AppState, id: &str, period_id: &str) -> PouchResult<()> {
    super::find(state, period_id)?;
    if !state
        .planned
        .iter()
        .any(|item| item.id == id && item.essential_id.is_none())
    {
        return Err(PouchError::InvalidEntry);
    }
    state
        .period_context
        .planned
        .insert(id.into(), period_id.into());
    Ok(())
}
