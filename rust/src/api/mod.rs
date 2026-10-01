use crate::{Money, PouchCore, models::*};

#[flutter_rust_bridge::frb(opaque)]
pub struct PouchApp {
    core: PouchCore,
}

impl PouchApp {
    pub fn open(
        application_data_directory: String,
        legacy_json_candidates: Vec<String>,
    ) -> Result<Self, String> {
        let core = PouchCore::open(application_data_directory, &legacy_json_candidates)
            .map_err(|error| error.to_string())?;
        Ok(Self { core })
    }

    pub fn snapshot(&self) -> Result<AppSnapshot, String> {
        snapshot(&self.core)
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

    pub fn budget_summary(&self, date: String) -> Result<BudgetSnapshot, String> {
        let date = parse_date(&date)?;
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

    pub fn set_daily_override(
        &mut self,
        date: String,
        amount: Option<String>,
    ) -> Result<AppSnapshot, String> {
        let date = parse_date(&date)?;
        let amount = amount.map(|value| parse_amount(&value)).transpose()?;
        self.core
            .apply(|state| crate::purchases::set_daily_override(state, date, amount))
            .map_err(|error| error.to_string())?;
        snapshot(&self.core)
    }

    pub fn record_income(
        &mut self,
        id: String,
        date: String,
        amount: String,
    ) -> Result<AppSnapshot, String> {
        let date = parse_date(&date)?;
        let amount = parse_amount(&amount)?;
        self.core
            .apply(|state| crate::income::record(state, id, date, amount))
            .map_err(|error| error.to_string())?;
        snapshot(&self.core)
    }

    pub fn update_income(
        &mut self,
        id: String,
        date: String,
        amount: String,
    ) -> Result<AppSnapshot, String> {
        let date = parse_date(&date)?;
        let amount = parse_amount(&amount)?;
        self.core
            .apply(|state| crate::income::edit(state, &id, date, amount))
            .map_err(|error| error.to_string())?;
        snapshot(&self.core)
    }

    pub fn schedule_income(
        &mut self,
        id: String,
        date: String,
        amount: String,
    ) -> Result<AppSnapshot, String> {
        let date = parse_date(&date)?;
        let amount = parse_amount(&amount)?;
        self.core
            .apply(|state| crate::income::schedule(state, id, date, amount))
            .map_err(|error| error.to_string())?;
        snapshot(&self.core)
    }

    pub fn update_expected_income(
        &mut self,
        id: String,
        date: String,
        amount: String,
    ) -> Result<AppSnapshot, String> {
        let date = parse_date(&date)?;
        let amount = parse_amount(&amount)?;
        self.core
            .apply(|state| crate::income::edit_expected(state, &id, date, amount))
            .map_err(|error| error.to_string())?;
        snapshot(&self.core)
    }

    pub fn mark_expected_income_received(
        &mut self,
        id: String,
        received_date: String,
    ) -> Result<AppSnapshot, String> {
        let received_date = parse_date(&received_date)?;
        self.core
            .apply_reversible(|state| {
                crate::income::mark_expected_received(state, &id, received_date)
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

    #[allow(clippy::too_many_arguments)]
    pub fn save_budget_plan(
        &mut self,
        effective: String,
        salary: Option<String>,
        daily_budget: String,
        expense_ids: Vec<String>,
        expense_names: Vec<String>,
        expense_amounts: Vec<String>,
        savings: String,
        payday: u8,
    ) -> Result<AppSnapshot, String> {
        if expense_ids.len() != expense_names.len() || expense_ids.len() != expense_amounts.len() {
            return Err("The required expense entries are incomplete.".into());
        }
        let plan = BudgetPlan {
            effective: parse_date(&effective)?,
            fallback_salary: salary.map(|value| parse_amount(&value)).transpose()?,
            daily_budget: parse_amount(&daily_budget)?,
            expenses: expense_ids
                .into_iter()
                .zip(expense_names)
                .zip(expense_amounts)
                .map(|((id, name), amount)| {
                    Ok(RequiredExpense {
                        id,
                        name,
                        amount: parse_amount(&amount)?,
                    })
                })
                .collect::<Result<Vec<_>, String>>()?,
            monthly_savings: parse_amount(&savings)?,
            payday,
            calendar: self.core.state().preferences.calendar,
            legacy: false,
        };
        self.core
            .apply(|state| crate::budget::save_plan(state, plan))
            .map_err(|error| error.to_string())?;
        snapshot(&self.core)
    }

    pub fn save_planned(
        &mut self,
        id: String,
        description: String,
        amount: String,
        category: String,
        kind: String,
        date: String,
    ) -> Result<AppSnapshot, String> {
        let item = crate::expenses::create_planned(
            id,
            description,
            parse_amount(&amount)?,
            parse_category(&category)?,
            parse_planned_kind(&kind)?,
            parse_date(&date)?,
        );
        self.core
            .apply(|state| crate::expenses::save_planned(state, item))
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

    pub fn goal_forecast(&self, as_of: String) -> Result<Vec<GoalForecastSnapshot>, String> {
        crate::goals::forecast(self.core.state(), parse_date(&as_of)?)
            .map_err(|error| error.to_string())?
            .into_iter()
            .map(|goal| {
                Ok(GoalForecastSnapshot {
                    id: goal.id,
                    periods: goal.periods,
                    required_monthly: goal.required_monthly,
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

pub struct AppSnapshot {
    pub revision: u64,
    pub recovered: bool,
    pub imported: bool,
    pub start_date: String,
    pub preferences: PreferencesSnapshot,
    pub income: Vec<IncomeSnapshot>,
    pub expected_income: Vec<ExpectedIncomeSnapshot>,
    pub plans: Vec<BudgetPlanSnapshot>,
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
    pub id: String,
    pub date: String,
    pub amount: i64,
}

pub struct ExpectedIncomeSnapshot {
    pub id: String,
    pub date: String,
    pub amount: i64,
}

pub struct RequiredExpenseSnapshot {
    pub id: String,
    pub name: String,
    pub amount: i64,
}

pub struct BudgetPlanSnapshot {
    pub effective: String,
    pub salary: Option<i64>,
    pub daily_budget: i64,
    pub expenses: Vec<RequiredExpenseSnapshot>,
    pub savings: i64,
    pub payday: u8,
    pub calendar: String,
    pub legacy: bool,
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
    pub budget: Option<i64>,
    pub purchases: Vec<PurchaseSnapshot>,
}

pub struct PlannedSnapshot {
    pub id: String,
    pub description: String,
    pub amount: i64,
    pub category: String,
    pub kind: String,
    pub date: String,
    pub status: String,
    pub paid_date: Option<String>,
    pub purchase_id: Option<String>,
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
    pub recommendation: i64,
    pub shortfall: i64,
}

pub struct GoalForecastSnapshot {
    pub id: String,
    pub periods: i32,
    pub required_monthly: Option<i64>,
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
            })
        })
        .collect::<Result<Vec<_>, String>>()?;
    let plans = state
        .plans
        .iter()
        .map(|plan| {
            Ok(BudgetPlanSnapshot {
                effective: plan.effective.iso().map_err(|error| error.to_string())?,
                salary: plan.fallback_salary.map(|amount| amount.hundredths()),
                daily_budget: plan.daily_budget.hundredths(),
                expenses: plan
                    .expenses
                    .iter()
                    .map(|expense| RequiredExpenseSnapshot {
                        id: expense.id.clone(),
                        name: expense.name.clone(),
                        amount: expense.amount.hundredths(),
                    })
                    .collect(),
                savings: plan.monthly_savings.hundredths(),
                payday: plan.payday,
                calendar: calendar_name(plan.calendar).to_owned(),
                legacy: plan.legacy,
            })
        })
        .collect::<Result<Vec<_>, String>>()?;
    let days = state
        .days
        .iter()
        .map(|(date, day)| {
            Ok(DaySnapshot {
                date: date.iso().map_err(|error| error.to_string())?,
                budget: day.budget_override.map(|amount| amount.hundredths()),
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
    let planned = state
        .planned
        .iter()
        .map(|item| {
            Ok(PlannedSnapshot {
                id: item.id.clone(),
                description: item.description.clone(),
                amount: item.amount.hundredths(),
                category: category_name(item.category).to_owned(),
                kind: planned_kind_name(item.kind).to_owned(),
                date: item.date.iso().map_err(|error| error.to_string())?,
                status: planned_status_name(item.status).to_owned(),
                paid_date: item
                    .paid_date
                    .map(|date| date.iso())
                    .transpose()
                    .map_err(|error| error.to_string())?,
                purchase_id: item.purchase_id.clone(),
            })
        })
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
        days,
        planned,
    })
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
