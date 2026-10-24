use crate::{Money, PouchCore, models::*};

#[flutter_rust_bridge::frb(opaque)]
pub struct PouchApp {
    core: PouchCore,
    economics: crate::economics::EconomicStore,
}

impl PouchApp {
    pub fn open(
        application_data_directory: String,
        legacy_json_candidates: Vec<String>,
    ) -> Result<Self, String> {
        let economics = crate::economics::EconomicStore::new(&application_data_directory);
        let core = PouchCore::open(application_data_directory, &legacy_json_candidates)
            .map_err(|error| error.to_string())?;
        Ok(Self { core, economics })
    }

    pub fn snapshot(&self) -> Result<AppSnapshot, String> {
        snapshot(&self.core)
    }

    pub fn dashboard(&self, query: String) -> Result<String, String> {
        let query: crate::dashboard::range::DashboardQuery =
            serde_json::from_str(&query).map_err(|error| error.to_string())?;
        let today = Date::from_naive_date(chrono::Local::now().date_naive())
            .map_err(|error| error.to_string())?;
        let snapshot = crate::dashboard::snapshot(self.core.state(), &query, today)
            .map_err(|error| error.to_string())?;
        serde_json::to_string(&snapshot).map_err(|error| error.to_string())
    }

    pub fn today(&self) -> Result<String, String> {
        let today = chrono::Local::now().date_naive();
        Date::from_naive_date(today)
            .and_then(Date::iso)
            .map_err(|error| error.to_string())
    }

    pub fn date_parts(&self, date: String, calendar: String) -> Result<DatePartsSnapshot, String> {
        let parts = crate::calendar::parts(parse_date(&date)?, parse_calendar(&calendar)?)
            .map_err(|error| error.to_string())?;
        Ok(DatePartsSnapshot {
            year: parts.year,
            month: parts.month as i32,
            day: parts.day as i32,
        })
    }

    pub fn calendar_month(
        &self,
        date: String,
        calendar: String,
        month_offset: i32,
    ) -> Result<CalendarMonthSnapshot, String> {
        let month =
            crate::calendar::month(parse_date(&date)?, parse_calendar(&calendar)?, month_offset)
                .map_err(|error| error.to_string())?;
        Ok(CalendarMonthSnapshot {
            start_date: month.start.iso().map_err(|error| error.to_string())?,
            year: month.year,
            month: month.month as i32,
            day_count: month.day_count as i32,
            first_weekday: month.first_weekday as i32,
        })
    }

    pub fn calendar_date(
        &self,
        year: i32,
        month: i32,
        day: i32,
        calendar: String,
    ) -> Result<String, String> {
        let month = u32::try_from(month).map_err(|_| "The selected date is invalid.")?;
        let day = u32::try_from(day).map_err(|_| "The selected date is invalid.")?;
        crate::calendar::from_parts(year, month, day, parse_calendar(&calendar)?)
            .and_then(Date::iso)
            .map_err(|error| error.to_string())
    }

    pub fn update_preferences(
        &mut self,
        country: String,
        currency: String,
        language: String,
        calendar: String,
        week_start: i32,
    ) -> Result<AppSnapshot, String> {
        let preferences = Preferences {
            country: parse_country(&country)?,
            currency: parse_currency(&currency)?,
            language: parse_language(&language)?,
            calendar: parse_calendar(&calendar)?,
            week_start: parse_week_start(week_start)?,
        };
        self.core
            .update_preferences(preferences)
            .map_err(|error| error.to_string())?;
        snapshot(&self.core)
    }

    pub fn budget_summary(
        &self,
        date: String,
        period_id: Option<String>,
    ) -> Result<BudgetSnapshot, String> {
        let mut date = parse_date(&date)?;
        if let Some(id) = period_id {
            let period =
                crate::periods::find(self.core.state(), &id).map_err(|error| error.to_string())?;
            date = date
                .max(period.start)
                .min(period.end.add_days(-1).map_err(|error| error.to_string())?);
        }
        let summary =
            crate::budget::recommend(self.core.state(), date).map_err(|error| error.to_string())?;
        Ok(BudgetSnapshot {
            date: summary.date.iso().map_err(|error| error.to_string())?,
            period_end: summary
                .period_end
                .iso()
                .map_err(|error| error.to_string())?,
            days_remaining: summary.days_remaining,
            carry: summary.carry,
            daily: summary.daily,
            spent: summary.spent,
            remaining: summary.remaining,
            income: summary.income,
            required_expenses: summary.required_expenses,
            savings: summary.savings,
            funds: summary.funds,
            reserved: summary.reserved,
            funded_expenses: summary.funded_expenses,
            recommendation: summary.recommendation,
            shortfall: summary.shortfall,
        })
    }

    pub fn add_purchase(
        &mut self,
        id: String,
        date: String,
        description: String,
        amount: String,
        category: String,
    ) -> Result<AppSnapshot, String> {
        let date = parse_date(&date)?;
        let amount = parse_amount(&amount)?;
        let category = parse_category(&category)?;
        self.core
            .apply(|state| crate::purchases::add(state, id, date, description, amount, category))
            .map_err(|error| error.to_string())?;
        snapshot(&self.core)
    }

    pub fn edit_purchase(
        &mut self,
        date: String,
        id: String,
        description: String,
        amount: String,
        category: String,
    ) -> Result<AppSnapshot, String> {
        let date = parse_date(&date)?;
        let amount = parse_amount(&amount)?;
        let category = parse_category(&category)?;
        self.core
            .apply(|state| crate::purchases::edit(state, date, &id, description, amount, category))
            .map_err(|error| error.to_string())?;
        snapshot(&self.core)
    }

    pub fn remove_purchase(&mut self, date: String, id: String) -> Result<AppSnapshot, String> {
        let date = parse_date(&date)?;
        self.core
            .apply_reversible(|state| crate::purchases::remove(state, date, &id))
            .map_err(|error| error.to_string())?;
        snapshot(&self.core)
    }

    pub fn update_income(
        &mut self,
        id: String,
        date: String,
        amount: String,
        period_id: Option<String>,
    ) -> Result<AppSnapshot, String> {
        let date = parse_date(&date)?;
        let amount = parse_amount(&amount)?;
        self.core
            .apply(|state| {
                crate::income::edit(state, &id, date, amount)?;
                if let Some(period_id) = period_id {
                    crate::periods::context::assign_income(state, &id, &period_id)?;
                }
                Ok(())
            })
            .map_err(|error| error.to_string())?;
        snapshot(&self.core)
    }

    pub fn schedule_income(
        &mut self,
        id: String,
        date: String,
        amount: String,
        period_id: Option<String>,
    ) -> Result<AppSnapshot, String> {
        let date = parse_date(&date)?;
        let amount = parse_amount(&amount)?;
        self.core
            .apply(|state| {
                crate::income::schedule(state, id.clone(), date, amount)?;
                if let Some(period_id) = period_id {
                    crate::periods::context::assign_income(state, &id, &period_id)?;
                }
                Ok(())
            })
            .map_err(|error| error.to_string())?;
        snapshot(&self.core)
    }

    pub fn update_expected_income(
        &mut self,
        id: String,
        date: String,
        amount: String,
        period_id: Option<String>,
    ) -> Result<AppSnapshot, String> {
        let date = parse_date(&date)?;
        let amount = parse_amount(&amount)?;
        self.core
            .apply(|state| {
                crate::income::edit_expected(state, &id, date, amount)?;
                if let Some(period_id) = period_id {
                    crate::periods::context::assign_income(state, &id, &period_id)?;
                }
                Ok(())
            })
            .map_err(|error| error.to_string())?;
        snapshot(&self.core)
    }

    pub fn remove_expected_income(&mut self, id: String) -> Result<AppSnapshot, String> {
        self.core
            .apply_reversible(|state| crate::income::remove_expected(state, &id))
            .map_err(|error| error.to_string())?;
        snapshot(&self.core)
    }

    pub fn remove_income(&mut self, id: String) -> Result<AppSnapshot, String> {
        self.core
            .apply_reversible(|state| crate::income::remove(state, &id))
            .map_err(|error| error.to_string())?;
        snapshot(&self.core)
    }

    pub fn remove_budget_plan(&mut self, effective: String) -> Result<AppSnapshot, String> {
        let effective = parse_date(&effective)?;
        self.core
            .apply_reversible(|state| crate::budget::remove_plan(state, effective))
            .map_err(|error| error.to_string())?;
        snapshot(&self.core)
    }

    pub fn save_budget_plan(
        &mut self,
        period_id: String,
        effective: String,
        savings: String,
    ) -> Result<AppSnapshot, String> {
        let plan = BudgetPlan {
            period_id,
            effective: parse_date(&effective)?,
            savings: parse_amount(&savings)?,
        };
        self.core
            .apply(|state| crate::budget::save_plan(state, plan))
            .map_err(|error| error.to_string())?;
        snapshot(&self.core)
    }

    pub fn period_view(&self, date: String) -> Result<PeriodViewSnapshot, String> {
        let date = parse_date(&date)?;
        let state = self.core.state();
        let period = crate::periods::at(state, date).map_err(|error| error.to_string())?;
        let today = Date::from_naive_date(chrono::Local::now().date_naive())
            .map_err(|error| error.to_string())?;
        let as_of = today
            .min(period.end.add_days(-1).map_err(|error| error.to_string())?)
            .max(period.start);
        let income = state
            .income
            .iter()
            .filter(|item| {
                crate::periods::context::income_period(state, &item.id, item.date)
                    == Some(period.id.as_str())
            })
            .map(|item| {
                Ok(IncomeSnapshot {
                    id: item.id.clone(),
                    date: item.date.iso().map_err(|error| error.to_string())?,
                    amount: item.amount.hundredths(),
                    period_id: crate::periods::context::income_period(state, &item.id, item.date)
                        .map(str::to_owned),
                })
            })
            .collect::<Result<Vec<_>, String>>()?;
        let expected_income = state
            .expected_income
            .iter()
            .filter(|item| {
                crate::periods::context::income_period(state, &item.id, item.date)
                    == Some(period.id.as_str())
            })
            .map(|item| {
                Ok(ExpectedIncomeSnapshot {
                    id: item.id.clone(),
                    date: item.date.iso().map_err(|error| error.to_string())?,
                    amount: item.amount.hundredths(),
                    period_id: crate::periods::context::income_period(state, &item.id, item.date)
                        .map(str::to_owned),
                })
            })
            .collect::<Result<Vec<_>, String>>()?;
        let expected_total = expected_income
            .iter()
            .try_fold(0, |sum, item| crate::budget::total(sum, item.amount))
            .map_err(|error| error.to_string())?;
        let obligations = crate::expenses::obligations(state, period.end)
            .map_err(|error| error.to_string())?
            .iter()
            .filter(|item| {
                item.kind == PlannedKind::Expense
                    && crate::periods::context::planned_matches(state, item, &period.id)
                    && (item.date < period.end
                        || crate::periods::context::planned_period(state, item).is_some())
                    && (item.date >= period.start
                        || item.status == PlannedStatus::Pending
                        || item.paid_date.is_some_and(|paid| paid > as_of))
            })
            .map(|item| planned_snapshot_at(state, item, as_of))
            .collect::<Result<Vec<_>, String>>()?;
        Ok(PeriodViewSnapshot {
            period: period_snapshot(state, &period)?,
            plan: plan_snapshot(&crate::budget::plan_at(state, as_of))?,
            budget: self.budget_summary(
                as_of.iso().map_err(|error| error.to_string())?,
                Some(period.id.clone()),
            )?,
            income,
            expected_income,
            expected_total,
            targets: crate::expenses::obligations(state, period.end)
                .map_err(|error| error.to_string())?
                .iter()
                .filter(|item| {
                    crate::periods::context::planned_matches(state, item, &period.id)
                        && (item.status == PlannedStatus::Pending
                            || item.paid_date.is_some_and(|paid| paid > as_of))
                })
                .map(|item| planned_snapshot_at(state, item, as_of))
                .collect::<Result<Vec<_>, _>>()?,
            obligations,
        })
    }

    pub fn save_period(
        &mut self,
        id: Option<String>,
        start: String,
        kind: String,
        custom_days: u16,
        through: Option<String>,
    ) -> Result<AppSnapshot, String> {
        let start = parse_date(&start)?;
        let recurrence = parse_recurrence(&kind, custom_days)?;
        let calendar = id
            .as_deref()
            .and_then(|id| {
                self.core
                    .state()
                    .periods
                    .iter()
                    .find(|period| period.id == id)
            })
            .map(|period| period.calendar)
            .unwrap_or(self.core.state().preferences.calendar);
        let through = through.map(|date| parse_date(&date)).transpose()?;
        let end = crate::periods::horizon(start, recurrence, calendar, through)
            .map_err(|error| error.to_string())?;
        self.core
            .apply(|state| match id {
                Some(id) => crate::periods::edit(state, &id, start, end, recurrence, calendar),
                None => crate::periods::create(state, start, end, recurrence, calendar).map(|_| ()),
            })
            .map_err(|error| error.to_string())?;
        snapshot(&self.core)
    }

    pub fn remove_period(&mut self, id: String) -> Result<AppSnapshot, String> {
        self.core
            .apply_reversible(|state| crate::periods::remove(state, &id))
            .map_err(|error| error.to_string())?;
        snapshot(&self.core)
    }

    pub fn receive_income(&mut self, receipt: ReceiveIncomeRequest) -> Result<AppSnapshot, String> {
        let ReceiveIncomeRequest {
            id,
            date,
            amount,
            period_id,
            start_new,
            kind,
            custom_days,
            through,
            expected,
        } = receipt;
        let date = parse_date(&date)?;
        let amount = parse_amount(&amount)?;
        let calendar = self.core.state().preferences.calendar;
        let recurrence = parse_recurrence(&kind, custom_days)?;
        let new_period = if start_new {
            let through = through.map(|date| parse_date(&date)).transpose()?;
            Some((
                crate::periods::horizon(date, recurrence, calendar, through)
                    .map_err(|error| error.to_string())?,
                recurrence,
                calendar,
            ))
        } else {
            None
        };
        self.core
            .apply(|state| {
                crate::income::receive(
                    state,
                    id,
                    date,
                    amount,
                    period_id.as_deref(),
                    new_period,
                    expected,
                )
            })
            .map_err(|error| error.to_string())?;
        snapshot(&self.core)
    }

    pub fn save_essential_expense(
        &mut self,
        id: String,
        name: String,
        amount: String,
        date: String,
        kind: String,
        custom_days: u16,
    ) -> Result<AppSnapshot, String> {
        let calendar = self
            .core
            .state()
            .essentials
            .iter()
            .find(|item| item.id == id)
            .map(|item| item.calendar)
            .unwrap_or(self.core.state().preferences.calendar);
        let expense = RequiredExpense {
            id,
            name,
            amount: parse_amount(&amount)?,
            date: parse_date(&date)?,
            recurrence: parse_recurrence(&kind, custom_days)?,
            calendar,
            until: None,
        };
        self.core
            .apply(|state| crate::expenses::save_essential(state, expense))
            .map_err(|error| error.to_string())?;
        snapshot(&self.core)
    }

    pub fn stop_essential_expense(
        &mut self,
        id: String,
        date: String,
    ) -> Result<AppSnapshot, String> {
        let date = parse_date(&date)?;
        self.core
            .apply_reversible(|state| crate::expenses::stop_essential(state, &id, date))
            .map_err(|error| error.to_string())?;
        snapshot(&self.core)
    }

    #[allow(clippy::too_many_arguments)]
    pub fn save_planned(
        &mut self,
        id: String,
        description: String,
        amount: String,
        category: String,
        kind: String,
        date: String,
        period_id: Option<String>,
    ) -> Result<AppSnapshot, String> {
        let item = crate::expenses::create_planned(
            id,
            description,
            parse_amount(&amount)?,
            parse_category(&category)?,
            parse_planned_kind(&kind)?,
            parse_date(&date)?,
        );
        let item_id = item.id.clone();
        self.core
            .apply(|state| {
                crate::expenses::save_planned(state, item)?;
                if let Some(period_id) = period_id {
                    crate::periods::context::assign_planned(state, &item_id, &period_id)?;
                }
                Ok(())
            })
            .map_err(|error| error.to_string())?;
        snapshot(&self.core)
    }

    pub fn remove_planned(&mut self, id: String) -> Result<AppSnapshot, String> {
        self.core
            .apply_reversible(|state| crate::expenses::remove_planned(state, &id))
            .map_err(|error| error.to_string())?;
        snapshot(&self.core)
    }

    pub fn mark_planned_paid(
        &mut self,
        plan_id: String,
        purchase_id: String,
        paid_date: String,
        amount: String,
    ) -> Result<AppSnapshot, String> {
        let paid_date = parse_date(&paid_date)?;
        let amount = parse_amount(&amount)?;
        self.core
            .apply(|state| {
                crate::expenses::mark_paid(state, &plan_id, purchase_id, paid_date, amount)
            })
            .map_err(|error| error.to_string())?;
        snapshot(&self.core)
    }

    pub fn export_backup(&self) -> Result<String, String> {
        crate::backup::export_json(self.core.state()).map_err(|error| error.to_string())
    }

    pub fn export_recovery_backup(&self) -> Result<String, String> {
        let state = self
            .core
            .recovery_state()
            .map_err(|error| error.to_string())?
            .ok_or_else(|| crate::PouchError::NoRecoveryCopy.to_string())?;
        crate::backup::export_json(&state).map_err(|error| error.to_string())
    }

    pub fn import_backup(&mut self, contents: String) -> Result<AppSnapshot, String> {
        let replacement =
            crate::backup::import_json(&contents).map_err(|error| error.to_string())?;
        self.core
            .replace_state(replacement)
            .map_err(|error| error.to_string())?;
        snapshot(&self.core)
    }

    pub fn reset(&mut self) -> Result<AppSnapshot, String> {
        let today = chrono::Local::now().date_naive();
        let start_date = Date::from_naive_date(today).map_err(|error| error.to_string())?;
        self.core
            .reset(start_date)
            .map_err(|error| error.to_string())?;
        snapshot(&self.core)
    }

    pub fn undo_last_change(&mut self) -> Result<AppSnapshot, String> {
        self.core.undo().map_err(|error| error.to_string())?;
        snapshot(&self.core)
    }

    pub fn standard_forecast(
        &self,
        as_of: String,
        selected_id: String,
        country: String,
    ) -> Result<String, String> {
        let cached = self.economics.read();
        let result = crate::economics::forecast(
            self.core.state(),
            &cached,
            parse_date(&as_of)?,
            &selected_id,
            &country,
            currency_name(self.core.state().preferences.currency),
        )?;
        serde_json::to_string(&result).map_err(|_| "invalid_profile".into())
    }

    pub fn cache_economic_profile(&self, contents: String) -> Result<(), String> {
        if contents.len() > 200_000 {
            return Err("invalid_profile".into());
        }
        let download: crate::economics::Download =
            serde_json::from_str(&contents).map_err(|_| "invalid_profile")?;
        let iran = download.profile.country == "IR";
        download.profile.validate().map_err(|error| {
            if iran {
                "iran_validation_failed".into()
            } else {
                error
            }
        })?;
        if let Some(exchange) = &download.exchange {
            exchange.validate().map_err(|error| {
                if iran {
                    "iran_validation_failed".into()
                } else {
                    error
                }
            })?;
        }
        self.economics.save(download).map_err(|error| {
            if iran {
                "iran_cache_failed".into()
            } else {
                error
            }
        })
    }

    pub fn customize_economic_profile(
        &mut self,
        country: String,
        monthly_net_income: String,
        monthly_essential: String,
        daily_spending: String,
        exchange_rate: Option<String>,
    ) -> Result<AppSnapshot, String> {
        if !crate::economics::valid_country(&country) {
            return Err("invalid_country".into());
        }
        let goal_currency = currency_name(self.core.state().preferences.currency).to_owned();
        let currency = crate::economics::country_currency(&country, &goal_currency).to_owned();
        let exchange_rate_trillionths = exchange_rate
            .map(|text| parse_exchange_rate(&text))
            .transpose()?;
        let value = crate::economics::Assumptions {
            currency,
            goal_currency,
            monthly_net_income: parse_amount(&monthly_net_income)?.hundredths(),
            monthly_essential: parse_amount(&monthly_essential)?.hundredths(),
            daily_spending: parse_amount(&daily_spending)?.hundredths(),
            exchange_rate_trillionths,
        };
        value.validate().map_err(|error| error.to_string())?;
        self.core
            .apply(|state| {
                state.economic_assumptions.insert(country, value);
                Ok(())
            })
            .map_err(|error| error.to_string())?;
        snapshot(&self.core)
    }

    pub fn reset_economic_profile(&mut self, country: String) -> Result<AppSnapshot, String> {
        self.core
            .apply(|state| {
                state.economic_assumptions.remove(&country);
                Ok(())
            })
            .map_err(|error| error.to_string())?;
        snapshot(&self.core)
    }

    pub fn financial_forecast(
        &self,
        as_of: String,
        selected_id: String,
        recommended: bool,
        income_required: bool,
        period_id: Option<String>,
    ) -> Result<FinancialForecastSnapshot, String> {
        let mut date = parse_date(&as_of)?;
        if let Some(id) = period_id {
            let period =
                crate::periods::find(self.core.state(), &id).map_err(|error| error.to_string())?;
            date = date
                .max(period.start)
                .min(period.end.add_days(-1).map_err(|error| error.to_string())?);
        }
        let forecast = crate::forecast::preview(
            self.core.state(),
            date,
            &selected_id,
            recommended,
            income_required,
        )
        .map_err(|error| error.to_string())?;
        Ok(FinancialForecastSnapshot {
            controllable_spending: forecast.controllable_spending,
            essential_expenses: forecast.essential_expenses,
            configured_savings: forecast.configured_savings,
            extra_days: forecast.extra_days,
            faster_days: forecast.faster_days,
            period_income: forecast.period_income,
            daily_allowance: forecast.daily_allowance,
            required_income: forecast.required_income,
            daily_limit: forecast.daily_limit,
            period_saving: forecast.period_saving,
            income_gap: forecast.income_gap,
            spending_reduction: forecast.spending_reduction,
            allocated: forecast.allocated,
            remaining: forecast.remaining,
            completion_days: forecast.completion_days,
            completion_date: forecast.completion_date,
            on_track: forecast.on_track,
            overdue: forecast.overdue,
            cycle_days: forecast.cycle_days,
            contribution: forecast.contribution,
        })
    }

    pub fn goal_forecast(&self, as_of: String) -> Result<Vec<GoalForecastSnapshot>, String> {
        crate::goals::forecast(self.core.state(), parse_date(&as_of)?)
            .map_err(|error| error.to_string())?
            .into_iter()
            .map(|goal| {
                Ok(GoalForecastSnapshot {
                    id: goal.id,
                    periods: goal.periods,
                    required_per_period: goal.required_per_period,
                    projected: goal.projected,
                    percent: goal.percent,
                    difference: goal.difference,
                    on_track: goal.on_track,
                    completion_days: goal.completion_days,
                    daily_reduction: goal.daily_reduction,
                })
            })
            .collect()
    }

    pub fn report_range(&self, from: String, through: String) -> Result<ReportSnapshot, String> {
        let dates = crate::reports::dates(crate::reports::ReportPeriod::Range {
            from: parse_date(&from)?,
            through: parse_date(&through)?,
        })
        .map_err(|error| error.to_string())?;
        report_snapshot(self.core.state(), dates)
    }

    pub fn report_week(&self, anchor: String, week_start: i32) -> Result<ReportSnapshot, String> {
        let week_start = parse_week_start(week_start)?;
        let dates = crate::reports::dates(crate::reports::ReportPeriod::Weekly {
            anchor: parse_date(&anchor)?,
            week_start,
        })
        .map_err(|error| error.to_string())?;
        report_snapshot(self.core.state(), dates)
    }

    pub fn report_month(&self, anchor: String, calendar: String) -> Result<ReportSnapshot, String> {
        let dates = crate::reports::dates(crate::reports::ReportPeriod::Monthly {
            anchor: parse_date(&anchor)?,
            calendar: parse_calendar(&calendar)?,
        })
        .map_err(|error| error.to_string())?;
        report_snapshot(self.core.state(), dates)
    }

    pub fn report_specific(&self, days: Vec<String>) -> Result<ReportSnapshot, String> {
        let days = days
            .iter()
            .map(|value| parse_date(value))
            .collect::<Result<Vec<_>, _>>()?;
        let dates = crate::reports::dates(crate::reports::ReportPeriod::Specific { days })
            .map_err(|error| error.to_string())?;
        report_snapshot(self.core.state(), dates)
    }
}

pub fn economic_countries() -> Result<String, String> {
    serde_json::to_string(&crate::economics::COUNTRIES).map_err(|_| "invalid_country".into())
}

pub async fn download_economic_profile(
    country: String,
    currency: String,
) -> Result<String, String> {
    let download = crate::economics::download(&country, &currency).await?;
    serde_json::to_string(&download).map_err(|_| "invalid_profile".into())
}

fn parse_exchange_rate(text: &str) -> Result<i64, String> {
    let mut normalized = String::new();
    for character in text.trim().chars() {
        match character {
            '۰'..='۹' => {
                normalized.push(char::from(b'0' + (character as u32 - '۰' as u32) as u8))
            }
            '٠'..='٩' => {
                normalized.push(char::from(b'0' + (character as u32 - '٠' as u32) as u8))
            }
            '٫' => normalized.push('.'),
            ',' | '٬' => {}
            _ => normalized.push(character),
        }
    }
    let mut parts = normalized.split('.');
    let whole = parts.next().ok_or("invalid_exchange_rate")?;
    let fraction = parts.next().unwrap_or("");
    if parts.next().is_some()
        || whole.is_empty()
        || fraction.len() > 12
        || !whole.bytes().all(|byte| byte.is_ascii_digit())
        || !fraction.bytes().all(|byte| byte.is_ascii_digit())
    {
        return Err("invalid_exchange_rate".into());
    }
    let whole: i64 = whole.parse().map_err(|_| "invalid_exchange_rate")?;
    let fraction: i64 = format!("{fraction:0<12}")
        .parse()
        .map_err(|_| "invalid_exchange_rate")?;
    whole
        .checked_mul(1_000_000_000_000)
        .and_then(|value| value.checked_add(fraction))
        .filter(|value| (1..=1_000_000_000_000_000_000).contains(value))
        .ok_or_else(|| "invalid_exchange_rate".into())
}

pub struct AppSnapshot {
    pub revision: u64,
    pub recovered: bool,
    pub imported: bool,
    pub start_date: String,
    pub preferences: PreferencesSnapshot,
    pub income: Vec<IncomeSnapshot>,
    pub expected_income: Vec<ExpectedIncomeSnapshot>,
    pub plans: Vec<BudgetPlanSnapshot>,
    pub current_plan: BudgetPlanSnapshot,
    pub current_period: Option<PeriodSnapshot>,
    pub periods: Vec<PeriodSnapshot>,
    pub essentials: Vec<RequiredExpenseSnapshot>,
    pub income_days: Vec<IncomeDaySnapshot>,
    pub days: Vec<DaySnapshot>,
    pub planned: Vec<PlannedSnapshot>,
}

pub struct PreferencesSnapshot {
    pub country: String,
    pub currency: String,
    pub language: String,
    pub calendar: String,
    pub week_start: i32,
}

pub struct IncomeSnapshot {
    pub period_id: Option<String>,
    pub id: String,
    pub date: String,
    pub amount: i64,
}

pub struct ExpectedIncomeSnapshot {
    pub period_id: Option<String>,
    pub id: String,
    pub date: String,
    pub amount: i64,
}

pub struct RequiredExpenseSnapshot {
    pub id: String,
    pub name: String,
    pub amount: i64,
    pub date: String,
    pub recurrence: String,
    pub custom_days: u16,
    pub until: Option<String>,
}

pub struct BudgetPlanSnapshot {
    pub period_id: String,
    pub effective: String,
    pub savings: i64,
}

pub struct PeriodSnapshot {
    pub name: String,
    pub id: String,
    pub start: String,
    pub end: String,
    pub previous_date: String,
    pub change_from: String,
    pub status: String,
    pub income: i64,
    pub expenses: i64,
    pub savings: i64,
    pub planned_savings: i64,
    pub contributed_savings: i64,
    pub remaining: i64,
    pub carry: i64,
    pub reserved: i64,
    pub funded_expenses: i64,
    pub next_date: String,
    pub recurrence: String,
    pub custom_days: u16,
    pub calendar: String,
}

pub struct ReceiveIncomeRequest {
    pub id: String,
    pub date: String,
    pub amount: String,
    pub period_id: Option<String>,
    pub start_new: bool,
    pub kind: String,
    pub custom_days: u16,
    pub through: Option<String>,
    pub expected: bool,
}

pub struct PeriodViewSnapshot {
    pub period: PeriodSnapshot,
    pub plan: BudgetPlanSnapshot,
    pub budget: BudgetSnapshot,
    pub income: Vec<IncomeSnapshot>,
    pub expected_income: Vec<ExpectedIncomeSnapshot>,
    pub expected_total: i64,
    pub targets: Vec<PlannedSnapshot>,
    pub obligations: Vec<PlannedSnapshot>,
}

pub struct IncomeDaySnapshot {
    pub date: String,
    pub received: i64,
    pub expected: i64,
    pub count: i32,
}

pub struct PurchaseSnapshot {
    pub id: String,
    pub description: String,
    pub amount: i64,
    pub category: String,
    pub funded_by_goal: bool,
}

pub struct DaySnapshot {
    pub date: String,
    pub purchases: Vec<PurchaseSnapshot>,
}

pub struct PlannedSnapshot {
    pub period_id: Option<String>,
    pub id: String,
    pub description: String,
    pub amount: i64,
    pub category: String,
    pub kind: String,
    pub date: String,
    pub status: String,
    pub paid_date: Option<String>,
    pub purchase_id: Option<String>,
    pub essential_id: Option<String>,
}

pub struct BudgetSnapshot {
    pub date: String,
    pub period_end: String,
    pub days_remaining: i32,
    pub carry: i64,
    pub daily: i64,
    pub spent: i64,
    pub remaining: i64,
    pub income: i64,
    pub required_expenses: i64,
    pub savings: i64,
    pub funds: i64,
    pub reserved: i64,
    pub funded_expenses: i64,
    pub recommendation: i64,
    pub shortfall: i64,
}

pub struct FinancialForecastSnapshot {
    pub controllable_spending: i64,
    pub essential_expenses: i64,
    pub configured_savings: i64,
    pub extra_days: Option<i32>,
    pub faster_days: Option<i32>,
    pub contribution: i64,
    pub period_income: i64,
    pub daily_allowance: i64,
    pub required_income: Option<i64>,
    pub daily_limit: i64,
    pub period_saving: Option<i64>,
    pub income_gap: Option<i64>,
    pub spending_reduction: i64,
    pub allocated: i64,
    pub remaining: i64,
    pub completion_days: Option<i32>,
    pub completion_date: Option<String>,
    pub on_track: bool,
    pub overdue: bool,
    pub cycle_days: i32,
}

pub struct GoalForecastSnapshot {
    pub id: String,
    pub periods: i32,
    pub required_per_period: Option<i64>,
    pub projected: i64,
    pub percent: i32,
    pub difference: Option<i64>,
    pub on_track: bool,
    pub completion_days: Option<i32>,
    pub daily_reduction: i64,
}

pub struct ReportSnapshot {
    pub dates: Vec<String>,
    pub entries: Vec<ReportEntrySnapshot>,
    pub daily: Vec<DailyTotalSnapshot>,
    pub categories: Vec<CategoryTotalSnapshot>,
    pub planned: Vec<PlannedReportSnapshot>,
    pub total: i64,
    pub reserved: i64,
}

pub struct DatePartsSnapshot {
    pub year: i32,
    pub month: i32,
    pub day: i32,
}

pub struct CalendarMonthSnapshot {
    pub start_date: String,
    pub year: i32,
    pub month: i32,
    pub day_count: i32,
    pub first_weekday: i32,
}

pub struct ReportEntrySnapshot {
    pub date: String,
    pub id: String,
    pub description: String,
    pub amount: i64,
    pub category: String,
    pub funded_by_goal: bool,
}

pub struct DailyTotalSnapshot {
    pub date: String,
    pub amount: i64,
}

pub struct CategoryTotalSnapshot {
    pub category: String,
    pub amount: i64,
}

pub struct PlannedReportSnapshot {
    pub date: String,
    pub id: String,
    pub description: String,
    pub amount: i64,
    pub category: String,
}

fn parse_date(value: &str) -> Result<Date, String> {
    Date::parse_iso(value).map_err(|error| error.to_string())
}

fn report_snapshot(state: &AppState, dates: Vec<Date>) -> Result<ReportSnapshot, String> {
    let report = crate::reports::build(state, dates).map_err(|error| error.to_string())?;
    Ok(ReportSnapshot {
        dates: report
            .dates
            .iter()
            .map(|date| date.iso().map_err(|error| error.to_string()))
            .collect::<Result<Vec<_>, _>>()?,
        entries: report
            .entries
            .into_iter()
            .map(|entry| {
                Ok(ReportEntrySnapshot {
                    date: entry.date.iso().map_err(|error| error.to_string())?,
                    id: entry.id,
                    description: entry.description,
                    amount: entry.amount,
                    category: category_name(entry.category).to_owned(),
                    funded_by_goal: entry.funded_by_goal,
                })
            })
            .collect::<Result<Vec<_>, String>>()?,
        daily: report
            .daily
            .into_iter()
            .map(|entry| {
                Ok(DailyTotalSnapshot {
                    date: entry.date.iso().map_err(|error| error.to_string())?,
                    amount: entry.amount,
                })
            })
            .collect::<Result<Vec<_>, String>>()?,
        categories: report
            .categories
            .into_iter()
            .map(|entry| CategoryTotalSnapshot {
                category: category_name(entry.category).to_owned(),
                amount: entry.amount,
            })
            .collect(),
        planned: report
            .planned
            .into_iter()
            .map(|entry| {
                Ok(PlannedReportSnapshot {
                    date: entry.date.iso().map_err(|error| error.to_string())?,
                    id: entry.id,
                    description: entry.description,
                    amount: entry.amount,
                    category: category_name(entry.category).to_owned(),
                })
            })
            .collect::<Result<Vec<_>, String>>()?,
        total: report.total,
        reserved: report.reserved,
    })
}

fn parse_amount(value: &str) -> Result<Money, String> {
    crate::money::parse_decimal(value).map_err(|error| error.to_string())
}

fn snapshot(core: &PouchCore) -> Result<AppSnapshot, String> {
    let state = core.state();
    let start_date = state.start_date.iso().map_err(|error| error.to_string())?;
    let preferences = PreferencesSnapshot {
        country: country_name(state.preferences.country).to_owned(),
        currency: currency_name(state.preferences.currency).to_owned(),
        language: language_name(state.preferences.language).to_owned(),
        calendar: calendar_name(state.preferences.calendar).to_owned(),
        week_start: week_start_number(state.preferences.week_start),
    };
    let income = state
        .income
        .iter()
        .map(|entry| {
            Ok(IncomeSnapshot {
                id: entry.id.clone(),
                date: entry.date.iso().map_err(|error| error.to_string())?,
                amount: entry.amount.hundredths(),
                period_id: crate::periods::context::income_period(state, &entry.id, entry.date)
                    .map(str::to_owned),
            })
        })
        .collect::<Result<Vec<_>, String>>()?;
    let expected_income = state
        .expected_income
        .iter()
        .map(|entry| {
            Ok(ExpectedIncomeSnapshot {
                id: entry.id.clone(),
                date: entry.date.iso().map_err(|error| error.to_string())?,
                amount: entry.amount.hundredths(),
                period_id: crate::periods::context::income_period(state, &entry.id, entry.date)
                    .map(str::to_owned),
            })
        })
        .collect::<Result<Vec<_>, String>>()?;
    let today = Date::from_naive_date(chrono::Local::now().date_naive())
        .map_err(|error| error.to_string())?;
    let current_period = match crate::periods::at(state, today) {
        Ok(period) => Some(period_snapshot(state, &period)?),
        Err(crate::PouchError::MissingPeriod) => None,
        Err(error) => return Err(error.to_string()),
    };
    let current_plan = plan_snapshot(&crate::budget::plan_at(state, today))?;
    let plans = state
        .plans
        .iter()
        .map(plan_snapshot)
        .collect::<Result<Vec<_>, _>>()?;
    let essentials = state
        .essentials
        .iter()
        .map(|expense| {
            Ok(RequiredExpenseSnapshot {
                id: expense.id.clone(),
                name: expense.name.clone(),
                amount: expense.amount.hundredths(),
                date: expense.date.iso().map_err(|error| error.to_string())?,
                recurrence: recurrence_name(expense.recurrence).into(),
                custom_days: recurrence_days(expense.recurrence),
                until: expense
                    .until
                    .map(Date::iso)
                    .transpose()
                    .map_err(|error| error.to_string())?,
            })
        })
        .collect::<Result<Vec<_>, String>>()?;
    let mut day_totals = std::collections::BTreeMap::<Date, (i64, i64, i32)>::new();
    for item in &state.income {
        let values = day_totals.entry(item.date).or_default();
        values.0 = crate::budget::total(values.0, item.amount.hundredths())
            .map_err(|error| error.to_string())?;
        values.2 += 1;
    }
    for item in &state.expected_income {
        let values = day_totals.entry(item.date).or_default();
        values.1 = crate::budget::total(values.1, item.amount.hundredths())
            .map_err(|error| error.to_string())?;
        values.2 += 1;
    }
    let income_days = day_totals
        .into_iter()
        .map(|(date, (received, expected, count))| {
            Ok(IncomeDaySnapshot {
                date: date.iso().map_err(|error| error.to_string())?,
                received,
                expected,
                count,
            })
        })
        .collect::<Result<Vec<_>, String>>()?;
    let days = state
        .days
        .iter()
        .map(|(date, day)| {
            Ok(DaySnapshot {
                date: date.iso().map_err(|error| error.to_string())?,
                purchases: day
                    .purchases
                    .iter()
                    .map(|purchase| PurchaseSnapshot {
                        id: purchase.id.clone(),
                        description: purchase.description.clone(),
                        amount: purchase.amount.hundredths(),
                        category: category_name(purchase.category).to_owned(),
                        funded_by_goal: purchase.funded_by_goal,
                    })
                    .collect(),
            })
        })
        .collect::<Result<Vec<_>, String>>()?;
    let horizon = crate::periods::at(state, today)
        .map(|period| period.end)
        .unwrap_or(today);
    let obligations =
        crate::expenses::obligations(state, horizon).map_err(|error| error.to_string())?;
    let planned = obligations
        .iter()
        .map(|item| planned_snapshot(state, item))
        .collect::<Result<Vec<_>, String>>()?;
    Ok(AppSnapshot {
        revision: core.revision(),
        recovered: core.was_recovered(),
        imported: core.imported_json(),
        start_date,
        preferences,
        income,
        expected_income,
        plans,
        current_plan,
        current_period,
        periods: state
            .periods
            .iter()
            .map(|period| period_snapshot(state, period))
            .collect::<Result<Vec<_>, _>>()?,
        essentials,
        income_days,
        days,
        planned,
    })
}

fn planned_snapshot(state: &AppState, item: &PlannedItem) -> Result<PlannedSnapshot, String> {
    Ok(PlannedSnapshot {
        id: item.id.clone(),
        description: item.description.clone(),
        amount: item.amount.hundredths(),
        category: category_name(item.category).into(),
        kind: planned_kind_name(item.kind).into(),
        date: item.date.iso().map_err(|error| error.to_string())?,
        status: planned_status_name(item.status).into(),
        paid_date: item
            .paid_date
            .map(Date::iso)
            .transpose()
            .map_err(|error| error.to_string())?,
        purchase_id: item.purchase_id.clone(),
        essential_id: item.essential_id.clone(),
        period_id: crate::periods::context::planned_period(state, item).map(str::to_owned),
    })
}

fn planned_snapshot_at(
    state: &AppState,
    item: &PlannedItem,
    as_of: Date,
) -> Result<PlannedSnapshot, String> {
    let mut value = planned_snapshot(state, item)?;
    if item.paid_date.is_some_and(|date| date > as_of) {
        value.status = "pending".into();
        value.paid_date = None;
        value.purchase_id = None;
    }
    Ok(value)
}

fn plan_snapshot(plan: &BudgetPlan) -> Result<BudgetPlanSnapshot, String> {
    Ok(BudgetPlanSnapshot {
        period_id: plan.period_id.clone(),
        effective: plan.effective.iso().map_err(|error| error.to_string())?,
        savings: plan.savings.hundredths(),
    })
}

fn period_snapshot(
    state: &crate::AppState,
    period: &BudgetPeriod,
) -> Result<PeriodSnapshot, String> {
    let today = Date::from_naive_date(chrono::Local::now().date_naive())
        .map_err(|error| error.to_string())?;
    let as_of = today
        .max(period.start)
        .min(period.end.add_days(-1).map_err(|error| error.to_string())?);
    let summary = crate::budget::recommend(state, as_of).map_err(|error| error.to_string())?;
    let status = if today < period.start {
        "upcoming"
    } else if today >= period.end {
        if state
            .periods
            .last()
            .is_some_and(|last| last.id == period.id)
        {
            "expired"
        } else {
            "closed"
        }
    } else {
        "active"
    };
    Ok(PeriodSnapshot {
        name: state
            .period_context
            .names
            .get(&period.id)
            .unwrap_or(&period.id)
            .clone(),
        change_from: period.start.iso().map_err(|error| error.to_string())?,
        status: status.into(),
        income: summary.income,
        expenses: crate::budget::spent(
            state,
            period.start,
            as_of.add_days(1).map_err(|error| error.to_string())?,
        )
        .map_err(|error| error.to_string())?,
        savings: summary.savings,
        planned_savings: crate::budget::plan_at(state, as_of).savings.hundredths(),
        contributed_savings: state
            .allocations
            .iter()
            .filter(|item| item.period_id == period.id && item.date <= as_of)
            .try_fold(0, |sum, item| crate::budget::total(sum, item.amount))
            .map_err(|error| error.to_string())?,
        remaining: summary.remaining,
        carry: summary.carry,
        reserved: summary.reserved,
        funded_expenses: summary.funded_expenses,
        id: period.id.clone(),
        start: period.start.iso().map_err(|error| error.to_string())?,
        end: period
            .end
            .add_days(-1)
            .and_then(Date::iso)
            .map_err(|error| error.to_string())?,
        previous_date: period
            .start
            .add_days(-1)
            .and_then(Date::iso)
            .unwrap_or(period.start.iso().map_err(|error| error.to_string())?),
        next_date: period.end.iso().map_err(|error| error.to_string())?,
        recurrence: recurrence_name(period.recurrence).into(),
        custom_days: recurrence_days(period.recurrence),
        calendar: calendar_name(period.calendar).into(),
    })
}

fn parse_recurrence(kind: &str, days: u16) -> Result<Recurrence, String> {
    let recurrence = match kind {
        "once" => Recurrence::Once,
        "weekly" => Recurrence::Weekly,
        "biweekly" => Recurrence::Biweekly,
        "monthly" => Recurrence::Monthly,
        "custom" => Recurrence::Custom(days),
        _ => return Err("Choose a valid schedule.".into()),
    };
    crate::periods::validate_recurrence(recurrence).map_err(|error| error.to_string())?;
    Ok(recurrence)
}

fn recurrence_name(value: Recurrence) -> &'static str {
    match value {
        Recurrence::Once => "once",
        Recurrence::Weekly => "weekly",
        Recurrence::Biweekly => "biweekly",
        Recurrence::Monthly => "monthly",
        Recurrence::Custom(_) => "custom",
    }
}

fn recurrence_days(value: Recurrence) -> u16 {
    match value {
        Recurrence::Custom(days) => days,
        _ => 0,
    }
}

pub fn reset_incompatible_storage(application_data_directory: String) -> Result<(), String> {
    let directory = std::path::PathBuf::from(application_data_directory);
    let mut store = crate::storage::BinaryStore::new(&directory);
    match store.load() {
        Err(crate::PouchError::UnsupportedStorageVersion) | Ok(None) => {}
        Err(error) => return Err(error.to_string()),
        Ok(Some(_)) => {
            return Err("Compatible data are already present. Use Reset in Settings.".into());
        }
    }
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(|error| error.to_string())?
        .as_nanos();
    let archive = directory.join(format!("incompatible-{stamp}"));
    std::fs::create_dir(&archive).map_err(|error| error.to_string())?;
    let mut moved = Vec::new();
    for name in ["pouch.data", "pouch.data.backup"] {
        let source = directory.join(name);
        if source.exists() {
            if let Err(error) = std::fs::rename(&source, archive.join(name)) {
                for previous in &moved {
                    let _ = std::fs::rename(archive.join(previous), directory.join(previous));
                }
                return Err(error.to_string());
            }
            moved.push(name);
        }
    }
    let today = Date::from_naive_date(chrono::Local::now().date_naive())
        .map_err(|error| error.to_string())?;
    crate::storage::BinaryStore::new(&directory)
        .save(&crate::AppState::fresh(today))
        .map_err(|error| error.to_string())
}

fn parse_currency(value: &str) -> Result<Currency, String> {
    match value {
        "TOMAN" => Ok(Currency::Toman),
        "CAD" => Ok(Currency::Cad),
        "USD" => Ok(Currency::Usd),
        "EUR" => Ok(Currency::Eur),
        "GBP" => Ok(Currency::Gbp),
        "AUD" => Ok(Currency::Aud),
        "NZD" => Ok(Currency::Nzd),
        _ => Err("The currency preference is invalid.".into()),
    }
}

fn parse_country(value: &str) -> Result<Country, String> {
    match value {
        "iran" => Ok(Country::Iran),
        "canada" => Ok(Country::Canada),
        "united_states" => Ok(Country::UnitedStates),
        "united_kingdom" => Ok(Country::UnitedKingdom),
        "germany" => Ok(Country::Germany),
        "australia" => Ok(Country::Australia),
        "new_zealand" => Ok(Country::NewZealand),
        "custom" => Ok(Country::Custom),
        _ => Err("The country preference is invalid.".into()),
    }
}

fn country_name(value: Country) -> &'static str {
    match value {
        Country::Iran => "iran",
        Country::Canada => "canada",
        Country::UnitedStates => "united_states",
        Country::UnitedKingdom => "united_kingdom",
        Country::Germany => "germany",
        Country::Australia => "australia",
        Country::NewZealand => "new_zealand",
        Country::Custom => "custom",
    }
}

fn parse_language(value: &str) -> Result<Language, String> {
    match value {
        "en" => Ok(Language::English),
        "fa" => Ok(Language::Persian),
        _ => Err("The language preference is invalid.".into()),
    }
}

fn parse_calendar(value: &str) -> Result<Calendar, String> {
    match value {
        "gregory" => Ok(Calendar::Gregorian),
        "persian" => Ok(Calendar::Jalali),
        _ => Err("The calendar preference is invalid.".into()),
    }
}

fn parse_week_start(value: i32) -> Result<WeekStart, String> {
    match value {
        0 => Ok(WeekStart::Sunday),
        1 => Ok(WeekStart::Monday),
        6 => Ok(WeekStart::Saturday),
        _ => Err("The week start preference is invalid.".into()),
    }
}

fn parse_category(value: &str) -> Result<Category, String> {
    match value {
        "other" => Ok(Category::Other),
        "food" => Ok(Category::Food),
        "transport" => Ok(Category::Transport),
        "shopping" => Ok(Category::Shopping),
        "health" => Ok(Category::Health),
        "entertainment" => Ok(Category::Entertainment),
        "bills" => Ok(Category::Bills),
        _ => Err("The purchase category is invalid.".into()),
    }
}

fn parse_planned_kind(value: &str) -> Result<PlannedKind, String> {
    match value {
        "expense" => Ok(PlannedKind::Expense),
        "goal" => Ok(PlannedKind::Goal),
        _ => Err("The planned item type is invalid.".into()),
    }
}

fn currency_name(value: Currency) -> &'static str {
    match value {
        Currency::Toman => "TOMAN",
        Currency::Cad => "CAD",
        Currency::Usd => "USD",
        Currency::Eur => "EUR",
        Currency::Gbp => "GBP",
        Currency::Aud => "AUD",
        Currency::Nzd => "NZD",
    }
}

fn language_name(value: Language) -> &'static str {
    match value {
        Language::English => "en",
        Language::Persian => "fa",
    }
}

fn calendar_name(value: Calendar) -> &'static str {
    match value {
        Calendar::Gregorian => "gregory",
        Calendar::Jalali => "persian",
    }
}

fn week_start_number(value: WeekStart) -> i32 {
    match value {
        WeekStart::Sunday => 0,
        WeekStart::Monday => 1,
        WeekStart::Saturday => 6,
    }
}

fn category_name(value: Category) -> &'static str {
    match value {
        Category::Other => "other",
        Category::Food => "food",
        Category::Transport => "transport",
        Category::Shopping => "shopping",
        Category::Health => "health",
        Category::Entertainment => "entertainment",
        Category::Bills => "bills",
    }
}

fn planned_kind_name(value: PlannedKind) -> &'static str {
    match value {
        PlannedKind::Expense => "expense",
        PlannedKind::Goal => "goal",
    }
}

fn planned_status_name(value: PlannedStatus) -> &'static str {
    match value {
        PlannedStatus::Pending => "pending",
        PlannedStatus::Paid => "paid",
    }
}

#[cfg(test)]
mod economic_api_tests {
    #[test]
    fn exchange_assumptions_support_persian_digits_and_small_rates() {
        assert_eq!(
            super::parse_exchange_rate("۰٫۰۰۰۰۰۸۷۷۱۲۳۴").expect("rate"),
            8_771_234
        );
        assert_eq!(
            super::parse_exchange_rate("1.4246").expect("rate"),
            1_424_600_000_000
        );
        assert!(super::parse_exchange_rate("0").is_err());
        assert!(super::parse_exchange_rate("NaN").is_err());
        assert!(super::parse_exchange_rate("1e3").is_err());
        assert!(super::parse_exchange_rate("0.0000000000001").is_err());
    }
}
