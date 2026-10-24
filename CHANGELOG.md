# Changelog

## Unreleased

- Add guided first-budget setup with currency, calendar, available money, budget end date, and optional bills and savings.
- Prioritize expense and income actions on Today and keep daily estimates independent of historical budget selection.
- Show localized budget dates, group charts/reports/forecasts under Insights, and open forecasts directly from savings goals.
- Add amount-first expense entry with optional notes, editable dates for new expenses, retained input after save failures, and an Edit confirmation action.
- Combine one-time and recurring bill creation, add due-date filters, and distinguish goal funding from purchases.
- Update English and Persian guidance and add regression coverage. The maintainer confirmed validation passed and application testing succeeded on Linux and Android on October 25, 2026.

## 3.0.0

### Build 6 savings correction

- Stop repeated daily goal contributions from consuming the entire spending budget.
- Credit opening savings and goal payments, and replay later allocations after backdated corrections.
- Repair derived allocations once when opening previous binary data or importing version 8/9 backups, preserving financial entries and the original binary recovery copy.
- Add regression coverage for repeated reconciliation, minimum savings, rollover, payments, historical corrections, backup import, recovery, and undo.
- Retain version 3.0.0 and increase the application build number to 6. Maintainer validation passed: 112 Rust tests, 50 Flutter tests, formatting, linting, Linux packaging, signed Android packaging, and application testing. Platform CI and package checksums are recorded in the Version 3 release notes.

### Original build 5

- Set the application and About screen version to 3.0.0 (build 5).
- Add a Windows CI workflow that validates and packages the portable release.
- Confirm manual build and application testing on Android and Linux.

- Refresh the README walkthrough with current Android screenshots while preserving the Pouch banner.

- Make period editing explicit and add confirmed deletion for unused periods, preserving financial records and supporting undo.
- Add deletion persistence and period-control interaction coverage.

- Integrate income entry into its calendar with explicit save buttons, independent period assignment, and successful-save coin feedback.
- Add stable generated period names and shared selectors for budgets, plans, savings goals, and Personal Forecast, with clear calculation-context messages in Today and beneath selectors.
- Preserve current user records and IDs while upgrading period metadata; read previous binary and JSON formats and retain the recovery copy.
- Add period assignment, forecast isolation, compatibility, calendar-save, and selector layout coverage. Bindings are regenerated from source without compilation.

- Play coin bursts after saving daily purchases, planned expenses, and savings goals.
- Add a shaded rotating coin beside Pouch on desktop, mobile, and About, with shared artwork for bursts and reduced-motion support.
- Cover save success, rejection, cancellation, rotating-coin lifecycle, and responsive branding.

- Add Delete beside Edit for every savings revision, with confirmation, Undo, and affected savings recalculation.
- Add brief coin bursts for received income and savings increases, plus subtle page transitions that respect reduced motion.
- Add savings deletion, persistence, Undo, success-feedback, and animation lifecycle regressions.

- Allow future dates in Today and record their expenses as plans, with shared editing and payment controls.
- Simplify all screens, explain savings set aside, prioritize income entry and forecast results, and move About into Settings.
- Add future-calendar/payment and Settings navigation regressions.

- Replace generated budget schedules with explicit editable periods and income-calendar receipt choices.
- Preserve stable IDs, shared boundaries, protected savings, reservations, debt and one-time rollover in Rust.
- Add personal period forecasting and historical summaries while keeping Standard Forecast independent.
- Restore date-based purchase entry and history inside Today, combine expenses and savings under Plans, and simplify period selection and setup.
- Restore the cream and light-brown default theme with bundled Vazirmatn interface typography and consistent responsive components.
- Introduce binary envelope 3, state schema 5 and JSON backup 8, with explicit archival of incompatible development data.
- Add accounting, transaction, forecast, navigation, localization and responsive-layout regressions.

## 2.0.0

- Add Linux x64 and Windows x64 desktop applications alongside Android.
- Add desktop report preview, PDF export and printing support with bundled Persian fonts.
- Improve financial forecasts with shared goal/expense selection, completion dates, deadline status and optional spending/income scenarios.
- Add country comparisons and standard forecasts for Canada, the United States, the United Kingdom, Germany, Australia, New Zealand and Iran, with cached data and optional local assumptions.
- Keep desktop storage, backup dialogs and platform services separate from the shared Flutter interface and Rust budgeting core.
- Preserve the Android application identity and release signing certificate; version code increases from 3 to 4.

The Linux release was built and tested on Ubuntu 26.04 x64. Compatibility with Ubuntu 24.04 is unverified. The Windows 11 package is an unsigned portable archive, not an installer. See [release verification](docs/RELEASE_V2.md) for validation details.
