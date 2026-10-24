# Financial dashboard

The spending dashboard is now reached through **Insights → Spending** (under **More** on mobile). Reports and forecasts are adjacent sections. Budget filters display localized date ranges; persistent IDs and accounting rules are unchanged. Maintainer-confirmed validation and application testing on Linux and Android are recorded in DESKTOP.md.

All financial queries run locally in Rust. The dashboard does not change the active budget period, Today’s selected date, stored records, revision, or undo history.

## Views

The dashboard opens in **Budget Period** mode with the current active period selected. Each time the user leaves and reopens Dashboard, its local selection is initialized again from Rust’s `AppSnapshot.current_period`, which is resolved by `periods::at(state, today)`. Flutter uses that result for dropdown state; it does not calculate period boundaries or choose the last saved period. Its overview shows:

1. **Available to spend** as the main figure, with a visible whole-account inspection date. A negative balance is labeled **Budget shortfall** and remains visible without opening details.
2. Received income, spending, and **Income minus spending** for the selected date range. This difference is distinct from the available balance, which includes earlier money and existing commitments.
3. Shortcuts to **Today**, **Budget**, and **Plans** through the existing app navigation.
4. One spending-by-category chart, with exact amounts beside each category. Ranges without spending show a short message instead of an empty chart. Ranges without any activity still show carried balances and the navigation shortcuts.

**Explore details** contains four sections, all collapsed initially. Their chart widgets are built when the section opens:

- **Income and spending**: dated income and spending trends, assigned income in Budget Period mode, and essential-linked spending.
- **Balance details**: recorded cash, protected savings, unpaid obligations, allocation, and cash/savings history.
- **Bills and budget**: funding progress, period comparisons, and planned versus paid obligations.
- **Savings and goals**: goal progress, savings contributions/releases, allocation history, and period savings targets.

Dashboard charts use a fixed presentation and plain color legends. Chart-type switching and legend filtering remain optional capabilities of the reusable chart widget. Exact-value data stays available through **View data** for keyboard and screen-reader users. Donut legends are focusable buttons with visible amounts. Charts support touch and mouse tooltips, localized labels, the current theme, and reduced motion. Chronology stays left to right in both languages; Persian text and controls use RTL. Summary cards and related comparison charts share a desktop row and stack on smaller screens or enlarged text.

Charts use the MIT-licensed [FL Chart](https://pub.dev/packages/fl_chart) package. Runtime operation remains offline.

## Filters and scope

A single **View** selector offers daily, weekly, monthly, yearly, custom range, and Budget Period modes. Only the relevant date or period controls are shown. **Back to this month** returns to the current month from another selection. Budget Period is unavailable when there are no saved periods. When Rust reports no active period, Dashboard opens on the current calendar month and explains the fallback. Saved historical or upcoming periods remain available for manual selection. Entering Budget Period mode without a selected period prompts the user to choose one before any query is sent. The dashboard owns its selection; it never publishes changes to `PouchPeriodScope`. Navigation shortcuts open the existing pages with their existing selections.

- Daily uses the chosen day.
- Weekly follows the configured week start, including Saturday.
- Monthly and yearly follow the selected Gregorian or Jalali calendar.
- Custom includes both endpoints and accepts up to 3,660 days. Reversed or oversized ranges are rejected.
- Budget Period uses the selected period’s inclusive start and exclusive end, displayed as the last included date. Date-mode choices are retained but do not narrow a period selection.

Snapshot refreshes preserve a valid manual period or date-range selection. If the selected period is removed, Dashboard returns to Rust’s current period or the explained monthly fallback. The selected range is always shown. Actual activity stops at the earlier of the range end and today. A wholly future range shows an explanation instead of projected actuals. Period comparison rows show their exact overlap with the effective range. The latest 24 overlapping periods are rendered, with a visible notice when others are omitted; range totals still include the complete range.

## Metric definitions

| Metric | Authoritative source and meaning |
| --- | --- |
| Received income | `budget::income_between`, using actual receipt dates within the effective range. Expected income is excluded. |
| Period-assigned income | `budget::income_for_period`, displayed separately in Budget Period mode. Includes receipts assigned to the period through the inspection date, even when received outside its calendar dates. |
| Actual expenses | `budget::spent`, using recorded purchases, including actual bill and goal purchases. Reservations and savings allocations are not purchases. |
| Net cash movement | Dated received income minus actual expenses. Rollover is not new income. |
| Recorded cash | `budget::funding(...).cash`, including all earlier receipts and purchases. This is the recorded account balance, not a bank integration. |
| Free funds / shortfall | Existing funding engine’s free balance. Negative values remain visible as a shortfall. |
| Protected savings | Existing funding engine’s funded savings, capped by available cash after obligations. |
| Unpaid obligations | Existing funding engine’s complete reservation. Funded obligations are shown separately and capped by positive cash. |
| Allocation donut | Positive free funds, protected savings, and funded obligations. These partition positive cash. A negative free balance is shown outside the donut. |
| Categories | Stored purchase categories. Goal purchases retain their recorded category. |
| Essential-linked spending | Actual purchases linked by payment date and purchase ID to an essential bill. Other purchases are not assumed to be unnecessary; their essential status is unknown. |
| Utilization | Range spending divided by range spending plus positive closing free funds. This is a funded-capacity indicator, not an originally saved spending limit. |
| Remaining capacity | Positive closing free funds against the same capacity denominator. A zero denominator displays no applicable target. |
| Essential payments | Original amounts of essential bills due in the selected range, compared with their actual linked payments through the inspection date. Earlier payments of the same bills are included. |
| Essential funding | Outstanding essential-bill allocations from the existing forecast service, using the same funding order as Plans at the inspection date. |
| Planned versus paid | Expense obligations explicitly assigned to the comparison period, or unassigned obligations due in its displayed overlap, against linked payments through its inspection date. This is not a total discretionary-spending budget. |
| Savings contributions / releases | Positive and negative recorded allocation changes, displayed separately. Neither is counted as income or an expense. |
| Savings minimum | The saved whole-period minimum from `budget::plan_at` at the inspection date. It is not prorated for a partial date range. |
| Net allocations | Signed allocations within the displayed period overlap. Corrections can make this negative; goal funding can make contributions exceed the minimum. |
| Goal progress | Outstanding goals use `forecast::preview` to share existing savings once, in the established funding order. The first 20 are displayed with an omission notice if needed. |

Position and funding figures describe the whole account at the inspection date, not only money created during the selected range. Date-mode goal progress uses the period containing the inspection date. The main balance card shows its whole-account inspection date. Detailed metric explanations appear inside their relevant sections.

## Historical accuracy

Receipt and payment dates remain authoritative for cash-flow charts. Savings history uses signed recorded allocations minus actual goal-funded purchases. Savings form part of cash; the two balance lines must not be added together.

Cash and savings opening balances include earlier records. Each point carries an exact start and end date. Up to 90 days use daily points, up to 730 use consecutive seven-day buckets anchored at the range start, and longer ranges use calendar-month buckets, including partial first and last months. Flow buckets preserve complete totals. Balance points are bucket-end balances; they do not interpolate transactions or invent intrabucket history.

Historical corrections are read from the updated records and reconciled allocations. Dashboard queries do not reconcile, mutate, or persist state themselves. Existing mutation services own that work.

Old versions of edited or deleted obligations and goals are not retained. The dashboard therefore does not claim to reconstruct historical free-to-spend balances or original goal definitions. Position, obligation comparisons, and goal funding are recalculated from currently retained definitions at the selected inspection date. There is no invented historical spending budget.

## Implementation map

- `rust/src/dashboard/range.rs`: query validation and calendar-aware date resolution.
- `rust/src/dashboard/mod.rs`: snapshot, KPIs, category and obligation aggregation, progress, and period comparisons.
- `rust/src/dashboard/series.rs`: indexed ledger grouping and bounded chart series.
- `PouchApp::dashboard`: read-only serialized query/snapshot transport through the existing Flutter Rust Bridge, consistent with the existing serialized economic APIs.
- `flutter/lib/features/dashboard`: presentation models, screen, filter controls, chart widgets, and progress widgets.
- `PouchBridge.dashboard`: decodes Rust results without performing financial aggregation.
- `AppSnapshot.current_period`: existing Rust period resolution used to initialize Dashboard; the Flutter wrapper exposes it as `PouchSnapshot.currentPeriod`.

Money remains integer minor units in Rust and the snapshot. Checked arithmetic uses the existing safe total bound. Flutter converts amounts to floating point only for chart geometry and existing display formatting; tooltips and data rows use the original integer amounts. All filtering, totals, progress ratios, and bucketing are computed in Rust.

The ledger is indexed once per query. Chart series contain at most about 120 points. Comparison and visible goal counts are bounded independently of complete KPI totals. Forecast calls reuse the existing service; datasets with many outstanding recurring essentials should be included in manual performance acceptance.

## Manual validation

The full Linux validation and release build have passed using `validate-and-build-linux.sh`, including Rust formatting, Clippy and tests, Flutter formatting, analysis and tests, and Linux release packaging. Visual acceptance on each platform remains a manual check. Dashboard uses the existing Rust–Flutter bridge with generated adapters for its read-only query. The active-period default adds no further dependencies or Rust API changes.

From the repository root, format only the affected sources:

```bash
rustfmt --edition 2024 rust/tests/dashboard.rs
dart format flutter/lib/features/dashboard/dashboard_screen.dart flutter/lib/features/dashboard/dashboard_filters.dart flutter/test/dashboard_test.dart
```

Preserve the existing UTF-8 encoding and line-ending convention for each edited file.

Run the appropriate existing validation/build script. It covers Rust formatting, Clippy and tests, Flutter formatting, analysis and tests, and the platform build:

- Linux: `./validate-and-build-linux.sh`
- Windows desktop: `./validate-and-build-windows.ps1`
- Android: `./validate-and-build.ps1` with the existing private signing configuration.

Focused diagnostics if a full validation run reports failures:

```bash
cargo test --manifest-path rust/Cargo.toml --locked --test dashboard
cd flutter
flutter test test/dashboard_test.dart test/responsive_layout_test.dart
```

`rust/tests/dashboard.rs` covers actual versus expected income, rollover, assigned receipts outside a period, Reports reconciliation, goal payments, savings releases, historical corrections, essential links, zero/future/negative balances, inclusive dates, weekly preferences, Gregorian leap years, Jalali boundaries, range validation, large ledgers, read-only JSON queries, active-period resolution at a period boundary, no active period with empty/expired/upcoming records, and unchanged Today/Budget figures after Dashboard queries.

`flutter/test/dashboard_test.dart` includes coverage for the active-period overview, reopening after manual period/date choices, a newly resolved active period on reopening, no-active-period fallback, manual saved-period selection without an active period, preservation of manual choices during refresh, recovery when a selected period is removed, collapsed details, navigation callbacks, visible shortfalls, income-only views, the month reset, all filter modes, shared-period isolation, stale asynchronous responses, loading/error/retry behavior, empty/future views, optional chart controls, exact tooltip values, accessible chart data, English/Persian direction, three themes, and mobile/tablet/desktop widths with enlarged text. Existing shell tests cover the More-menu entry.

Manually verify on Android, Linux, and Windows:

1. Open Dashboard from More or the sidebar. Confirm Budget Period mode selects the current active period, plus the main available balance or shortfall, three activity totals, and one spending breakdown. Open each detail section and switch every date mode and budget period; check Back to this month.
2. Compare received income, payments, cash, funded obligations, and savings with Today, Budget Plan, Purchases, Plans, and Reports using identical dates and scopes.
3. Check a receipt assigned outside its dates, a paid essential bill, an unpaid obligation, a funded goal purchase, rollover, and a historical correction.
4. Inspect a Jalali new year and Gregorian leap day with each week-start preference.
5. Switch language and theme, enlarge text, resize the window, and use both keyboard and pointer/touch interactions.
6. Verify visible category amounts, exact tooltips, horizontal chart scrolling, detail/data expansion, loading, retry, and screen-reader labels. Confirm empty and income-only ranges avoid empty overview charts.
7. Follow the Today, Budget, and Plans shortcuts. Choose another period or date range in Dashboard, leave, and reopen it; confirm it returns to Rust’s current active period. Confirm Dashboard filtering and its month reset do not change Today’s date, the shared budget period, or other tabs’ calculations. Also check the monthly fallback with no periods, only expired periods, and only upcoming periods; saved periods must remain manually selectable.
8. Exercise a large backup and many outstanding essential occurrences, confirming responsive filtering and complete totals.

For future changes, confirm manual validation passed before committing and pushing. Review the diff and verify GitHub CI for the pushed commit. Keep unrelated working-tree changes outside the dashboard commit.
