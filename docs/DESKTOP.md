# Windows and Linux desktop builds

Version 2 desktop packages passed manual build and runtime validation on Windows 11 x64 and Ubuntu 26.04 x64. Android retains its native services and release signing setup. The Windows package is an unsigned portable release. Compatibility of the published Linux package with Ubuntu 24.04 or older distributions has not been verified.

## Toolchains

Use Flutter 3.47.2 (Dart 3.13.2) and Rust 1.97.1, matching the prepared Linux workflow. Windows needs Visual Studio with Desktop development with C++, the Windows SDK, and CMake. Linux needs clang, CMake, Ninja, pkg-config, GTK 3 development headers, liblzma development headers, and a C++ toolchain. The current dependency graph includes JNI build tooling; a JDK with JAVA_HOME configured may be required by dependency build hooks.

On Ubuntu 24.04:

    sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev

Desktop Rust builds locate the Cargo manifest relative to the application project, independent of Flutter plugin symlinks. Windows passes the configured Flutter SDK path to the Rust build helper.

The hand-written runtime initializer loads the Rust library relative to the executable, independent of the working directory or any Rust build tree. Generated bridge files are unchanged.

The printing plugin downloads its pinned PDFium runtime during configuration. Build machines need network access for dependencies; installed reports use bundled fonts and PDFium and do not download fonts at runtime. Linux printing uses the GTK print dialog and configured printer services. PDF export works without a configured physical printer. External profile links require the desktop's URL handler, such as xdg-open on Linux.

## Manual validation

Run formatting yourself before the validation script:

    cd flutter
    dart format lib test

From the repository root on Windows:

    .\validate-and-build-windows.ps1

From the repository root on Linux:

    bash ./validate-and-build-linux.sh

Scripts check Rust formatting, Clippy and tests, resolve the locked Flutter dependencies, check Dart formatting, run Flutter analysis and tests, then build and package the complete desktop bundle. They run only when invoked. They do not commit, push, upload, or publish anything. Repeat the existing Android validation script with private release signing configured to verify Android compatibility.

Archives are written under ignored dist/: pouch-2.0.0-windows-x64.zip and pouch-2.0.0-linux-x64.tar.gz. They are unsigned portable application bundles, not installers. Extract the entire archive and run pouch.exe or ./pouch. Do not distribute the executable alone. Windows requires the compatible Microsoft Visual C++ runtime. Linux requires compatible glibc, GTK 3, graphics libraries and printer integration; the published Version 2 bundle was built and tested on Ubuntu 26.04, and compatibility with Ubuntu 24.04 or older distributions has not been verified.

## Platform services and records

PouchPlatform supplies OS services to PouchBridge. AndroidPouchPlatform forwards the original Android method channel, including legacy record migration and SharedPreferences theme storage. DesktopPouchPlatform uses path_provider's per-user application support directory, file_selector dialogs, url_launcher, and printing.

Windows application data is identified by the executable's stable CompanyName (AlighasemiQWxp) and ProductName (Pouch) resource values. Linux uses the GTK application ID com.daybook.pouch under the XDG application-data directory, with path_provider's executable-name fallback where required. Keep these identities stable across releases. Records live in pouch.data with pouch.data.backup; desktop theme selection is separate in pouch-theme.txt. Moving the application does not move records. A held OS file lock prevents simultaneous desktop processes from writing the same data directory. A second instance reports a startup error instead of opening those records.

The named-period update uses binary envelope 4, state schema 6, and backup version 9. The immediately previous envelope 3/schema 5 and backup version 8 upgrade without clearing records; older incompatible formats remain unsupported. Validated writes and recovery remain in Rust. Incompatible files are preserved and an explicit reset archives them; legacy WebView and older development formats are not migrated. Desktop starts with no Android legacy storage candidates; transferring Android data requires the existing explicit JSON export/restore flow. Backup dialogs preserve cancellation, bound UTF-8 reads to 5 MB and write through a flushed temporary file before replacing the destination. Export destinations inside the app's data directory are rejected to protect internal records and settings.

Desktop report export adds a preview with Print, Save as PDF and Close. PDF generation uses the same Rust report, localized labels, amounts and calendar formatter as Android HTML reports. Amiri fonts support offline English and Persian output. Save as PDF uses a native save dialog and remains available if preview rendering or printer discovery fails. Android continues using its native HTML print window.

## GitHub Actions Linux workflow

.github/workflows/linux-desktop.yml runs on every push to main and on pull requests, with workflow_dispatch retained for manual runs. It has read-only repository permissions, runs Rust and Flutter formatting checks, linting, tests, and Linux build/package on Ubuntu 24.04, and uploads a GitHub Actions artifact for 14 days. There are no path filters, so documentation-only pushes to main also create runs. Results appear in the Actions tab and commit or pull-request checks, with a green check only when all steps succeed. The pinned Flutter SDK checkout fetches full Git history and release tags so Flutter can identify its version during dependency resolution. It has no GitHub Release upload steps.

After source review and manual validation, pushing to main starts the workflow automatically. It can also be started explicitly from GitHub Actions using Run workflow. A passing build is not proof that Linux UI, dialogs or printing work; test the extracted artifact on a Linux desktop before publishing.

## Acceptance checks

- Launch an extracted bundle outside the checkout, including from a directory with spaces and non-ASCII characters; ensure the Rust library loads.
- Record/edit income and purchases, including backdated entries; verify plans, savings, goals and undo. Restart and verify records and theme persist.
- Export/restore Android and desktop JSON backups in both directions. Check cancellation, overwrite, invalid JSON, oversized files, unreadable destinations and recovery-copy export. Use synthetic data.
- With disposable records, test recovery after primary-file corruption and rejection of unsupported newer formats. Confirm an additional process cannot write the same data directory.
- Exercise every screen in English and Persian, both calendars, keyboard navigation, wheel scrolling, small/large windows and scaled displays. Existing screen layouts are preserved.
- Preview, save and print short and multi-page reports. Verify Persian letters join correctly, RTL column order, mixed numbers/text, totals, dates and descriptions. Test no-printer and cancellation cases; opening the saved PDF externally must remain possible.
- Verify the About profile link and Android startup, migration, themes, backups, printing and signed-device behavior.

For Version 2, manual builds, automated validation and application testing were confirmed on all three platforms. The Linux persistence, backup/restore, English/Persian display, report preview and PDF export checks passed. Physical-printer behavior and older Linux distribution compatibility are not claimed by this release record.

## Explicit-period redesign validation

The current working-tree redesign has not been compiled, unit-tested, or built here. Earlier Version 2 acceptance records above describe the released version only. Source generation and static checks are not runtime validation.

Completed source checks: official bridge generation in source-parsing mode, matching Rust/Dart bridge hashes, Dart static analysis with no issues, Rust/Dart formatting checks, whitespace checks respecting existing CRLF files, and 536 matching English/Persian localization keys with matching placeholders. Rust and Flutter regression tests and platform builds have not been executed.

Run these commands manually from the repository root, in order:

1. `cargo fmt --manifest-path rust/Cargo.toml -- --check`
2. `cargo clippy --manifest-path rust/Cargo.toml --all-targets --locked -- -D warnings`
3. `cargo test --manifest-path rust/Cargo.toml --locked`
4. In `flutter`, run `flutter pub get --enforce-lockfile`, `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`, and `flutter test`.
5. From the repository root on Linux, run `bash ./validate-and-build-linux.sh`. On Windows, run `./validate-and-build-windows.ps1`. Run `./validate-and-build.ps1` for Android using the existing private signing configuration when validating a release package. Each script includes the platform build and validation checks.
6. Launch the resulting application and complete the acceptance steps below. Do not approve Git synchronization until both automated and manual validation pass.

If bindings need regeneration during manual validation, run `flutter_rust_bridge_codegen generate` from `flutter` with the configured toolchain, then repeat the checks. The checked-in bindings were generated from Rust source without invoking cargo-expand compilation.

Acceptance sequence:

- Start with disposable current-format data. Create the first period through the Income Calendar, choose a horizon, and record income. Verify both receipt choices, same-day additional income, and explicit rejection of a second period on the same start date.
- Using a past year such as 2024, record income on October 10, October 27, and November 8, starting new periods on the latter two dates. Verify stable IDs, inclusive starts/exclusive ends, correct closure, and one-time rollover. Repeat with weekly, biweekly, monthly in both calendars, custom, and irregular horizons.
- Edit dates and horizons, including a shared boundary. Verify adjacent dates and dated plans stay valid, and failed edits leave state unchanged. Let the last horizon expire; verify the explicit warning and no invented income or daily allowance.
- Add recurring rent, ordinary expenses, and savings goals. Receive multiple incomes; reserve funds; pay/edit/delete a bill or goal purchase; stop a recurrence; and make historical corrections. Verify actual spending is counted once, unpaid bills persist, protected savings continue, and cash equals free funds plus reservations plus protected savings.
- Select a historical Budget Plan, open Today, and verify today remains active. Select historical/current/future Personal Forecast periods and compare actual/planned values. Keep Standard Forecast expanded while changing the personal period; verify its target, country, date basis, and methodology stay independent.
- Test Purchases search, all-date/day filtering, backdated entry, editing, and deletion/undo. Test expense/goal creation, deadline editing, payment, status filters, and existing economic customization/refresh/offline behavior.
- Exercise report range/specific/week/month selection, category charts, historical unpaid obligations, PDF preview/export, printing and cancellation. Test backup export/restore, recovery export, reset confirmation, restart persistence, process locking, invalid/oversized backups, and incompatible-format archival.
- Verify English and Persian, LTR/RTL, Gregorian/Jalali, Persian/Arabic numeric input, large text, keyboard dismissal, dialog cancellation, rapid selector changes, Android portrait, and narrow/wide Linux/Windows windows. Check all navigation destinations, focus/hover/disabled states, and short windows.

Regression suites include explicit-period accounting, transactional changes, period forecasts, application navigation/onboarding, localization parity, and responsive components. Rust and Flutter test execution remains pending manual execution.
