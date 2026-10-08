# Financial Forecast

Financial Forecast is a main navigation page with an eye icon, labeled **پیش‌بینی مالی** in Persian. `flutter/lib/features/forecast` owns all forecast presentation. Planned Expenses owns target creation, editing, amounts, dates, payment actions and current allocation labels. It has no completion estimates or forecast controls. When no pending positive-amount targets exist, the forecast page offers a button opening Planned Expenses.

## Target and progressive disclosure

The drawer order is Today, Budget Plan, Planned Expenses, Financial Forecast, Reports, Settings & Data, About.

One selector shows pending goals and expenses in deadline/ID order. The selected name, remaining amount and calendar deadline are visible. All forecast views use the same target.

The initial page shows **Your current forecast**: estimated completion days/date and deadline status. Income, essential costs, everyday spending, configured savings, affordable contribution, deadline saving requirements, allocations and assumptions are inside **How this is calculated**.

**Explore improvements** starts collapsed. Its selector offers:

- **Spend a little less**: preserves recorded income and essential costs while previewing a 10% reduction in everyday spending, rounded upward. Users are asked to consider this only when everyday needs remain covered.
- **Income needed to meet the deadline**: keeps current everyday spending and computes the income needed for all pending deadlines and the configured savings minimum. The required income is visible alongside completion. It uses no national salary data. If an unfunded deadline has passed, no finite required income/completion is invented.

**Compare with another country** starts collapsed and initializes the Standard Forecast only while opened. It contains country selection, benchmark results, optional customization, refresh controls and expandable sources/assumptions. The country comparison evaluates the selected target's remaining amount using country benchmark income and saving capacity.

Metric grids collapse to one column on narrow screens. Completion dates use DD/MM/YYYY in the selected Gregorian/Jalali calendar, with localized Persian digits and RTL. Previews do not change the financial plan; saving or resetting optional country assumptions retains the existing explicit customization behavior.

## Calculation and data ownership

Rust owns all financial calculations, completion/extra days and comparisons. Flutter owns target/income-basis selection, localization and layout. `forecast::preview` is read-only; it never changes the financial plan, storage, revision, backup or undo history. Expected income cannot fund the recorded or recommended plan. Hypothetical required income is only a preview.

Allocation pools are computed before proposed spending or income is applied, so switching income basis preserves the same existing allocations. Each savings/expense pool is allocated once by deadline/ID. Completion includes earlier outstanding targets of the same kind and protects the other pool's deadline commitments. Country comparison independently evaluates the selected target and does not fund earlier targets a second time.

Amounts describe the current income cycle; they are not forcibly converted into a fixed 30-day month. Required contribution may exceed the configured contribution, and completion may therefore be late or unavailable. Fully allocated targets complete today. A proposed spending reduction is an assumption rather than an automatic plan change.

## Iran retrieval

The SCI 1404 urban household publication was retrieved successfully from this workstation on 2026-10-05, including with the application's user agent. It supplied the reviewed income/cost figures and thousand-rial units. The original device error was not reproduced, so no single device failure cause is confirmed.

The adapter now follows at most four HTTPS redirects within `amar.org.ir` and `www.amar.org.ir`, normalizes Persian/Arabic digits, letter variants, HTML references, directional marks and optional ezafe, and distinguishes source access, redirect, format, year, unit, validation and cache-write failures. It continues to require the reviewed year and units and never substitutes guessed statistics. Failed downloads/parsing never replace valid cached profiles or local overrides. Iran remains an **Urban household estimate**, not an employee salary. A trimmed reviewed publication fixture and parser regression cases are included.

## Manual validation

No bridge generation, compilation, formatter, lint, test or build was run for this change. The typed Rust forecast signature and snapshot changed. **Regenerate the bridge before analyzing or compiling.** Existing generated adapters are intentionally left for the manual generator.

```powershell
Set-Location F:\Projects\Rust\Pouch\flutter
flutter_rust_bridge_codegen generate
Set-Location ..
cargo fmt --manifest-path rust/Cargo.toml
cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings
cargo test --manifest-path rust/Cargo.toml
Set-Location flutter
dart format lib/main.dart lib/core/pouch_bridge.dart lib/core/pouch_models.dart lib/features/planned/planned_screen.dart lib/features/forecast test/forecast_metric_test.dart
flutter analyze
flutter test
Set-Location ..
.\validate-and-build.ps1
```

Use `validate-and-build-windows.ps1` or `validate-and-build-linux.sh` for the corresponding desktop runner.

After validation, check:

- Drawer order, eye navigation, no duplicate forecasts in Planned Expenses, allocation labels, and empty-state navigation.
- Initially collapsed improvements, country comparison and calculation details; completion/deadline status; remaining amount; both improvement choices; country controls after closing and reopening.
- Expense/goal selection, long names, partially funded goals and earlier commitments. All sections must select the same target, including rapid changes while requests are pending.
- Both improvement choices, zero/unreceived income, insufficient savings, overdue/fully funded targets and unchanged allocations across previews.
- Recorded/recommended completion days, date, extra days and comparison. A 10% spending reduction must be clearly optional; essential expenses stay fixed.
- Iran refresh on the target device, failure messages, cached offline data and preserved custom overrides. Verify all other countries and currency pairs still work.
- English/Persian, Gregorian/Jalali, narrow Android, desktop and short-window drawer scrolling.
- Unchanged saved financial records, backup compatibility and undo history after read-only forecast actions.

Added Rust regression cases cover recommendation allocation/essential-cost preservation, required-income previews with earlier commitments, overdue requirements, the reviewed Iran HTML shape, optional ezafe and distinct invalid year/unit/value/format failures. Flutter metric-grid tests also cover narrow/wide layouts and both text directions. These tests await manual execution.

The immediate SCI certificate-chain and error-category fix is documented in [Economic Profiles](ECONOMIC_PROFILES.md#temporary-sci-transport-workaround). The planned structured Iran dataset migration remains pending separate approval.
