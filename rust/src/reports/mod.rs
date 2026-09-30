use std::collections::BTreeSet;

use chrono::Datelike;

use crate::{
    AppState, Date, PouchError, PouchResult, calendar,
    models::{Calendar, Category, PlannedKind, PlannedStatus, WeekStart},
};

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ReportEntry {
    pub date: Date,
    pub id: String,
    pub description: String,
    pub amount: i64,
    pub category: Category,
    pub funded_by_goal: bool,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct DailyTotal {
    pub date: Date,
    pub amount: i64,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CategoryTotal {
    pub category: Category,
    pub amount: i64,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct PlannedReportEntry {
    pub date: Date,
    pub id: String,
    pub description: String,
    pub amount: i64,
    pub category: Category,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Report {
    pub dates: Vec<Date>,
    pub entries: Vec<ReportEntry>,
    pub daily: Vec<DailyTotal>,
    pub categories: Vec<CategoryTotal>,
    pub planned: Vec<PlannedReportEntry>,
    pub total: i64,
    pub reserved: i64,
}

pub enum ReportPeriod {
    Range { from: Date, through: Date },
    Weekly { anchor: Date, week_start: WeekStart },
    Monthly { anchor: Date, calendar: Calendar },
    Specific { days: Vec<Date> },
}

pub fn dates(period: ReportPeriod) -> PouchResult<Vec<Date>> {
    let selected = match period {
        ReportPeriod::Specific { days } => {
            let dates: BTreeSet<_> = days.into_iter().collect();
            if dates.is_empty() || dates.len() > 366 {
                return Err(PouchError::InvalidReport);
            }
            dates.into_iter().collect()
        }
        ReportPeriod::Range { from, through } => inclusive_range(from, through)?,
        ReportPeriod::Weekly { anchor, week_start } => {
            let weekday = anchor.to_naive_date()?.weekday().num_days_from_sunday();
            let first_weekday = match week_start {
                WeekStart::Sunday => 0,
                WeekStart::Monday => 1,
                WeekStart::Saturday => 6,
            };
            let days_since_start = (weekday + 7 - first_weekday) % 7;
            let start = anchor.add_days(-(days_since_start as i32))?;
            inclusive_range(start, start.add_days(6)?)?
        }
        ReportPeriod::Monthly { anchor, calendar } => {
            let start = calendar::month_start(anchor, calendar)?;
            let end = calendar::month_end_exclusive(anchor, calendar)?.add_days(-1)?;
            inclusive_range(start, end)?
        }
    };
    Ok(selected)
}

fn inclusive_range(from: Date, through: Date) -> PouchResult<Vec<Date>> {
    from.to_naive_date()?;
    through.to_naive_date()?;
    if through < from || from.days_until(through) > 365 {
        return Err(PouchError::InvalidReport);
    }
    let count = from.days_until(through) + 1;
    (0..count).map(|offset| from.add_days(offset)).collect()
}

pub fn build(state: &AppState, selected: Vec<Date>) -> PouchResult<Report> {
    let dates = dates(ReportPeriod::Specific { days: selected })?;
    let included: BTreeSet<_> = dates.iter().copied().collect();
    let mut entries = Vec::new();
    let mut daily = Vec::with_capacity(dates.len());
    let mut category_amounts = Vec::<(Category, i64)>::new();
    let mut total = 0_i64;
    for date in &dates {
        let mut day_total = 0_i64;
        if let Some(day) = state.days.get(date) {
            for purchase in &day.purchases {
                day_total = add_amount(day_total, purchase.amount.hundredths())?;
                total = add_amount(total, purchase.amount.hundredths())?;
                if let Some((_, amount)) = category_amounts
                    .iter_mut()
                    .find(|(category, _)| *category == purchase.category)
                {
                    *amount = add_amount(*amount, purchase.amount.hundredths())?;
                } else {
                    category_amounts.push((purchase.category, purchase.amount.hundredths()));
                }
                entries.push(ReportEntry {
                    date: *date,
                    id: purchase.id.clone(),
                    description: purchase.description.clone(),
                    amount: purchase.amount.hundredths(),
                    category: purchase.category,
                    funded_by_goal: purchase.funded_by_goal,
                });
            }
        }
        daily.push(DailyTotal {
            date: *date,
            amount: day_total,
        });
    }
    let mut planned = Vec::new();
    let mut reserved = 0_i64;
    for item in &state.planned {
        if item.kind == PlannedKind::Expense
            && item.status == PlannedStatus::Pending
            && included.contains(&item.date)
        {
            reserved = add_amount(reserved, item.amount.hundredths())?;
            planned.push(PlannedReportEntry {
                date: item.date,
                id: item.id.clone(),
                description: item.description.clone(),
                amount: item.amount.hundredths(),
                category: item.category,
            });
        }
    }
    planned.sort_by_key(|item| (item.date, item.id.clone()));
    Ok(Report {
        dates,
        entries,
        daily,
        categories: category_amounts
            .into_iter()
            .map(|(category, amount)| CategoryTotal { category, amount })
            .collect(),
        planned,
        total,
        reserved,
    })
}

fn add_amount(current: i64, next: i64) -> PouchResult<i64> {
    current
        .checked_add(next)
        .filter(|total| *total <= 9_007_199_254_740_991)
        .ok_or(PouchError::TotalTooLarge)
}

#[cfg(test)]
mod tests {
    use super::{ReportPeriod, dates};
    use crate::{
        Date,
        models::{Calendar, WeekStart},
    };

    #[test]
    fn custom_ranges_include_both_end_dates() {
        let from = Date::parse_iso("2026-09-01").expect("the date is valid");
        let through = Date::parse_iso("2026-09-03").expect("the date is valid");
        let selected = dates(ReportPeriod::Range { from, through }).expect("the range is valid");

        assert_eq!(selected.len(), 3);
        assert_eq!(selected.first(), Some(&from));
        assert_eq!(selected.last(), Some(&through));
    }

    #[test]
    fn weekly_period_starts_on_the_selected_weekday() {
        let anchor = Date::parse_iso("2026-09-30").expect("the date is valid");
        let selected = dates(ReportPeriod::Weekly {
            anchor,
            week_start: WeekStart::Monday,
        })
        .expect("the week is valid");

        assert_eq!(selected.len(), 7);
        assert_eq!(selected[0].iso().expect("date formats"), "2026-09-28");
        assert_eq!(selected[6].iso().expect("date formats"), "2026-10-04");
    }

    #[test]
    fn monthly_period_uses_the_requested_calendar() {
        let anchor = Date::parse_iso("2024-03-20").expect("the date is valid");
        let selected = dates(ReportPeriod::Monthly {
            anchor,
            calendar: Calendar::Jalali,
        })
        .expect("the month is valid");

        assert_eq!(
            selected.first().and_then(|date| date.iso().ok()).as_deref(),
            Some("2024-03-20")
        );
        assert_eq!(
            selected.last().and_then(|date| date.iso().ok()).as_deref(),
            Some("2024-04-19")
        );
    }
}
