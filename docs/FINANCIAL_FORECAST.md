# Financial Forecast

Rust owns forecasting, amounts, dates, allocations, assumptions, and validation. Flutter owns selectors, presentation, localization, and temporary loading state. Queries never change records, storage, revision, or undo history.

## Personal period selection

Personal Forecast places a named period selector at the top, defaulting to the active period. Its selection is shared with Budget Plan, Today, and Plans, with a short calculation-context explanation beneath each selector. Today keeps its selected calendar date. Rust supplies the same period summaries used by Budget Plan: actual received income, spending, carried free funds, reserved expenses, protected savings, and dates. Rust also supplies the targets pending at the period's inspection date and associated with that period, including targets due outside its date range. Existing unassigned targets keep their prior visibility. Actual cash always follows receipt/payment dates; assigning income to a period never creates or duplicates money. Historical inspection uses the last included day; future inspection uses the first day.

Historical periods show actual spending, planned minimum savings, actual period savings contributions, and closing balances. An optional target projection is explicitly a scenario from that historical closing date. It does not rewrite history.

Daily discretionary spending uses observed purchases per elapsed day, or the Rust-funded recommendation when there is no spending history. Linked bill/goal payments are excluded from discretionary spending. Existing allocations are shared once in deadline/ID order, and reservations remain distinct from actual payments.

Opening free cash is available once during the remaining horizon. Projections beyond that horizon assume a similar rate of actually received period income, unchanged spending and commitments, and no repeated opening balance. A missing expected payment creates no income. Insufficient capacity produces an unavailable completion estimate rather than invented money.

Explore improvements offers a read-only 10% reduction in everyday spending or hypothetical additional income needed for outstanding commitments. An unfunded overdue deadline has no finite required-income answer. Hypothetical income does not increase actual allocations or spending recommendations.

## Independent Standard Forecast

Country comparison keeps its own target selector and always uses today. Selecting a personal period or personal target does not change its inputs or trigger a country reload. Existing country providers, benchmarks, monthly methodology, exchange conversion, customization, refresh/error handling, offline cache, and source disclosures remain maintained.

Country results estimate the selected target's remaining allocation using the existing benchmark methodology. They do not apply the personal period's horizon or repeat a rollover balance. Provider details and limitations remain in [Economic Profiles](ECONOMIC_PROFILES.md).

## Presentation

Desktop uses persistent navigation; mobile uses a compact bar and More sheet. Personal summaries precede target projections. Improvements and country comparisons are progressively disclosed. Responsive metrics, local Gregorian/Jalali dates, localized digits, English LTR and Persian RTL are shared with the application design system.

## Iran retrieval

The SCI 1404 urban household publication was retrieved successfully from this workstation on 2026-10-05, including with the application's user agent. It supplied the reviewed income/cost figures and thousand-rial units. The original device error was not reproduced, so no single device failure cause is confirmed.

The adapter now follows at most four HTTPS redirects within `amar.org.ir` and `www.amar.org.ir`, normalizes Persian/Arabic digits, letter variants, HTML references, directional marks and optional ezafe, and distinguishes source access, redirect, format, year, unit, validation and cache-write failures. It continues to require the reviewed year and units and never substitutes guessed statistics. Failed downloads/parsing never replace valid cached profiles or local overrides. Iran remains an **Urban household estimate**, not an employee salary. A trimmed reviewed publication fixture and parser regression cases are included.

## Manual validation

Bindings were generated with the installed Flutter Rust Bridge generator in source-parsing mode, without compilation. This proves generation only; it does not establish Rust type correctness or runtime integration. Follow the exact commands and acceptance sequence in [Desktop validation](DESKTOP.md#explicit-period-redesign-validation).

Check personal historical/current/future period selection, pending-at-date targets, empty/expired periods, paid targets, recorded/recommended scenarios, required-income failures, and rapid selector changes. Confirm Standard Forecast keeps its own target/country and uses today. Compare backups and revisions before/after read-only previews. Verify the country refresh, cache, custom assumptions, and provider failure behavior alongside calendar/locale switching.
