use crate::{
    PouchError, PouchResult,
    models::{Calendar, Date},
};
use chrono::{Datelike, NaiveDate};
use jalali_calendar::JalaliDate;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct CalendarParts {
    pub year: i32,
    pub month: u32,
    pub day: u32,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct CalendarMonth {
    pub start: Date,
    pub year: i32,
    pub month: u32,
    pub day_count: u32,
    pub first_weekday: u32,
}

pub fn parts(date: Date, calendar: Calendar) -> PouchResult<CalendarParts> {
    let gregorian = date.to_naive_date()?;
    match calendar {
        Calendar::Gregorian => Ok(CalendarParts {
            year: gregorian.year(),
            month: gregorian.month(),
            day: gregorian.day(),
        }),
        Calendar::Jalali => {
            let value =
                JalaliDate::from_naive_date(gregorian).map_err(|_| PouchError::InvalidDate)?;
            Ok(CalendarParts {
                year: value.year(),
                month: value.month(),
                day: value.day(),
            })
        }
    }
}

pub fn month_start(date: Date, calendar: Calendar) -> PouchResult<Date> {
    match calendar {
        Calendar::Gregorian => {
            let current = date.to_naive_date()?;
            let start = NaiveDate::from_ymd_opt(current.year(), current.month(), 1)
                .ok_or(PouchError::InvalidDate)?;
            Date::from_naive_date(start)
        }
        Calendar::Jalali => {
            let current = JalaliDate::from_naive_date(date.to_naive_date()?)
                .map_err(|_| PouchError::InvalidDate)?;
            Date::from_naive_date(current.first_day_of_month().to_naive_date())
        }
    }
}

pub fn add_months_anchored(date: Date, months: i32, calendar: Calendar) -> PouchResult<Date> {
    match calendar {
        Calendar::Gregorian => {
            let anchor = date.to_naive_date()?;
            let index = anchor.year() * 12 + anchor.month() as i32 - 1 + months;
            let year = index.div_euclid(12);
            let month = index.rem_euclid(12) as u32 + 1;
            let next_month = if month == 12 {
                NaiveDate::from_ymd_opt(year + 1, 1, 1)
            } else {
                NaiveDate::from_ymd_opt(year, month + 1, 1)
            }
            .ok_or(PouchError::InvalidDate)?;
            let month_end = next_month.pred_opt().ok_or(PouchError::InvalidDate)?.day();
            let result = NaiveDate::from_ymd_opt(year, month, anchor.day().min(month_end))
                .ok_or(PouchError::InvalidDate)?;
            Date::from_naive_date(result)
        }
        Calendar::Jalali => {
            let anchor = JalaliDate::from_naive_date(date.to_naive_date()?)
                .map_err(|_| PouchError::InvalidDate)?;
            Date::from_naive_date(anchor.add_months(months).to_naive_date())
        }
    }
}

pub fn month_end_exclusive(date: Date, calendar: Calendar) -> PouchResult<Date> {
    let start = month_start(date, calendar)?;
    add_months_anchored(start, 1, calendar)
}

pub fn month(date: Date, calendar: Calendar, offset: i32) -> PouchResult<CalendarMonth> {
    let start = add_months_anchored(month_start(date, calendar)?, offset, calendar)?;
    let parts = parts(start, calendar)?;
    let day_count = match calendar {
        Calendar::Gregorian => {
            let current = start.to_naive_date()?;
            let next_month = if current.month() == 12 {
                NaiveDate::from_ymd_opt(current.year() + 1, 1, 1)
            } else {
                NaiveDate::from_ymd_opt(current.year(), current.month() + 1, 1)
            }
            .ok_or(PouchError::InvalidDate)?;
            next_month.pred_opt().ok_or(PouchError::InvalidDate)?.day()
        }
        Calendar::Jalali => JalaliDate::from_naive_date(start.to_naive_date()?)
            .map_err(|_| PouchError::InvalidDate)?
            .days_in_this_month(),
    };
    let first_weekday = start.to_naive_date()?.weekday().num_days_from_sunday();
    Ok(CalendarMonth {
        start,
        year: parts.year,
        month: parts.month,
        day_count,
        first_weekday,
    })
}

pub fn from_parts(year: i32, month: u32, day: u32, calendar: Calendar) -> PouchResult<Date> {
    match calendar {
        Calendar::Gregorian => {
            let value = NaiveDate::from_ymd_opt(year, month, day).ok_or(PouchError::InvalidDate)?;
            Date::from_naive_date(value)
        }
        Calendar::Jalali => {
            let value = JalaliDate::new(year, month, day).map_err(|_| PouchError::InvalidDate)?;
            Date::from_naive_date(value.to_naive_date())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{add_months_anchored, from_parts, month, parts};
    use crate::{Date, models::Calendar};

    #[test]
    fn gregorian_month_addition_clamps_at_month_end() {
        let january = Date::parse_iso("2024-01-31").expect("the date is valid");
        let february =
            add_months_anchored(january, 1, Calendar::Gregorian).expect("the next month is valid");

        assert_eq!(february.iso().expect("date formats"), "2024-02-29");
    }

    #[test]
    fn nowruz_conversion_has_the_expected_jalali_parts() {
        let nowruz = Date::parse_iso("2024-03-20").expect("the date is valid");
        let value = parts(nowruz, Calendar::Jalali).expect("the Jalali date converts");

        assert_eq!((value.year, value.month, value.day), (1403, 1, 1));
    }

    #[test]
    fn jalali_month_grid_and_selection_use_canonical_dates() {
        let anchor = Date::parse_iso("2024-03-20").expect("the date is valid");
        let grid = month(anchor, Calendar::Jalali, 0).expect("the month is available");
        let last_day = from_parts(grid.year, grid.month, grid.day_count, Calendar::Jalali)
            .expect("the last day is valid");

        assert_eq!(grid.day_count, 31);
        assert_eq!(grid.first_weekday, 3);
        assert_eq!(last_day.iso().expect("date formats"), "2024-04-19");
    }

    #[test]
    fn final_supported_gregorian_month_can_be_displayed() {
        let anchor = Date::parse_iso("9998-12-31").expect("the date is valid");
        let grid = month(anchor, Calendar::Gregorian, 0).expect("the final month can be displayed");

        assert_eq!((grid.year, grid.month, grid.day_count), (9998, 12, 31));
    }
}
