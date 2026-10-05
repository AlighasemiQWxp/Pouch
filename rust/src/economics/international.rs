use super::{ExchangeRate, METHOD_VERSION, Observation, Profile, canada, country_currency};
use serde_json::Value;

const OECD: &str =
    "https://sdmx.oecd.org/public/rest/data/OECD.CTP.TPS,DSD_TAX_WAGES_DECOMP@DF_TW_DECOMP,2.1";
const IRAN: &str = "https://amar.org.ir/news/id/19255";

pub async fn download(client: &reqwest::Client, country: &str) -> Result<Profile, String> {
    let currency = country_currency(country, "");
    let mut observations = if country == "IR" {
        iran().await?
    } else {
        let area = match country {
            "US" => "USA",
            "GB" => "GBR",
            "DE" => "DEU",
            "AU" => "AUS",
            "NZ" => "NZL",
            _ => return Err("invalid_country".into()),
        };
        let response = client
            .get(format!(
                "{OECD}/{area}.NWE.XDC.S_C0.AW100._Z.A?startPeriod=2020&format=csvfile"
            ))
            .send()
            .await
            .map_err(|_| "retrieval_failed")?;
        let csv =
            String::from_utf8(canada::body(response).await?).map_err(|_| "invalid_response")?;
        let (year, income) = wages(&csv, area)?;
        let consumption = indicator(client, country, "NE.CON.PRVT.CN").await?;
        let population = indicator(client, country, "SP.POP.TOTL").await?;
        let cost_year = consumption
            .iter()
            .map(|(year, _)| *year)
            .filter(|year| *year <= year_now() && population.iter().any(|(other, _)| other == year))
            .max()
            .ok_or("missing_data")?;
        if (year - cost_year).abs() > 2 {
            return Err("incompatible_periods".into());
        }
        let spending = consumption
            .iter()
            .find(|(year, _)| *year == cost_year)
            .ok_or("missing_data")?
            .1
            / population
                .iter()
                .find(|(year, _)| *year == cost_year)
                .ok_or("missing_data")?
                .1;
        vec![
            observation(
                "annual_net",
                income,
                &format!("{currency}/year"),
                &year.to_string(),
                "OECD single worker, no children, average wage",
            ),
            observation(
                "annual_spending",
                spending,
                &format!("{currency}/person/year"),
                &cost_year.to_string(),
                "World Bank household consumption / population",
            ),
        ]
    };
    if let Ok(Some(local)) = exchange(client, currency).await {
        observations.push(observation(
            "cad_per_local",
            local.cad_per_unit,
            "CAD/local unit",
            &local.date,
            "Bank of Canada; TGJU for toman",
        ));
    }
    let profile = Profile {
        version: METHOD_VERSION,
        country: country.into(),
        downloaded: today(),
        observations,
    };
    profile.validate().map_err(|error| {
        if country == "IR" {
            "iran_validation_failed".into()
        } else {
            error
        }
    })?;
    Ok(profile)
}

pub async fn exchange(
    client: &reqwest::Client,
    currency: &str,
) -> Result<Option<ExchangeRate>, String> {
    if currency == "CAD" {
        return Ok(Some(ExchangeRate {
            currency: currency.into(),
            cad_per_unit: 1.0,
            date: today(),
            downloaded: today(),
        }));
    }
    if currency != "TOMAN" {
        return canada::exchange(client, currency).await;
    }
    let usd = canada::exchange(client, "USD")
        .await?
        .ok_or("conversion_required")?;
    let response = client
        .get("https://call1.tgju.org/ajax.json")
        .send()
        .await
        .map_err(|_| "retrieval_failed")?;
    let data: Value = serde_json::from_slice(&body(response, 4_000_000).await?)
        .map_err(|_| "invalid_response")?;
    let quote = &data["current"]["price_dollar_rl"];
    let (rials, date) = market_quote(quote)?;
    let exchange = ExchangeRate {
        currency: currency.into(),
        cad_per_unit: usd.cad_per_unit / (rials / 10.0),
        date: usd.date.min(date),
        downloaded: today(),
    };
    exchange.validate()?;
    Ok(Some(exchange))
}

fn market_quote(quote: &Value) -> Result<(f64, String), String> {
    let rials = quote["p"]
        .as_str()
        .ok_or("invalid_response")?
        .replace(',', "")
        .parse::<f64>()
        .map_err(|_| "invalid_response")?;
    let stamp = quote["ts"].as_str().ok_or("invalid_response")?;
    let date = stamp.get(..10).ok_or("invalid_response")?;
    let parsed = crate::Date::parse_iso(date).map_err(|_| "invalid_response")?;
    let now = crate::Date::parse_iso(&today()).map_err(|_| "invalid_response")?;
    if parsed > now
        || parsed.days_until(now) > 7
        || !rials.is_finite()
        || !(1000.0..=100_000_000.0).contains(&rials)
    {
        return Err("stale_exchange_rate".into());
    }
    Ok((rials, date.into()))
}

async fn iran() -> Result<Vec<Observation>, String> {
    let client = super::sci_tls::client()?;
    let mut url = reqwest::Url::parse(IRAN).map_err(|_| "iran_transport_failed")?;
    for _ in 0..5 {
        let response = client
            .get(url.clone())
            .send()
            .await
            .map_err(|error| super::sci_tls::request_error(&error))?;
        if response.status().is_redirection() {
            let location = response
                .headers()
                .get(reqwest::header::LOCATION)
                .and_then(|value| value.to_str().ok())
                .ok_or("iran_redirect_failed")?;
            url = url.join(location).map_err(|_| "iran_redirect_failed")?;
            if url.scheme() != "https"
                || !matches!(url.host_str(), Some("amar.org.ir" | "www.amar.org.ir"))
                || !url.username().is_empty()
                || url.password().is_some()
                || url.port_or_known_default() != Some(443)
            {
                return Err("iran_redirect_failed".into());
            }
            continue;
        }
        if !response.status().is_success() {
            return Err(format!("iran_http_status:{}", response.status().as_u16()));
        }
        let html =
            String::from_utf8(iran_body(response).await?).map_err(|_| "iran_format_changed")?;
        return iran_observations(&html);
    }
    Err("iran_redirect_failed".into())
}

async fn iran_body(mut response: reqwest::Response) -> Result<Vec<u8>, String> {
    const LIMIT: usize = 2_000_000;
    if response
        .content_length()
        .is_some_and(|length| length > LIMIT as u64)
    {
        return Err("iran_body_too_large".into());
    }
    let mut bytes = Vec::new();
    while let Some(chunk) = response.chunk().await.map_err(|_| "iran_body_failed")? {
        if bytes.len() + chunk.len() > LIMIT {
            return Err("iran_body_too_large".into());
        }
        bytes.extend_from_slice(&chunk);
    }
    Ok(bytes)
}

fn iran_observations(html: &str) -> Result<Vec<Observation>, String> {
    let html = decode_entities(html);
    let mut text = String::new();
    let mut tag = false;
    for character in html.chars() {
        match character {
            '<' => {
                tag = true;
                text.push(' ');
            }
            '>' => {
                tag = false;
            }
            _ if !tag => text.push(character),
            _ => {}
        }
    }
    let text: String = text
        .replace("&zwnj;", "")
        .replace("&nbsp;", " ")
        .chars()
        .filter(|character| {
            !character.is_whitespace()
                && !matches!(
                    *character,
                    '\u{200c}' | '\u{200d}' | '\u{200e}' | '\u{200f}' | '\u{0640}' | '\u{0650}'
                )
        })
        .map(|character| match character {
            'ي' => 'ی',
            'ك' => 'ک',
            'آ' => 'ا',
            '۰' | '٠' => '0',
            '۱' | '١' => '1',
            '۲' | '٢' => '2',
            '۳' | '٣' => '3',
            '۴' | '٤' => '4',
            '۵' | '٥' => '5',
            '۶' | '٦' => '6',
            '۷' | '٧' => '7',
            '۸' | '٨' => '8',
            '۹' | '٩' => '9',
            '٬' => ',',
            _ => character,
        })
        .collect();
    let text = text
        .replace("هزینهی", "هزینه")
        .replace("سالانهییک", "سالانهیک");
    if !text.contains("متوسطدرامداظهارشدهسالانهیکخانوارشهری")
        || !text.contains("متوسطهزینهکلخالصسالانهیکخانوارشهری")
    {
        return Err("iran_format_changed".into());
    }
    if !text.contains("درسال1404") {
        return Err("iran_year_changed".into());
    }
    let amount = |prefix: &str| -> Result<f64, String> {
        let tail = text.split_once(prefix).ok_or("iran_format_changed")?.1;
        let number: String = tail
            .chars()
            .take_while(|character| character.is_ascii_digit() || *character == ',')
            .collect();
        if !tail[number.len()..].starts_with("هزارریال") {
            return Err("iran_unit_changed".into());
        }
        let value = number
            .replace(',', "")
            .parse::<f64>()
            .map_err(|_| "iran_format_changed")?
            * 100.0;
        if !value.is_finite() || !(1_000_000.0..=10_000_000_000.0).contains(&value) {
            return Err("iran_validation_failed".into());
        }
        Ok(value)
    };
    let income = amount("متوسطدرامداظهارشدهسالانهیکخانوارشهری")?;
    let spending = amount("متوسطهزینهکلخالصسالانهیکخانوارشهری")?;
    Ok(vec![
        observation("annual_net", income, "TOMAN/household/year", "1404", IRAN),
        observation(
            "annual_spending",
            spending,
            "TOMAN/household/year",
            "1404",
            IRAN,
        ),
    ])
}

fn decode_entities(html: &str) -> String {
    let mut result = String::new();
    let mut rest = html;
    while let Some(start) = rest.find('&') {
        result.push_str(&rest[..start]);
        rest = &rest[start..];
        if let Some(end) = rest.find(';').filter(|end| *end <= 12) {
            let entity = &rest[1..end];
            let decoded = match entity {
                "nbsp" => Some(' '),
                "zwnj" => Some('\u{200c}'),
                _ => entity
                    .strip_prefix("#x")
                    .or_else(|| entity.strip_prefix("#X"))
                    .and_then(|value| u32::from_str_radix(value, 16).ok())
                    .or_else(|| {
                        entity
                            .strip_prefix('#')
                            .and_then(|value| value.parse().ok())
                    })
                    .and_then(char::from_u32),
            };
            if let Some(character) = decoded {
                result.push(character);
                rest = &rest[end + 1..];
                continue;
            }
        }
        result.push('&');
        rest = &rest[1..];
    }
    result.push_str(rest);
    result
}

async fn indicator(
    client: &reqwest::Client,
    country: &str,
    indicator: &str,
) -> Result<Vec<(i32, f64)>, String> {
    let response = client.get(format!("https://api.worldbank.org/v2/country/{country}/indicator/{indicator}?format=json&date=2020:{}&per_page=20", year_now()))
        .send().await.map_err(|_| "retrieval_failed")?;
    let data: Value =
        serde_json::from_slice(&canada::body(response).await?).map_err(|_| "invalid_response")?;
    let rows = data[1].as_array().ok_or("invalid_response")?;
    let mut values = Vec::new();
    for row in rows {
        if row["indicator"]["id"] != indicator || row["country"]["id"] != country {
            return Err("invalid_response".into());
        }
        if row["value"].is_null() {
            continue;
        }
        let year = row["date"]
            .as_str()
            .ok_or("invalid_response")?
            .parse::<i32>()
            .map_err(|_| "invalid_response")?;
        let value = row["value"].as_f64().ok_or("invalid_response")?;
        if !value.is_finite() || value <= 0.0 || values.iter().any(|(other, _)| *other == year) {
            return Err("invalid_response".into());
        }
        values.push((year, value));
    }
    Ok(values)
}

fn wages(contents: &str, area: &str) -> Result<(i32, f64), String> {
    let mut reader = csv::Reader::from_reader(contents.as_bytes());
    let headers = reader.headers().map_err(|_| "invalid_response")?.clone();
    let mut latest: Option<(i32, f64)> = None;
    let mut years = std::collections::BTreeSet::new();
    for row in reader.records() {
        let row = row.map_err(|_| "invalid_response")?;
        let get = |name: &str| canada::field(&row, &headers, name);
        if get("REF_AREA")? != area
            || get("MEASURE")? != "NWE"
            || get("UNIT_MEASURE")? != "XDC"
            || get("HOUSEHOLD_TYPE")? != "S_C0"
            || get("INCOME_PRINCIPAL")? != "AW100"
            || get("INCOME_SPOUSE")? != "_Z"
            || get("CIVIL_STATUS")? != "_Z"
            || get("FREQ")? != "A"
            || get("UNIT_MULT")? != "0"
            || get("DATAFLOW")? != "OECD.CTP.TPS:DSD_TAX_WAGES_DECOMP@DF_TW_DECOMP(2.1)"
        {
            return Err("invalid_response".into());
        }
        if get("OBS_STATUS")? != "A" {
            continue;
        }
        let year = get("TIME_PERIOD")?
            .parse::<i32>()
            .map_err(|_| "invalid_response")?;
        let value = get("OBS_VALUE")?
            .parse::<f64>()
            .map_err(|_| "invalid_response")?;
        if !value.is_finite() || value <= 0.0 || year > year_now() {
            return Err("invalid_response".into());
        }
        if !years.insert(year) {
            return Err("invalid_response".into());
        }
        if latest.is_none_or(|(other, _)| year > other) {
            latest = Some((year, value));
        }
    }
    latest.ok_or_else(|| "missing_data".into())
}

fn observation(indicator: &str, value: f64, unit: &str, period: &str, source: &str) -> Observation {
    Observation {
        indicator: indicator.into(),
        value,
        unit: unit.into(),
        period: period.into(),
        released: source.into(),
    }
}

async fn body(mut response: reqwest::Response, limit: usize) -> Result<Vec<u8>, String> {
    if !response.status().is_success()
        || response
            .content_length()
            .is_some_and(|length| length > limit as u64)
    {
        return Err("retrieval_failed".into());
    }
    let mut bytes = Vec::new();
    while let Some(chunk) = response.chunk().await.map_err(|_| "retrieval_failed")? {
        if bytes.len() + chunk.len() > limit {
            return Err("invalid_response".into());
        }
        bytes.extend_from_slice(&chunk);
    }
    Ok(bytes)
}

fn today() -> String {
    chrono::Utc::now().format("%Y-%m-%d").to_string()
}
fn year_now() -> i32 {
    use chrono::Datelike;
    chrono::Utc::now().year()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn iran_uses_reported_household_values_and_converts_thousand_rials_to_tomans() {
        let html = "در سال 1404 <p>متوسط هزينه‌ی كل خالص سالانه‌ی يك خانوار شهري 3,919,427 هزار ريال</p><p>متوسط درامد اظهار شده‌ سالانه‌ يك خانوار شهری 4,846,105 هزار ريال</p>";
        let values = iran_observations(html).expect("official survey shape");
        assert_eq!(values[0].value, 484_610_500.0);
        assert_eq!(values[1].value, 391_942_700.0);
        assert!(iran_observations(&html.replace("هزار ريال", "تومان")).is_err());
        assert!(iran_observations(&html.replace("1404", "1403")).is_err());
        let entities = html.replace('\u{200c}', "&zwnj;");
        assert_eq!(
            iran_observations(&entities).expect("HTML entities")[0].value,
            values[0].value
        );
        let localized = html
            .replace("1404", "۱۴۰۴")
            .replace("4,846,105", "۴٬۸۴۶٬۱۰۵")
            .replace("3,919,427", "٣٬٩١٩٬٤٢٧")
            .replace("درامد", "درآمد")
            .replace(' ', "&#160;")
            .replace('\u{200c}', "&#x200c;");
        let localized_values = iran_observations(&localized).expect("localized survey");
        assert_eq!(localized_values[0].value, values[0].value);
        assert_eq!(localized_values[1].value, values[1].value);
    }

    #[test]
    fn iran_publication_fixture_and_optional_ezafe_are_supported() {
        let html = include_str!("fixtures/iran_1404.html");
        let values = iran_observations(html).expect("reviewed publication");
        assert_eq!(values[0].value, 484_610_500.0);
        assert_eq!(values[1].value, 391_942_700.0);
        let plain = html
            .replace("&zwnj;ی", "")
            .replace("<span>", "<b>")
            .replace("</span>", "</b>");
        assert_eq!(
            iran_observations(&plain).expect("optional ezafe")[1].value,
            values[1].value
        );
        assert_eq!(
            iran_observations(&html.replace("1404", "1403")).expect_err("year"),
            "iran_year_changed"
        );
        assert_eq!(
            iran_observations(&html.replace("هزار ريال", "تومان")).expect_err("unit"),
            "iran_unit_changed"
        );
        assert_eq!(
            iran_observations(&html.replace("4,846,105", "0")).expect_err("value"),
            "iran_validation_failed"
        );
        assert_eq!(
            iran_observations("در سال 1404 صفحه ورود").expect_err("format"),
            "iran_format_changed"
        );
    }

    #[test]
    fn market_quote_requires_a_recent_date_and_valid_price() {
        let quote = serde_json::json!({"p":"2,000,000", "ts": format!("{} 12:00:00", today())});
        assert_eq!(market_quote(&quote).expect("valid quote").0, 2_000_000.0);
        assert!(market_quote(&serde_json::json!({"p":"0", "ts":"2020-01-01 12:00:00"})).is_err());
    }
}
