# Economic profiles and Standard Forecast

Automatic retrieval is enabled for Canada, Iran, United States, United Kingdom, Germany, Australia and New Zealand. The Settings option Custom is not a country; it does not invent an economic profile. All source changes still require manual Rust/Flutter validation and device acceptance.

## Sources and scenarios

| Countries | Income | Living costs | Scenario |
| --- | --- | --- | --- |
| Canada | OECD modeled net annual earnings, single worker without children at average wage | Statistics Canada one-person consumption, CPI adjusted | Existing Canada worker scenario |
| US, UK, Germany, Australia, New Zealand | OECD modeled net annual earnings, same worker profile | World Bank household consumption in local currency divided by population, matching spending/population year | Worker income with national per-person spending benchmark |
| Iran | SCI reported urban household annual income | SCI urban household annual spending, same survey year | Urban household scenario, not one worker's salary |

OECD adapter: `OECD.CTP.TPS,DSD_TAX_WAGES_DECOMP@DF_TW_DECOMP,2.1`; `USA`, `GBR`, `DEU`, `AUS`, `NZL`; measure `NWE`, unit `XDC`, household `S_C0`, wage `AW100`, spouse `_Z`, annual, unit multiplier zero, observation status `A`. Retrieve the latest valid year since 2020; validate dimensions, duplicate years and numeric values. World Bank indicators `NE.CON.PRVT.CN` and `SP.POP.TOTL` use their newest common year. Income and spending may be at most two years apart, and each period is exposed. Consumption is a national accounts benchmark, including imputed and third-party spending; it is not a city-specific cash budget. No arbitrary cost percentage, GDP-as-salary substitution or missing-data zero is used.

Iran adapter retrieves the reviewed SCI 1404 publication at https://amar.org.ir/news/id/19255, validates the year and explicit urban income/spending labels and thousand-rial units, and converts each thousand rials to 100 traditional toman. Observed official annual values on 2026-10-04: household income 4,846,105 thousand rials; spending 3,919,427 thousand rials. These are parser test references, not fallback data. The parser handles HTML tags, zero-width joiner entities and Arabic/Persian letter variants. A changed year or publication format requires adapter review. The source includes non-cash income and income from business and transfers; its saving difference must not be presented as guaranteed spendable cash or individual take-home salary. The main UI labels Iran as an urban household estimate and uses household income labels. Customize can supply an individual net-income scenario.

Canada retains its reviewed mapping: OECD `CAN.GWE+NWE.XDC.S_C0.AW100._Z.A`, 2025; Statistics Canada table 11-10-0224-01 one-person 2023 consumption vectors 54530203, shelter 54530207, groceries 54530205, operations 54530213; CPI table 18-10-0005-01 vector 41693271 for 2023/2025. Net wage / 12; essential costs = shelter + groceries + operations adjusted by CPI(2025)/CPI(2023), / 12; other consumption is daily spending / 365.25. New unmatched periods trigger review.

The scenarios are estimates with different statistical populations, especially Iran. They are not interchangeable individual salary quotes, housing offers or guarantees. Source periods and assumptions remain inspectable and editable. No future inflation, salary growth, interest or investment return is assumed.

## Currency conversion

Bank of Canada Valet provides CAD per USD, EUR, GBP, AUD and NZD using the latest published business-day observations. CAD per CAD is exactly one. TGJU's public `https://call1.tgju.org/ajax.json` supplies `current.price_dollar_rl.p` (free-market rials per USD) and its `ts` observation timestamp. Rials are divided by ten to obtain traditional toman. CAD per toman = CAD per USD / toman per USD. The timestamp must be valid, non-future and at most seven days old when retrieved. No stale official Iranian exchange rate is substituted.

For any supported pair, destination units per goal-currency unit = CAD per goal-currency unit / CAD per destination unit. Both quote dates remain inspectable; cached quotes can have different dates. Toman conversions use a market indication, not a transaction quote. Changing a forecast country does not change stored account currency or rescale recorded amounts. Currency redenomination is not inferred from an unchanged currency code. An explicit custom rate takes precedence for its matching goal currency. Missing FX does not discard valid economic statistics; same-currency scenarios still work. Cross-currency forecasts show an unavailable conversion rather than inventing a rate.

## Calculations and interface

The personal forecast allocates registered savings once in deadline/ID priority order. Standard Forecast uses that selected item's remaining amount and evaluates it independently in the selected country. Earlier outstanding goals are not additionally funded by a country comparison; it is a what-if scenario for the selected goal.

Amounts use checked integer hundredths and ceiling division. A month is 365.25 / 12 days. Required monthly saving = converted remaining amount × days per month / days until selected target. Required monthly income = benchmark monthly living costs + required monthly saving. An unfunded past deadline has no finite required monthly amount. Benchmark saving capacity = max(benchmark income − living costs, 0). Completion days = remaining amount / benchmark daily saving capacity, rounded upward; completion date = today + completion days. Zero capacity produces no finite date; already funded targets complete today. Full goal and remaining goal are converted separately. Expected income never funds the preview.

The main UI in the dedicated Financial Forecast page shows the country selector, converted remaining target, benchmark income, achievable saving capacity and days/date. Full converted target, required income/saving, benchmark costs, source observations, quote basis, dates and methodology are under one expandable details section. Completion uses the selected Gregorian/Jalali calendar and DD/MM/YYYY order; Persian digits and RTL are preserved. Financial Forecast separately shows extra days beyond the target when delayed.

## Ownership, caching and privacy

Iran parsing normalizes Persian/Arabic digits, Arabic thousands separators, Arabic letter variants, the income spelling with alef-madda, and decimal/hexadecimal HTML character references. The adapter still requires the reviewed 1404 urban household scenario and thousand-rial units; it does not substitute fixed statistics or guess a new survey. Source access failure, unrecognized survey format and cache-write failure have distinct localized messages. SCI was retrieved successfully from this workstation on 2026-10-05 with the application user agent. The original device failure was not reproduced; successful refresh still requires device acceptance. The parser now also tolerates optional ezafe and directional marks and distinguishes year, unit and validation errors. Bounded redirects are supported only on the official SCI HTTPS hosts.

Forecast metrics now use shaded, aligned label/value rows that stack on narrow widths, with goal summary, results and economic assumptions headings. Source details remain expandable and calendar/digit localization remains unchanged.

Rust `economics` owns requests, adapters, validation, conversion and calculations. Flutter owns display and optional customization through the existing JSON API. The companion Financial Forecast changes require typed bridge regeneration; financial storage schemas are unchanged. `EconomicStore` retains atomic cache writes, recovery copy and existing valid Canada cache compatibility. Economic downloads expire after 30 days; FX observations request refresh after seven days. Offline cached results are labeled as older where applicable. A failed or invalid refresh leaves previously valid data intact. Custom assumptions stay local and remain in the existing backups.

Only public country, indicator, worker scenario and currency identifiers are sent to providers. No goals, amounts, savings, income records or personal financial history leave the device. HTTPS hosts are fixed; redirects are rejected except for up to four HTTPS redirects within the two official SCI hosts, timeout is 20 seconds per request, and bodies are bounded while streamed: 200 KB for structured OECD/World Bank/Bank of Canada responses; 2 MB for the SCI page; 4 MB for TGJU's market document. Only the selected public market quote is persisted. No API key or paid service was added.

## Manual validation

Run the existing Windows or Linux validation script for the target platform. The new Standard Forecast fields are inside existing JSON strings, so these changes do not require bridge regeneration. The companion Financial Forecast changes require bridge regeneration before any compilation; follow [Financial Forecast](FINANCIAL_FORECAST.md).

1. Run formatting, Rust compilation/clippy/tests, Flutter analysis/tests and the target build manually. New Rust coverage includes every catalog country, cross conversion, required salary/savings, immutable preview state, malformed profiles and Iranian units/HTML/FX timestamps.
2. Online, select each of the seven countries with same-currency and cross-currency goals, including TOMAN. Inspect reference years, source amounts and both quote dates. Confirm the full target and remaining amount are different for partly funded goals.
3. Compare required monthly income/saving with target date changes; the completion estimate uses benchmark capacity rather than the required saving amount. Zero or negative benchmark surplus must show no finite completion date.
4. Confirm Iran visibly uses the household basis and inspect non-cash income limitations. A household estimate must not be mistaken for one worker's salary.
5. Relaunch offline after successful retrieval; retain valid profiles and rates. Try an initial offline load, failed provider request, malformed response and missing conversion. No invented numbers or lost records.
6. Switch countries/goals quickly during downloads; outdated responses must not replace the new selection. Changing Settings country refreshes the initial country. Compare records and undo state before/after all read-only actions.
7. Test fully funded, overdue, no income, extreme amount/date overflow and shared savings. Verify Financial Forecast monthly requirements subtract savings and delayed dates show correct extra days.
8. Check English/Persian, Gregorian/Jalali, narrow/mobile/desktop and RTL. Verify readable metrics and DD/MM/YYYY completion dates.

Public API probes and source inspection do not establish Rust/Flutter compilation, generated bridge, live layout or device acceptance.

## References

- OECD data and API: https://www.oecd.org/en/data/insights/data-explainers/2024/09/api.html
- Statistics Canada WDS: https://www.statcan.gc.ca/en/developers/wds/user-guide
- World Bank API: https://datahelpdesk.worldbank.org/knowledgebase/articles/889392
- SCI urban household survey: https://amar.org.ir/news/id/19255
- Bank of Canada Valet: https://www.bankofcanada.ca/valet/docs
- TGJU free-market USD indication: https://www.tgju.org/profile/price_dollar_rl

## Temporary SCI transport workaround

On 2026-10-05 SCI supplied its current site certificate without its issuer, Certum DV TLS G2 R39 CA, and included unrelated older chain certificates. Windows HTTP access succeeded, but independent CA-bundle verification failed with an unknown issuer. Supplying the fingerprint-verified intermediate from Certum restored full-chain verification and HTTP 200 access.

`rust/src/economics/sci_tls.rs` creates a separate SCI-only client. Its custom verifier supplies the bundled intermediate to Rustls's normal WebPKI verifier. It does not add an intermediate or server certificate to the trusted root store. Only the two official SCI names receive supplementation. Hostname, date, root-chain and handshake-signature verification remain enabled. Redirect host/HTTPS limits, body bounds and timeout remain unchanged. Other country/FX clients are unchanged.

The direct Rustls and WebPKI dependencies match packages already in Cargo.lock. Reqwest and Rustls are pinned to the reviewed compatible versions because `use_preconfigured_tls` requires the same Rustls type/version. Review this adapter when updating either dependency. No package versions were upgraded by this fix.

Iran refresh distinguishes `iran_tls_failed`, `iran_transport_failed`, `iran_timeout`, `iran_http_status:<status>`, `iran_body_failed`, `iran_body_too_large`, existing parser/year/unit/validation categories, and `iran_cache_failed`. Underlying errors are classified without debug logs or exposure of user data. Profile validation precedes cache replacement; downloads and previews never change user overrides. Failed refresh continues displaying valid cached results.

The SCI HTML adapter remains a temporary, fragile source path: its reviewed phrases, 1404 year and thousand-rial units are deliberately unchanged. Statistical assumptions and forecast calculations are unchanged. A later, separately approved migration should download an authenticated, reviewed/versioned economic JSON dataset derived from official SCI publications, preserving provenance, units, year and urban-household labeling. That migration is not implemented here.

Manual validation for this fix (bridge API signatures did not change, so regeneration is unnecessary):

```powershell
Set-Location F:\Projects\Rust\Pouch
cargo fmt --manifest-path rust/Cargo.toml
cargo clippy --manifest-path rust/Cargo.toml --all-targets --locked -- -D warnings
cargo test --manifest-path rust/Cargo.toml --locked
Set-Location flutter
dart format lib/features/forecast/standard_forecast_section.dart
flutter analyze
flutter test
Set-Location ..
# Android: set the existing private signing file first.
$env:POUCH_SIGNING_PROPERTIES = "C:\Private\Pouch\signing.properties"
.\validate-and-build.ps1
# Windows:
.\validate-and-build-windows.ps1
```

Replace the example signing path with the existing private file. Windows does not require Android signing. The Windows script checks formatting across `lib` and `test`; format any reported files manually before rerunning it.

Security tests cover successful completion of the missing chain, both SCI hostnames, unrelated-host scoping, incorrect hostname, expired/not-yet-valid leaf, an untrusted root and a corrupted certificate signature. These tests and project builds were not run automatically.

On Android and the extracted Windows bundle, force Iran refresh and check it succeeds. Then check an offline refresh preserves cached data and custom overrides, and verify the six other countries still refresh. Exercise existing parser/year/unit failure tests and cache recovery tests. The earlier independent TLS probe does not prove this new Rust client or either app build; manual compilation, tests and device acceptance remain required.
