<p align="center">
  <img src="flutter/assets/pouch-icon.png" alt="Pouch app icon" width="160">
</p>

# Pouch

Pouch is an offline Android spending planner with a Flutter interface and a Rust core. It helps you plan a budget, record income and purchases, reserve money for upcoming expenses, track savings goals, and prepare reports.

The project is maintained by [AlighasemiQWxp](https://github.com/AlighasemiQWxp).

## Features

- English and Persian interfaces, with right-to-left Persian layouts and Gregorian or Jalali calendars
- Country-based currency, calendar, and week-start defaults, with manual calendar and week-start choices
- Recorded income and future expected income, kept separate until it is marked received
- Backdated income and purchases in Budget Plan and Today, including dates before first use; earlier records extend the first budget plan and carry-forward history
- Income calendar and a simple monthly plan for savings and essential expenses
- Daily spending recommendations with carry-forward balances
- Planned expenses that reserve money until paid
- Automatic savings allocations shared across goals, with funded progress, daily spending adjustments, and completion estimates
- Purchase history available on demand, with editing and undo for recent deletions
- Reports for selected days, date ranges, weeks, and months, with PDF printing on Android
- Local JSON backup and restore, with recovery copies for saved data

Pouch keeps budgeting data on the device. Its recommendations are calculations from recorded income and expenses, not a bank balance or a promise of future income.

Budget Plan uses the calendar chosen in Settings. Received income funds daily recommendations; manual salary, base allowance, payday, and daily overrides are no longer used. Existing backup fields remain readable for compatibility. Monthly savings is a minimum: goals can increase the shared allocation, while essential expenses and recorded spending reduce available funds. Goal progress describes funds allocated by the model, not money transferred to a separate account. Goal completion estimates assume similar future received income and spending; expected income never funds current progress. Target dates determine goal priority. Changing a goal recalculates allocations from the recorded history.

Today shows the spending recommendation, expense entry, and relevant planned expenses. Purchase history opens only when requested, without search or category filters.

Reports calendars highlight the selected date range, individual days, full week, or full month. Weekly selection follows the chosen week start, and monthly selection follows the Gregorian or Jalali calendar chosen in Settings. Selecting a date updates the corresponding range endpoint, adds an individual day, or chooses the week or month to report.

## Project structure

- flutter contains the Android interface, navigation, localization, and platform integration.
- rust contains the budget domain, calculations, backup validation, and persistent storage.
- ARCHITECTURE.md describes module responsibilities and data flow.
- SECURITY.md explains data handling and vulnerability reporting.

## Build and run

Install Flutter, the Android SDK, and the Android NDK version pinned by the Flutter Gradle configuration. From the flutter directory, run:

    flutter pub get
    flutter run

The Android release build uses the application version shown in the About page. Configure a private Android signing key before distributing a release build; keep signing files and passwords outside this repository.

If you change the Rust API, regenerate the Flutter bridge from the flutter directory with flutter_rust_bridge_codegen generate, then build and verify the app manually on an Android device.

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

Verify the new APK on an Android device before publishing. An installation signed with the debug key cannot be updated by this release key. Export a backup before uninstalling that installation, then restore it in the signed app.

## License

Pouch is covered by the Pouch Source-Available License 1.0 in LICENSE. Third-party dependencies remain under their own licenses.
