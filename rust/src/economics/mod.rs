mod canada;
mod international;
mod sci_tls;
mod store;

use crate::{AppState, Date, Money, PouchError, PouchResult};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
pub use store::{CachedData, EconomicStore};

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CountryProfile {
    pub code: &'static str,
    pub label_key: &'static str,
    pub currency: &'static str,
    pub automatic: bool,
}

pub const COUNTRIES: [CountryProfile; 7] = [
    CountryProfile {
        code: "CA",
        label_key: "countryCanada",
        currency: "CAD",
        automatic: true,
    },
    CountryProfile {
        code: "IR",
        label_key: "countryIran",
        currency: "TOMAN",
        automatic: true,
    },
    CountryProfile {
        code: "US",
        label_key: "countryUnitedStates",
        currency: "USD",
        automatic: true,
    },
    CountryProfile {
        code: "GB",
        label_key: "countryUnitedKingdom",
        currency: "GBP",
        automatic: true,
    },
    CountryProfile {
        code: "DE",
        label_key: "countryGermany",
        currency: "EUR",
        automatic: true,
    },
    CountryProfile {
        code: "AU",
        label_key: "countryAustralia",
        currency: "AUD",
        automatic: true,
    },
    CountryProfile {
        code: "NZ",
        label_key: "countryNewZealand",
        currency: "NZD",
        automatic: true,
    },
];

pub fn country_currency<'a>(country: &str, fallback: &'a str) -> &'a str {
    COUNTRIES
        .iter()
        .find(|profile| profile.code == country)
        .map(|profile| profile.currency)
        .unwrap_or(fallback)
}

pub const METHOD_VERSION: u16 = 1;
const DAYS_PER_MONTH: i128 = 36525;

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Assumptions {
    pub currency: String,
    pub monthly_net_income: i64,
    pub monthly_essential: i64,
    pub daily_spending: i64,
    pub goal_currency: String,
    pub exchange_rate_trillionths: Option<i64>,
}

impl Assumptions {
    pub fn validate(&self) -> PouchResult<()> {
        for amount in [
            self.monthly_net_income,
            self.monthly_essential,
            self.daily_spending,
        ] {
            Money::from_hundredths(amount)?;
        }
        if !valid_currency(&self.currency)
            || !valid_currency(&self.goal_currency)
            || self
                .exchange_rate_trillionths
                .is_some_and(|rate| !(1..=1_000_000_000_000_000_000).contains(&rate))
        {
            return Err(PouchError::InvalidAmount);
        }
        Ok(())
    }
}

pub fn validate_assumptions(values: &BTreeMap<String, Assumptions>) -> PouchResult<()> {
    if values.len() > 250 {
        return Err(PouchError::InvalidState);
    }
    for (country, value) in values {
        if !valid_country(country) {
            return Err(PouchError::InvalidState);
        }
        value.validate()?;
    }
    Ok(())
}

pub fn valid_country(country: &str) -> bool {
    country.len() == 2 && country.bytes().all(|byte| byte.is_ascii_uppercase())
}

pub fn valid_currency(currency: &str) -> bool {
    matches!(
        currency,
        "CAD" | "USD" | "EUR" | "GBP" | "AUD" | "NZD" | "TOMAN"
    )
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Observation {
    pub indicator: String,
    pub value: f64,
    pub unit: String,
    pub period: String,
    pub released: String,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Profile {
    pub version: u16,
    pub country: String,
    pub downloaded: String,
    pub observations: Vec<Observation>,
}

impl Profile {
    pub fn validate(&self) -> Result<(), String> {
        if self
            .observations
            .iter()
            .any(|entry| entry.indicator == "annual_net")
        {
            return self.validate_international();
        }
        if self.version != METHOD_VERSION || self.country != "CA" || self.observations.len() != 8 {
            return Err("unreviewed_profile".into());
        }
        let downloaded = Date::parse_iso(&self.downloaded).map_err(|_| "invalid_profile")?;
        let now = Date::from_naive_date(chrono::Utc::now().date_naive())
            .map_err(|_| "invalid_profile")?;
        if downloaded > now {
            return Err("invalid_profile".into());
        }
        for (indicator, unit, period) in canada::INDICATORS {
            let entries: Vec<_> = self
                .observations
                .iter()
                .filter(|entry| entry.indicator == indicator)
                .collect();
            if entries.len() != 1 {
                return Err("invalid_profile".into());
            }
            let entry = entries[0];
            if entry.unit != unit
                || entry.period != period
                || !entry.value.is_finite()
                || !(0.0..=1_000_000.0).contains(&entry.value)
                || entry.value == 0.0
                || entry.released.len() > 32
            {
                return Err("invalid_profile".into());
            }
        }
        let ratio = self.value("cpi_2025")? / self.value("cpi_2023")?;
        if !(0.8..=1.5).contains(&ratio)
            || !(20_000.0..=200_000.0).contains(&self.value("gross")?)
            || !(10_000.0..=150_000.0).contains(&self.value("net")?)
            || !(10_000.0..=100_000.0).contains(&self.value("consumption")?)
        {
            return Err("review_required".into());
        }
        let essential =
            self.value("shelter")? + self.value("groceries")? + self.value("operations")?;
        if self.value("net")? > self.value("gross")? || essential > self.value("consumption")? {
            return Err("invalid_profile".into());
        }
        Ok(())
    }

    fn value(&self, indicator: &str) -> Result<f64, String> {
        self.observations
            .iter()
            .find(|entry| entry.indicator == indicator)
            .map(|entry| entry.value)
            .ok_or_else(|| "invalid_profile".into())
    }

    fn assumptions(&self) -> Result<Assumptions, String> {
        self.validate()?;
        if self
            .observations
            .iter()
            .any(|entry| entry.indicator == "annual_net")
        {
            return Ok(Assumptions {
                currency: country_currency(&self.country, "").into(),
                monthly_net_income: money(self.value("annual_net")? / 12.0)?,
                monthly_essential: money(self.value("annual_spending")? / 12.0)?,
                daily_spending: 0,
                goal_currency: country_currency(&self.country, "").into(),
                exchange_rate_trillionths: None,
            });
        }
        let inflation = self.value("cpi_2025")? / self.value("cpi_2023")?;
        let essential =
            self.value("shelter")? + self.value("groceries")? + self.value("operations")?;
        Ok(Assumptions {
            currency: "CAD".into(),
            monthly_net_income: money(self.value("net")? / 12.0)?,
            monthly_essential: money(essential * inflation / 12.0)?,
            daily_spending: money((self.value("consumption")? - essential) * inflation / 365.25)?,
            goal_currency: "CAD".into(),
            exchange_rate_trillionths: None,
        })
    }
}

impl Profile {
    fn validate_international(&self) -> Result<(), String> {
        if self.version != METHOD_VERSION
            || !COUNTRIES.iter().any(|country| country.code == self.country)
            || !(2..=3).contains(&self.observations.len())
            || self.country == "CA"
        {
            return Err("invalid_profile".into());
        }
        let downloaded = Date::parse_iso(&self.downloaded).map_err(|_| "invalid_profile")?;
        let now = Date::from_naive_date(chrono::Utc::now().date_naive())
            .map_err(|_| "invalid_profile")?;
        if downloaded > now {
            return Err("invalid_profile".into());
        }
        let currency = country_currency(&self.country, "");
        for indicator in ["annual_net", "annual_spending", "cad_per_local"] {
            let entries: Vec<_> = self
                .observations
                .iter()
                .filter(|entry| entry.indicator == indicator)
                .collect();
            if indicator == "cad_per_local" && entries.is_empty() && self.observations.len() == 2 {
                continue;
            }
            if entries.len() != 1 {
                return Err("invalid_profile".into());
            }
            let entry = entries[0];
            if !entry.value.is_finite() || entry.value <= 0.0 || entry.released.len() > 200 {
                return Err("invalid_profile".into());
            }
            if indicator == "cad_per_local" {
                if entry.unit != "CAD/local unit"
                    || !(0.000000001..=1000.0).contains(&entry.value)
                    || Date::parse_iso(&entry.period).map_err(|_| "invalid_profile")? > downloaded
                {
                    return Err("invalid_profile".into());
                }
            } else {
                money(entry.value)?;
                let suffix = if self.country == "IR" {
                    "/household/year"
                } else if indicator == "annual_net" {
                    "/year"
                } else {
                    "/person/year"
                };
                if entry.unit != format!("{currency}{suffix}") {
                    return Err("invalid_profile".into());
                }
                let year = entry.period.parse::<i32>().map_err(|_| "invalid_profile")?;
                let upper = if self.country == "IR" {
                    1404
                } else {
                    chrono::Datelike::year(&chrono::Utc::now())
                };
                if !(2020..=upper).contains(&year) && !(self.country == "IR" && year == 1404) {
                    return Err("invalid_profile".into());
                }
            }
        }
        let income = self
            .observations
            .iter()
            .find(|entry| entry.indicator == "annual_net")
            .ok_or("invalid_profile")?;
        let spending = self
            .observations
            .iter()
            .find(|entry| entry.indicator == "annual_spending")
            .ok_or("invalid_profile")?;
        let income_year = income
            .period
            .parse::<i32>()
            .map_err(|_| "invalid_profile")?;
        let spending_year = spending
            .period
            .parse::<i32>()
            .map_err(|_| "invalid_profile")?;
        if (income_year - spending_year).abs() > 2 {
            return Err("invalid_profile".into());
        }
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ExchangeRate {
    pub currency: String,
    pub cad_per_unit: f64,
    pub date: String,
    pub downloaded: String,
}

impl ExchangeRate {
    pub fn validate(&self) -> Result<(), String> {
        if !matches!(
            self.currency.as_str(),
            "CAD" | "USD" | "EUR" | "GBP" | "AUD" | "NZD" | "TOMAN"
        ) || !self.cad_per_unit.is_finite()
            || !(0.000000001..=1000.0).contains(&self.cad_per_unit)
            || (self.currency == "CAD" && self.cad_per_unit != 1.0)
        {
            return Err("invalid_exchange_rate".into());
        }
        let date = Date::parse_iso(&self.date).map_err(|_| "invalid_exchange_rate")?;
        let downloaded = Date::parse_iso(&self.downloaded).map_err(|_| "invalid_exchange_rate")?;
        let now = Date::from_naive_date(chrono::Utc::now().date_naive())
            .map_err(|_| "invalid_exchange_rate")?;
        if date > downloaded || downloaded > now {
            return Err("invalid_exchange_rate".into());
        }
        Ok(())
    }
}

#[derive(Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Download {
    pub profile: Profile,
    pub exchange: Option<ExchangeRate>,
}

pub async fn download(country: &str, currency: &str) -> Result<Download, String> {
    if !COUNTRIES.iter().any(|profile| profile.code == country) || !valid_currency(currency) {
        return Err("unreviewed_profile".into());
    }
    let client = reqwest::Client::builder()
        .https_only(true)
        .timeout(std::time::Duration::from_secs(20))
        .redirect(reqwest::redirect::Policy::none())
        .user_agent("Pouch economic profiles")
        .build()
        .map_err(|_| {
            if country == "IR" {
                "iran_transport_failed"
            } else {
                "retrieval_failed"
            }
        })?;
    let profile = if country == "CA" {
        canada::download(&client).await?
    } else {
        international::download(&client, country).await?
    };
    // A failed currency request must not discard valid economic statistics.
    let exchange = international::exchange(&client, currency)
        .await
        .ok()
        .flatten();
    Ok(Download { profile, exchange })
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct StandardForecast {
    pub country: String,
    pub status: String,
    pub customized: bool,
    pub needs_refresh: bool,
    pub cache_warning: bool,
    pub downloaded: Option<String>,
    pub currency: String,
    pub remaining: i64,
    pub converted_remaining: Option<i64>,
    pub converted_goal: Option<i64>,
    pub required_monthly_saving: Option<i64>,
    pub required_monthly_income: Option<i64>,
    pub monthly_net_income: Option<i64>,
    pub monthly_essential: Option<i64>,
    pub daily_spending: Option<i64>,
    pub monthly_saving: Option<i64>,
    pub completion_days: Option<i32>,
    pub completion_date: Option<String>,
    pub exchange: Option<ExchangeRate>,
    pub exchange_rate_trillionths: Option<i64>,
    pub observations: Vec<Observation>,
}

pub fn forecast(
    state: &AppState,
    store: &CachedData,
    today: Date,
    selected: &str,
    country: &str,
    goal_currency: &str,
) -> Result<StandardForecast, String> {
    if !valid_country(country) {
        return Err("invalid_country".into());
    }
    let personal = crate::forecast::forecast(state, today, selected, None)
        .map_err(|error| error.to_string())?;
    let remaining = personal.remaining;
    let item = state
        .planned
        .iter()
        .find(|item| item.id == selected)
        .ok_or("invalid_entry")?;
    let cached = store.profile(country);
    let custom = state.economic_assumptions.get(country);
    let currency = country_currency(country, goal_currency);
    let mut result = StandardForecast {
        country: country.into(),
        status: "initial_connection".into(),
        customized: custom.is_some(),
        needs_refresh: cached.is_none_or(|profile| {
            age(&profile.downloaded, today) >= 30
                || profile.observations.iter().any(|entry| {
                    entry.indicator == "cad_per_local" && age(&entry.period, today) >= 7
                })
        }),
        cache_warning: store.warning(),
        downloaded: cached.map(|profile| profile.downloaded.clone()),
        currency: currency.into(),
        remaining,
        converted_remaining: None,
        converted_goal: None,
        required_monthly_saving: None,
        required_monthly_income: None,
        monthly_net_income: None,
        monthly_essential: None,
        daily_spending: None,
        monthly_saving: None,
        completion_days: None,
        completion_date: None,
        exchange: None,
        exchange_rate_trillionths: None,
        observations: cached
            .map(|profile| profile.observations.clone())
            .unwrap_or_default(),
    };
    let assumptions = match custom {
        Some(value) => value.clone(),
        None => match cached {
            Some(profile) => profile.assumptions()?,
            None => return Ok(result),
        },
    };
    assumptions.validate().map_err(|_| "invalid_assumptions")?;
    result.currency = assumptions.currency.clone();
    result.monthly_net_income = Some(assumptions.monthly_net_income);
    result.monthly_essential = Some(assumptions.monthly_essential);
    result.daily_spending = Some(assumptions.daily_spending);
    let daily_cost = (i128::from(assumptions.daily_spending) * DAYS_PER_MONTH + 1199) / 1200;
    let capacity = (i128::from(assumptions.monthly_net_income)
        - i128::from(assumptions.monthly_essential)
        - daily_cost)
        .max(0);
    result.monthly_saving = Some(i64::try_from(capacity).map_err(|_| "invalid_assumptions")?);
    let rate = if goal_currency == assumptions.currency {
        Some(1_000_000_000_000)
    } else if custom.is_some()
        && assumptions.goal_currency == goal_currency
        && assumptions.exchange_rate_trillionths.is_some()
    {
        assumptions.exchange_rate_trillionths
    } else {
        store.exchange(goal_currency).and_then(|exchange| {
            result.exchange = Some(exchange.clone());
            if age(&exchange.date, today) >= 7 {
                result.needs_refresh = true;
            }
            let local = if assumptions.currency == "CAD" {
                1.0
            } else {
                cached
                    .and_then(|profile| profile.value("cad_per_local").ok())
                    .unwrap_or(0.0)
            };
            if local <= 0.0 {
                return None;
            }
            Some((exchange.cad_per_unit / local * 1_000_000_000_000.0).round() as i64)
        })
    };
    if rate.is_none() {
        result.needs_refresh = true;
    }
    let Some(rate) = rate else {
        if remaining == 0 {
            result.converted_remaining = Some(0);
            result.required_monthly_saving = Some(0);
            let living = i64::try_from(i128::from(assumptions.monthly_essential) + daily_cost)
                .map_err(|_| "target_too_large")?;
            Money::from_hundredths(living).map_err(|_| "target_too_large")?;
            result.required_monthly_income = Some(living);
            result.completion_days = Some(0);
            result.completion_date = Some(today.iso().map_err(|_| "date_out_of_range")?);
            result.status = "ready".into();
            return Ok(result);
        }
        result.status = "conversion_required".into();
        return Ok(result);
    };
    result.exchange_rate_trillionths = Some(rate);
    if rate <= 0 || rate > 1_000_000_000_000_000_000 {
        return Err("invalid_exchange_rate".into());
    }
    let target = (i128::from(remaining) * i128::from(rate) + 999_999_999_999) / 1_000_000_000_000;
    let target = i64::try_from(target).map_err(|_| "target_too_large")?;
    Money::from_hundredths(target).map_err(|_| "target_too_large")?;
    result.converted_remaining = Some(target);
    let full = (i128::from(item.amount.hundredths()) * i128::from(rate) + 999_999_999_999)
        / 1_000_000_000_000;
    let full = i64::try_from(full).map_err(|_| "target_too_large")?;
    Money::from_hundredths(full).map_err(|_| "target_too_large")?;
    result.converted_goal = Some(full);
    let deadline = i128::from(today.days_until(item.date)).max(0);
    let cumulative = i128::from(target);
    if cumulative == 0 || deadline > 0 {
        let required = if cumulative == 0 {
            0
        } else {
            (cumulative * DAYS_PER_MONTH + deadline * 1200 - 1) / (deadline * 1200)
        };
        let salary = required + i128::from(assumptions.monthly_essential) + daily_cost;
        let required = i64::try_from(required).map_err(|_| "target_too_large")?;
        let salary = i64::try_from(salary).map_err(|_| "target_too_large")?;
        Money::from_hundredths(required).map_err(|_| "target_too_large")?;
        Money::from_hundredths(salary).map_err(|_| "target_too_large")?;
        result.required_monthly_saving = Some(required);
        result.required_monthly_income = Some(salary);
    }
    if target > 0 && capacity == 0 {
        result.status = "no_capacity".into();
        return Ok(result);
    }
    let days = if target == 0 {
        0
    } else {
        let denominator = capacity * 1200;
        (i128::from(target) * DAYS_PER_MONTH + denominator - 1) / denominator
    };
    let days = i32::try_from(days).map_err(|_| "date_out_of_range")?;
    let completion = today
        .add_days(days)
        .and_then(Date::iso)
        .map_err(|_| "date_out_of_range")?;
    result.completion_days = Some(days);
    result.completion_date = Some(completion);
    result.status = "ready".into();
    Ok(result)
}

fn money(value: f64) -> Result<i64, String> {
    if !value.is_finite() || value < 0.0 || value * 100.0 > crate::money::MAX_HUNDREDTHS as f64 {
        return Err("invalid_profile".into());
    }
    Ok((value * 100.0).round() as i64)
}

fn age(value: &str, today: Date) -> i32 {
    Date::parse_iso(value)
        .map(|date| date.days_until(today).max(0))
        .unwrap_or(i32::MAX)
}

#[cfg(test)]
mod tests;
