# Windows and Linux desktop builds

Desktop support is prepared for Windows x64 and Ubuntu 24.04 x64. Compilation and desktop runtime acceptance remain pending. Android retains its existing native services and signing setup. No desktop release has been published.

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

Archives are written under ignored dist/: pouch-1.0.0-windows-x64.zip and pouch-1.0.0-linux-x64.tar.gz. They are unsigned portable application bundles, not installers. Extract the entire archive and run pouch.exe or ./pouch. Do not distribute the executable alone. Windows requires the compatible Microsoft Visual C++ runtime. Linux requires compatible glibc, GTK 3, graphics libraries and printer integration; a bundle built on Ubuntu 24.04 is not claimed to support older distributions.

## Platform services and records

PouchPlatform supplies OS services to PouchBridge. AndroidPouchPlatform forwards the original Android method channel, including legacy record migration and SharedPreferences theme storage. DesktopPouchPlatform uses path_provider's per-user application support directory, file_selector dialogs, url_launcher, and printing.

Windows application data is identified by the executable's stable CompanyName (AlighasemiQWxp) and ProductName (Pouch) resource values. Linux uses the GTK application ID com.daybook.pouch under the XDG application-data directory, with path_provider's executable-name fallback where required. Keep these identities stable across releases. Records live in pouch.data with pouch.data.backup; desktop theme selection is separate in pouch-theme.txt. Moving the application does not move records. A held OS file lock prevents simultaneous desktop processes from writing the same data directory. A second instance reports a startup error instead of opening those records.

Rust's binary schema, validated writes, recovery and portable JSON backup formats are unchanged. Desktop starts with no Android legacy storage candidates; transferring Android data requires the existing explicit JSON export/restore flow. Backup dialogs preserve cancellation, bound UTF-8 reads to 5 MB and write through a flushed temporary file before replacing the destination. Export destinations inside the app's data directory are rejected to protect internal records and settings.

Desktop report export adds a preview with Print, Save as PDF and Close. PDF generation uses the same Rust report, localized labels, amounts and calendar formatter as Android HTML reports. Amiri fonts support offline English and Persian output. Save as PDF uses a native save dialog and remains available if preview rendering or printer discovery fails. Android continues using its native HTML print window.

## Manual Linux workflow

.github/workflows/linux-desktop.yml has only workflow_dispatch. It has read-only repository permissions, runs validation/build/package on Ubuntu 24.04, and uploads a GitHub Actions artifact for 14 days. It has no push, pull-request or tag triggers, and no GitHub Release upload steps. It has not been run.

After source review, manual validation and repository synchronization, the workflow can be started explicitly from GitHub Actions. A passing build is not proof that Linux UI, dialogs or printing work; test the extracted artifact on a Linux desktop before publishing.

## Acceptance checks

- Launch an extracted bundle outside the checkout, including from a directory with spaces and non-ASCII characters; ensure the Rust library loads.
- Record/edit income and purchases, including backdated entries; verify plans, savings, goals and undo. Restart and verify records and theme persist.
- Export/restore Android and desktop JSON backups in both directions. Check cancellation, overwrite, invalid JSON, oversized files, unreadable destinations and recovery-copy export. Use synthetic data.
- With disposable records, test recovery after primary-file corruption and rejection of unsupported newer formats. Confirm an additional process cannot write the same data directory.
- Exercise every screen in English and Persian, both calendars, keyboard navigation, wheel scrolling, small/large windows and scaled displays. Existing screen layouts are preserved.
- Preview, save and print short and multi-page reports. Verify Persian letters join correctly, RTL column order, mixed numbers/text, totals, dates and descriptions. Test no-printer and cancellation cases; opening the saved PDF externally must remain possible.
- Verify the About profile link and Android startup, migration, themes, backups, printing and signed-device behavior.

Compilation, automated tests, printed output and these runtime checks must be confirmed manually before a commit, push or release.
