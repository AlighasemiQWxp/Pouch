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

Rust's binary schema, validated writes, recovery and portable JSON backup formats are unchanged. Desktop starts with no Android legacy storage candidates; transferring Android data requires the existing explicit JSON export/restore flow. Backup dialogs preserve cancellation, bound UTF-8 reads to 5 MB and write through a flushed temporary file before replacing the destination. Export destinations inside the app's data directory are rejected to protect internal records and settings.

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
