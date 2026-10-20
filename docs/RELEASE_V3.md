# Pouch 3.0.0 release record

## Scope

The maintained application uses Flutter and the Rust core. Version 3.0.0 (build 5) updates the application metadata and About screen. The release includes explicit editable budget periods, income-calendar entry, period selectors, savings and plan controls, refreshed navigation and responsive interface, and offline English/Persian reports. See CHANGELOG.md for the full source changes.

The legacy root-level WebView application is outside this release.

## Validation

The [Linux validation and build workflow](https://github.com/AlighasemiQWxp/Pouch/actions/runs/39310734644) passed for source commit 1143b30b99dd1203259c96f19a96ca10a8a25587, including formatting, linting, Rust and Flutter tests, and Linux packaging.

The maintainer confirmed Linux and Android builds and manual application testing for the current application source before the release metadata changed from 2.0.0+4 to 3.0.0+5. That confirmation does not claim the previously built packages contain the new version metadata.

The Windows workflow runs Rust formatting, Clippy and tests, locked Flutter dependency resolution, Dart formatting, Flutter analysis and tests, and the Windows release build. It checks required bundle files and verifies the executable's numeric resource version matches pubspec.yaml. Release publication requires a successful run for the tagged source commit and verified artifact checksums.

Windows interactive runtime testing is not performed by CI. Earlier Windows 11 acceptance records describe Version 2 and are not Version 3 runtime evidence.

## Assets and publication

- pouch-3.0.0-windows-x64.zip: the complete unsigned portable Windows application, including the Rust DLL, Flutter runtime, plugins, assets and license notices.
- SHA256SUMS: SHA-256 checksum of the published Windows ZIP.

Extract the entire ZIP and run pouch.exe. Windows requires the compatible Microsoft Visual C++ runtime. This package is not an installer and is not Authenticode signed.

This release publishes the Windows package requested by the maintainer. Previously built Android and Linux packages are not renamed or represented as newly built 3.0.0 packages.

Publish tag v3.0.0 at the reviewed source commit after validation and successful CI. Verify the downloaded release assets against SHA256SUMS and confirm the tag, local main and remote main identify the same commit. Build logs are available under the repository's Windows desktop build workflow in GitHub Actions.
