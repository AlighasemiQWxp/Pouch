use std::collections::BTreeMap;

use serde::Deserialize;

use crate::{
    AppState, Date, PouchError, PouchResult,
    models::{
        BudgetPeriod, BudgetPlan, DailyRecord, ExpectedIncomeEntry, IncomeEntry, IncomeReceipt,
        PlannedItem, Preferences, RequiredExpense, SavingsAllocation,
    },
};

#[derive(Deserialize)]
pub(crate) struct PreviousState {
    schema_version: u16,
    start_date: Date,
    preferences: Preferences,
    periods: Vec<BudgetPeriod>,
    essentials: Vec<RequiredExpense>,
    allocations: Vec<SavingsAllocation>,
    receipts: Vec<IncomeReceipt>,
    income: Vec<IncomeEntry>,
    expected_income: Vec<ExpectedIncomeEntry>,
    plans: Vec<BudgetPlan>,
    days: BTreeMap<Date, DailyRecord>,
    planned: Vec<PlannedItem>,
    economic_assumptions: BTreeMap<String, crate::economics::Assumptions>,
}

impl PreviousState {
    pub fn upgrade(self) -> PouchResult<AppState> {
        if self.schema_version != 5 {
            return Err(PouchError::UnsupportedStorageVersion);
        }
        let mut state = AppState {
            schema_version: AppState::CURRENT_SCHEMA_VERSION,
            start_date: self.start_date,
            preferences: self.preferences,
            periods: self.periods,
            essentials: self.essentials,
            allocations: self.allocations,
            receipts: self.receipts,
            income: self.income,
            expected_income: self.expected_income,
            plans: self.plans,
            days: self.days,
            planned: self.planned,
            economic_assumptions: self.economic_assumptions,
            period_context: Default::default(),
        };
        state.validate()?;
        crate::periods::context::synchronize(&mut state);
        repair_savings(state)
    }
}

pub(crate) fn upgrade_json(mut state: serde_json::Value, schema: u64) -> PouchResult<AppState> {
    if state.get("schemaVersion").and_then(|value| value.as_u64()) != Some(schema) {
        return Err(PouchError::InvalidBackup);
    }
    state["schemaVersion"] = AppState::CURRENT_SCHEMA_VERSION.into();
    if schema == 5 {
        state
            .as_object_mut()
            .ok_or(PouchError::InvalidBackup)?
            .remove("periodContext");
    }
    let mut state: AppState =
        serde_json::from_value(state).map_err(|_| PouchError::InvalidBackup)?;
    state.validate().map_err(|_| PouchError::InvalidBackup)?;
    crate::periods::context::synchronize(&mut state);
    repair_savings(state).map_err(|_| PouchError::InvalidBackup)
}

pub(crate) fn repair_savings(mut state: AppState) -> PouchResult<AppState> {
    state.schema_version = AppState::CURRENT_SCHEMA_VERSION;
    state.validate()?;
    let today = Date::from_naive_date(chrono::Local::now().date_naive())?;
    let start = state.start_date;
    crate::savings::rebuild_from(&mut state, start, today)?;
    state.validate()?;
    Ok(state)
}
