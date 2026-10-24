<p align="center">
  <img src="design-assets/pouch-readme-banner.png" alt="Pouch logo surrounded by banknotes and gold coins with piggy-bank designs" width="100%">
</p>

# Pouch

Pouch is an offline spending planner with a Flutter interface and a Rust core. It supports Android, Windows x64, and Linux x64. It helps you plan a budget, record income and purchases, reserve money for upcoming expenses, track savings goals, and prepare reports.

The project is maintained by [AlighasemiQWxp](https://github.com/AlighasemiQWxp).

The default Classic theme uses cream and light brown. The interface bundles Vazirmatn for offline Persian and English text. Mobile navigation groups Today, Budget, and Bills & goals alongside More; desktop navigation also exposes Insights and Settings in the sidebar. About is available from Settings.

Periods can be edited or deleted from Budget. Deletion requires confirmation and is available only for periods without linked financial records. Removing an unused period extends an adjacent period to keep the calendar continuous.

## App walkthrough

### Start with a budget

On Today, choose **Set up my budget**. Confirm the currency and calendar, enter money already available for the budget, and choose the last day it should cover. The amount is recorded as received income today. Budget creation and that receipt use the existing transactional core operation. Optional bills and savings follow; the estimate uses only recorded information. Bills already saved remain when optional savings are skipped. Existing records keep their currency.

### Today: record everyday spending

Today puts the daily spending estimate and **Add expense** before the activity list. **Add income** opens the current budget's income form. Choose another day with the compact date controls; the estimate follows that day independently of historical budget selection elsewhere. **Back to today** returns to the current date.

Expense entry starts with the amount and currency, defaults to the viewed day, and offers quick categories and optional notes. New expenses can be backdated in the form. Existing expense dates remain fixed when editing. A failed save keeps the form and its contents open. The save confirmation offers **Edit**. Future-day entries remain planned bills until payment is recorded.

Upcoming bills and **How is this calculated?** appear below daily activity. The explanation distinguishes spending money, bill reservations, and savings allocations. Pouch does not move or lock money.

### Budget: income, dates, and savings

Budgets are shown by localized date ranges rather than generated names. Income defaults to today; expand the date control to use the income calendar. Future income stays expected until received. Saved income and bills retain explicit period assignments, including assignments outside their calendar dates through advanced options. Period editing, deletion, and savings history remain available.

### Bills & goals

Use **Add a bill** for a one-time payment or choose a repeat schedule in the same form. Repeating bills use the Bills category and their existing core recurrence rules. Manage and stop schedules below the bill list. Unpaid bills can be filtered to overdue or due within seven days. Recording payment remains separate from planning it.

Savings goals show money set aside against the target, with progress and a direct **View forecast** action. Reaching the target does not record a purchase. Use **Record purchase** only after spending the money. Goals remain visible across budget selections.

### Insights

Open **More → Insights** on mobile, or **Insights** in the desktop sidebar. **Spending**, **Reports**, and **Forecasts** share this destination. Reports load the current month's report on entry and retain custom date selection and PDF export. A goal's forecast shortcut opens that goal directly. Country comparisons remain optional and separate from the personal budget.

### Settings and backups

Settings contains English/Persian language selection, Classic/Ocean/Forest themes, regional preferences, and backup export/restore. Export a backup before uninstalling or clearing app data. Currency labels do not convert records.

The images in `ScreenShots/` document the earlier interface. They have not yet been replaced with captures of this UX revision. The maintainer confirmed successful validation and application testing on Linux and Android on October 25, 2026. See the regression checklist in [desktop validation](docs/DESKTOP.md).

## Features

- English and Persian interfaces, with right-to-left Persian layouts and Gregorian or Jalali calendars
- Country-based currency, calendar, and week-start defaults, with manual calendar and week-start choices
- Recorded income and future expected income, kept separate until it is marked received
- Backdated income and purchases in Budget and Today, including dates before first use; earlier records extend the first budget plan and carry-forward history
- Income calendar with explicit period choices, editable planning horizons, rollover, period savings plans, and independently recurring essential bills
- Responsive desktop/mobile navigation, daily expenses within Today, combined expenses and savings goals in Plans, and consistent English/Persian presentation
- Financial Forecast with a shared target, clear completion/deadline status, expandable improvements and country comparison (see [Financial Forecast](docs/FINANCIAL_FORECAST.md))
- Standard Forecast with automatic data retrieval for all seven named countries, deadline saving and income requirements, currency conversion, offline caching and optional local assumptions (see [Economic Profiles](docs/ECONOMIC_PROFILES.md))
- Daily spending recommendations with carry-forward balances
- Planned expenses that reserve money until paid
- Automatic savings allocations shared across goals, with funded progress, daily spending adjustments, and completion estimates
- Expense history available on demand, with editing and undo for recent deletions
- Dashboard with independent calendar and period filters, interactive cash-flow and savings charts, funding progress, and period comparisons (see [Dashboard](docs/DASHBOARD.md))
- Reports for selected days, date ranges, weeks, and months, with PDF printing on Android
- Local JSON backup and restore, with recovery copies for saved data

Pouch keeps budgeting data on the device. Its recommendations are calculations from recorded income and expenses, not a bank balance or a promise of future income.

Explicit periods retain stable IDs and their original planning calendar; changing the display calendar does not move saved dates. Shared boundaries and plan references are validated transactionally. Only received income funds recommendations. Cash and deficits carry forward without creating synthetic income. Pending expenses are reserved before savings; essential bills are included in that reservation once. Savings allocations are recorded, goal contributions are credited once per period, and goal payments consume them. Backdated corrections replay affected later allocations. Expected income remains separate until received, including when its actual date or amount differs. Financial forecasts are read-only estimates. See [data formats](docs/DATA_FORMAT.md) for the intentional storage break and [architecture](ARCHITECTURE.md) for the accounting rules.

Today shows the spending recommendation, expense entry, and relevant planned expenses. Expense history opens only when requested, with name search and date filtering for paid and planned expenses.

Reports calendars highlight the selected date range, individual days, full week, or full month. Weekly selection follows the chosen week start, and monthly selection follows the Gregorian or Jalali calendar chosen in Settings. Selecting a date updates the corresponding range endpoint, adds an individual day, or chooses the week or month to report.

## Project structure

- flutter contains the application interface, navigation, localization, and platform integration.
- rust contains the budget domain, calculations, backup validation, and persistent storage.
- ARCHITECTURE.md describes module responsibilities and data flow.
- SECURITY.md explains data handling and vulnerability reporting.

## Build and run

Install Flutter, the Android SDK, and the Android NDK version pinned by the Flutter Gradle configuration. From the flutter directory, run:

    flutter pub get
    flutter run

The Android release build uses the application version shown in the About page. Configure a private Android signing key before distributing a release build; keep signing files and passwords outside this repository.

If you change the Rust API, regenerate the Flutter bridge from the flutter directory with flutter_rust_bridge_codegen generate, then build and verify the app manually on an Android device.

## Desktop support

Windows x64 and Linux x64 runners, platform services, and manual packaging scripts are prepared. See [desktop build and acceptance instructions](docs/DESKTOP.md). Version 2 packages have passed manual build and runtime validation on Ubuntu 26.04 x64, Android, and Windows 11. Windows is an unsigned portable release. Ubuntu 24.04 compatibility of the published Linux package has not been verified. The Linux workflow runs on every push to main and on pull requests, and can also be started manually. It checks the Flutter frontend and Rust core, builds the Linux application, and uploads an Actions artifact rather than a release. Results appear in GitHub Actions and commit or pull-request checks.

## Version 3

Version 3.0.0 build 6 corrects repeated goal reservations that could leave Today with no daily allowance. It repairs derived savings allocations when opening earlier Flutter/Rust data or importing supported backups. The maintainer completed Linux validation, built the signed Android package, and confirmed the corrected application works. The Version 3 release notes identify the replacement package source commit, platform CI results, and checksums. See the [changelog](CHANGELOG.md), [release verification record](docs/RELEASE_V3.md), and [GitHub release](https://github.com/AlighasemiQWxp/Pouch/releases/tag/v3.0.0).

## Release signing and validation

Keep the release keystore and its properties file outside this repository. Back them up securely so future versions can use the same key.

Create the private directory first, then generate a keystore with the JDK keytool command. Enter passwords interactively:

    keytool -genkeypair -v -keystore "C:\Private\Pouch\pouch-release.jks" -keyalg RSA -keysize 2048 -validity 10000 -alias pouch

Create `C:/Private/Pouch/signing.properties` with these fields, replacing the placeholders privately. Use forward slashes for the absolute keystore path:

    storeFile=C:/Private/Pouch/pouch-release.jks
    storePassword=YOUR_PRIVATE_STORE_PASSWORD
    keyAlias=pouch
    keyPassword=YOUR_PRIVATE_KEY_PASSWORD

In PowerShell, set the properties file location and run validation from the repository root:

    $env:POUCH_SIGNING_PROPERTIES = "C:\Private\Pouch\signing.properties"
    .\validate-and-build.ps1

The script checks Rust formatting, Clippy and tests, Flutter analysis and available tests, then builds the signed APK at `flutter/build/app/outputs/flutter-apk/app-release.apk`. Debug builds do not require signing credentials. Release builds fail when credentials are missing and never fall back to the debug key.

Verify the new APK on an Android device before publishing. An installation signed with the debug key cannot be updated by this release key. Export a backup before uninstalling that installation, then restore it in the signed app if both installations use the current backup format. Older development backups are intentionally unsupported.

## License

Pouch is covered by the Pouch Source-Available License 1.0 in LICENSE. Third-party dependencies remain under their own licenses.
