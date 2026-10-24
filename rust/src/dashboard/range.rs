use chrono::Datelike;
use serde::Deserialize;

use crate::{AppState, Date, PouchError, PouchResult, calendar, models::WeekStart};

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DashboardQuery {
    pub mode: String,
    pub anchor: Date,
    pub from: Option<Date>,
    pub through: Option<Date>,
    pub period_id: Option<String>,
}

#[derive(Clone, Copy, Debug)]
pub struct Range {
    pub from: Date,
    pub through: Date,
    pub as_of: Date,
}

pub fn resolve(state: &AppState, query: &DashboardQuery, today: Date) -> PouchResult<Range> {
    query.anchor.to_naive_date()?;
    today.to_naive_date()?;
    let calendar = state.preferences.calendar;
    let (from, through) = match query.mode.as_str() {
        "daily" => (query.anchor, query.anchor),
        "weekly" => {
            let first = match state.preferences.week_start {
                WeekStart::Sunday => 0,
                WeekStart::Monday => 1,
                WeekStart::Saturday => 6,
            };
            let weekday = query
                .anchor
                .to_naive_date()?
                .weekday()
                .num_days_from_sunday();
            let from = query
                .anchor
                .add_days(-(((weekday + 7 - first) % 7) as i32))?;
            (from, from.add_days(6)?)
        }
        "monthly" => (
            calendar::month_start(query.anchor, calendar)?,
            calendar::month_end_exclusive(query.anchor, calendar)?.add_days(-1)?,
        ),
        "yearly" => {
            let year = calendar::parts(query.anchor, calendar)?.year;
            let from = calendar::from_parts(year, 1, 1, calendar)?;
            (
                from,
                calendar::add_months_anchored(from, 12, calendar)?.add_days(-1)?,
            )
        }
        "custom" => (
            query.from.ok_or(PouchError::InvalidDate)?,
            query.through.ok_or(PouchError::InvalidDate)?,
        ),
        "period" => {
            let period = crate::periods::find(
                state,
                query
                    .period_id
                    .as_deref()
                    .ok_or(PouchError::MissingPeriod)?,
            )?;
            (period.start, period.end.add_days(-1)?)
        }
        _ => return Err(PouchError::InvalidDate),
    };
    from.to_naive_date()?;
    through.to_naive_date()?;
    if through < from || from.days_until(through) >= 3660 {
        return Err(PouchError::InvalidDate);
    }
    Ok(Range {
        from,
        through,
        as_of: through.min(today),
    })
}

pub fn label(state: &AppState, date: Date) -> PouchResult<String> {
    let parts = calendar::parts(date, state.preferences.calendar)?;
    Ok(format!(
        "{:04}/{:02}/{:02}",
        parts.year, parts.month, parts.day
    ))
}
