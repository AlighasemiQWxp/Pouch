# Pouch 2.0.0 release checklist

Status: all three release packages built and manually tested. Source synchronization, CI verification and publication are the final release gates.

## Version and scope

The Flutter application version is 2.0.0+4. Android reads its version name and code from Flutter. The About screen displays 2.0.0. Windows resource metadata uses the Flutter version during normal builds.

The maintained application uses Flutter and the Rust core. The legacy root-level WebView application is outside this release.

## Manual validation and builds

Run Dart formatting from flutter with `dart format lib test`, and Rust formatting from the repository root with `cargo fmt --manifest-path rust/Cargo.toml`. Review any resulting changes.

On Linux, run `bash ./validate-and-build-linux.sh` from the repository root. On Windows, run `.\validate-and-build-windows.ps1`. These scripts check formatting, linting, tests, and produce complete portable desktop archives.

For Android, set POUCH_SIGNING_PROPERTIES to the private signing properties file and run `.\validate-and-build.ps1` in PowerShell from the repository root. Use the same signing key as the previous release so existing users can update. Never include credentials or signing keys in source or release assets.

Confirm all checks pass, then test the signed Android APK and extracted desktop bundles. Follow the acceptance checks in DESKTOP.md, including persistence, backup restore, English and Persian screens, and PDF reports. Verify the installed application reports 2.0.0. Build all packages from the final reviewed source; rebuild any affected package after source changes.

## Release assets

- pouch-2.0.0-android.apk, copied from flutter/build/app/outputs/flutter-apk/app-release.apk after validation.
- pouch-2.0.0-linux-x64.tar.gz, produced in dist/ by the Linux script.
- pouch-2.0.0-windows-x64.zip, produced in dist/ by the Windows script.
- SHA256SUMS, calculated from the final three assets.

Desktop packages include the entire application bundle and license notices. They are unsigned portable archives, not installers. The Windows package was manually tested on Windows 11. Windows requires the compatible Microsoft Visual C++ runtime. The published Linux package was built and tested on Ubuntu 26.04 x64 using Flutter 3.47.6 (Dart 3.13.5) and Rust 1.99.0. Ubuntu 24.04 compatibility has not been verified. The CI workflow separately builds on Ubuntu 24.04 with its pinned toolchain; this does not establish compatibility of the published Ubuntu 26.04 artifact. Android must be signed with the release key.

## Confirmed validation

- Rust formatting and Clippy passed; all 73 Rust tests passed.
- Dart formatting, Flutter analysis and all 9 Flutter tests passed.
- Linux archive launched outside the checkout; version, screens, English/Persian layouts, report preview, PDF export, persistence and JSON backup/restore passed manual checks.
- Android APK signature verifies with APK Signature Scheme v2. Its package is com.daybook.app, version 2.0.0, code 4. Its signing certificate matches the published Version 1 APK (code 3). Android manual testing was confirmed by the maintainer.
- Windows validation/build script passed, the extracted final package passed manual testing, and the executable resource version is 2.0.0.4. No Authenticode signature is present.
- Existing tested packages are reused without rebuilding. Final asset hashes are distributed in SHA256SUMS.

## Publication

After manual validation is confirmed, review the source diff for secrets, generated files, unrelated changes, temporary artifacts, and unwanted references. Update documentation to reflect confirmed results. Commit the reviewed release changes on main, push to origin, verify local and remote commit hashes match, and confirm GitHub CI passes.

Create tag v2.0.0 at that validated commit and publish a new GitHub Release titled Pouch 2.0.0 with the four assets above. Confirm the uploaded assets and checksums. Report the commit hash, push status, CI result, and release URL.
