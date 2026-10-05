use super::{ExchangeRate, METHOD_VERSION, Observation, Profile};
use serde_json::{Value, json};

pub const INDICATORS: [(&str, &str, &str); 8] = [
    ("gross", "CAD/year", "2025"),
    ("net", "CAD/year", "2025"),
    ("consumption", "CAD/year", "2023"),
    ("shelter", "CAD/year", "2023"),
    ("groceries", "CAD/year", "2023"),
    ("operations", "CAD/year", "2023"),
    ("cpi_2023", "index:2002=100", "2023"),
    ("cpi_2025", "index:2002=100", "2025"),
];
const OECD: &str = "https://sdmx.oecd.org/public/rest/data/OECD.CTP.TPS,DSD_TAX_WAGES_DECOMP@DF_TW_DECOMP,2.1/CAN.GWE+NWE.XDC.S_C0.AW100._Z.A?startPeriod=2025&endPeriod=2025&format=csvfile";
const WDS: &str = "https://www150.statcan.gc.ca/t1/wds/rest/getDataFromVectorsAndLatestNPeriods";
const MAX_RESPONSE: usize = 200_000;

pub async fn download(client: &reqwest::Client) -> Result<Profile, String> {
    let response = client
        .get(OECD)
        .send()
        .await
        .map_err(|_| "retrieval_failed")?;
    let csv = String::from_utf8(body(response).await?).map_err(|_| "invalid_response")?;
    let mut observations = wages(&csv)?;
    let request = json!([
        {"vectorId":54530203,"latestN":1}, {"vectorId":54530207,"latestN":1},
        {"vectorId":54530205,"latestN":1}, {"vectorId":54530213,"latestN":1},
        {"vectorId":41693271,"latestN":3}
    ]);
    let response = client
        .post(WDS)
        .json(&request)
        .send()
        .await
        .map_err(|_| "retrieval_failed")?;
    let data: Value =
        serde_json::from_slice(&body(response).await?).map_err(|_| "invalid_response")?;
    for (indicator, vector, year, product) in [
        ("consumption", 54530203, 2023, 11100224),
        ("shelter", 54530207, 2023, 11100224),
        ("groceries", 54530205, 2023, 11100224),
        ("operations", 54530213, 2023, 11100224),
        ("cpi_2023", 41693271, 2023, 18100005),
        ("cpi_2025", 41693271, 2025, 18100005),
    ] {
        observations.push(statistic(&data, indicator, vector, year, product)?);
    }
    let profile = Profile {
        version: METHOD_VERSION,
        country: "CA".into(),
        downloaded: today(),
        observations,
    };
    profile.validate()?;
    Ok(profile)
}

pub async fn exchange(
    client: &reqwest::Client,
    currency: &str,
) -> Result<Option<ExchangeRate>, String> {
    let series = match currency {
        "USD" => "FXUSDCAD",
        "EUR" => "FXEURCAD",
        "GBP" => "FXGBPCAD",
        "AUD" => "FXAUDCAD",
        "NZD" => "FXNZDCAD",
        "CAD" | "TOMAN" => return Ok(None),
        _ => return Err("invalid_currency".into()),
    };
    let response = client
        .get(format!(
            "https://www.bankofcanada.ca/valet/observations/{series}/json?recent=1"
        ))
        .send()
        .await
        .map_err(|_| "retrieval_failed")?;
    let data: Value =
        serde_json::from_slice(&body(response).await?).map_err(|_| "invalid_response")?;
    let row = data["observations"]
        .as_array()
        .filter(|rows| rows.len() == 1)
        .and_then(|rows| rows.first())
        .ok_or("invalid_response")?;
    let exchange = ExchangeRate {
        currency: currency.into(),
        cad_per_unit: row[series]["v"]
            .as_str()
            .and_then(|value| value.parse().ok())
            .ok_or("invalid_response")?,
        date: row["d"].as_str().ok_or("invalid_response")?.into(),
        downloaded: today(),
    };
    exchange.validate()?;
    Ok(Some(exchange))
}

pub(super) async fn body(mut response: reqwest::Response) -> Result<Vec<u8>, String> {
    if !response.status().is_success()
        || response
            .content_length()
            .is_some_and(|length| length > MAX_RESPONSE as u64)
    {
        return Err("retrieval_failed".into());
    }
    let mut bytes = Vec::new();
    while let Some(chunk) = response.chunk().await.map_err(|_| "retrieval_failed")? {
        if bytes.len() + chunk.len() > MAX_RESPONSE {
            return Err("invalid_response".into());
        }
        bytes.extend_from_slice(&chunk);
    }
    Ok(bytes)
}

pub(super) fn field<'a>(
    row: &'a csv::StringRecord,
    headers: &csv::StringRecord,
    name: &str,
) -> Result<&'a str, String> {
    let index = headers
        .iter()
        .position(|header| header == name)
        .ok_or("invalid_response")?;
    row.get(index).ok_or_else(|| "invalid_response".into())
}

fn wages(contents: &str) -> Result<Vec<Observation>, String> {
    let mut reader = csv::Reader::from_reader(contents.as_bytes());
    let headers = reader.headers().map_err(|_| "invalid_response")?.clone();
    let mut values = Vec::new();
    for row in reader.records() {
        let row = row.map_err(|_| "invalid_response")?;
        let get = |name: &str| field(&row, &headers, name);
        if get("REF_AREA")? != "CAN"
            || get("UNIT_MEASURE")? != "XDC"
            || get("HOUSEHOLD_TYPE")? != "S_C0"
            || get("INCOME_PRINCIPAL")? != "AW100"
            || get("TIME_PERIOD")? != "2025"
            || get("FREQ")? != "A"
            || get("UNIT_MULT")? != "0"
            || get("OBS_STATUS")? != "A"
            || get("INCOME_SPOUSE")? != "_Z"
            || get("CIVIL_STATUS")? != "_Z"
            || get("DATAFLOW")? != "OECD.CTP.TPS:DSD_TAX_WAGES_DECOMP@DF_TW_DECOMP(2.1)"
        {
            return Err("invalid_response".into());
        }
        let indicator = match get("MEASURE")? {
            "GWE" => "gross",
            "NWE" => "net",
            _ => return Err("invalid_response".into()),
        };
        values.push(Observation {
            indicator: indicator.into(),
            value: get("OBS_VALUE")?.parse().map_err(|_| "invalid_response")?,
            unit: "CAD/year".into(),
            period: "2025".into(),
            released: "Taxing Wages 2026".into(),
        });
    }
    if values.len() != 2 {
        return Err("invalid_response".into());
    }
    Ok(values)
}

fn statistic(
    data: &Value,
    indicator: &str,
    vector: i64,
    year: i32,
    product: i64,
) -> Result<Observation, String> {
    let rows = data.as_array().ok_or("invalid_response")?;
    let matches: Vec<_> = rows
        .iter()
        .filter(|row| row["object"]["vectorId"].as_i64() == Some(vector))
        .collect();
    if matches.len() != 1 {
        return Err("invalid_response".into());
    }
    let row = matches[0];
    let object = &row["object"];
    if row["status"] != "SUCCESS"
        || object["responseStatusCode"] != 0
        || object["productId"] != product
    {
        return Err("invalid_response".into());
    }
    let period = format!("{year}-01-01");
    let points = object["vectorDataPoint"]
        .as_array()
        .ok_or("invalid_response")?;
    let matches: Vec<_> = points
        .iter()
        .filter(|point| point["refPer"].as_str() == Some(&period))
        .collect();
    if matches.len() != 1 {
        return Err("review_required".into());
    }
    let point = matches[0];
    if point["scalarFactorCode"] != 0
        || point["statusCode"] != 0
        || point["securityLevelCode"] != 0
        || point["symbolCode"] != 0
        || point["frequencyCode"] != 12
    {
        return Err("review_required".into());
    }
    Ok(Observation {
        indicator: indicator.into(),
        value: point["value"].as_f64().ok_or("invalid_response")?,
        unit: if product == 18100005 {
            "index:2002=100".into()
        } else {
            "CAD/year".into()
        },
        period: year.to_string(),
        released: point["releaseTime"]
            .as_str()
            .ok_or("invalid_response")?
            .into(),
    })
}

fn today() -> String {
    chrono::Utc::now().format("%Y-%m-%d").to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn suppression_and_unreviewed_units_are_rejected() {
        let mut data = json!([{"status":"SUCCESS","object":{"vectorId":54530203,"productId":11100224,
            "responseStatusCode":0,"vectorDataPoint":[{"refPer":"2023-01-01","value":44074,
            "scalarFactorCode":0,"statusCode":0,"symbolCode":0,"securityLevelCode":0,
            "frequencyCode":12,"releaseTime":"2026-09-18T08:30"}]}}]);
        assert!(statistic(&data, "consumption", 54530203, 2023, 11100224).is_ok());
        data[0]["object"]["vectorDataPoint"][0]["statusCode"] = json!(1);
        assert!(statistic(&data, "consumption", 54530203, 2023, 11100224).is_err());
        data[0]["object"]["vectorDataPoint"][0]["statusCode"] = json!(0);
        data[0]["object"]["vectorDataPoint"][0]["scalarFactorCode"] = json!(3);
        assert!(statistic(&data, "consumption", 54530203, 2023, 11100224).is_err());
    }
    #[test]
    fn oecd_worker_dimensions_and_net_gross_values_are_separate() {
        let csv = "DATAFLOW,REF_AREA,MEASURE,UNIT_MEASURE,HOUSEHOLD_TYPE,INCOME_PRINCIPAL,INCOME_SPOUSE,FREQ,TIME_PERIOD,OBS_VALUE,DECIMALS,UNIT_MULT,OBS_STATUS,CIVIL_STATUS\nOECD.CTP.TPS:DSD_TAX_WAGES_DECOMP@DF_TW_DECOMP(2.1),CAN,NWE,XDC,S_C0,AW100,_Z,A,2025,68738.15807219,2,0,A,_Z\nOECD.CTP.TPS:DSD_TAX_WAGES_DECOMP@DF_TW_DECOMP(2.1),CAN,GWE,XDC,S_C0,AW100,_Z,A,2025,92400.82826182,2,0,A,_Z\n";
        let result = wages(csv).expect("reviewed worker scenario");
        assert_eq!(result[0].indicator, "net");
        assert_eq!(result[1].indicator, "gross");
        assert!(wages(&csv.replace("S_C0", "S_C2")).is_err());
        assert!(wages(&csv.replace("XDC", "USD")).is_err());
    }
}
