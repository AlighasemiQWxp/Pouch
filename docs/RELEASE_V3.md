# Pouch 3.0.0 release record

## Build 6 savings correction

The maintained Flutter application and Rust core retain version 3.0.0 and increase the build number from 5 to 6. The correction credits existing period contributions when reserving money for savings goals, preventing repeated reservations from consuming the daily spending budget. Backdated corrections replay later allocations. Previous binary formats and JSON backup versions 8 and 9 receive a one-time repair of derived allocations, preserving ledger entries and keeping the original binary recovery copy. See [data formats](DATA_FORMAT.md) for repair scope and compatibility.

The legacy root-level WebView application is outside this release.

## Validation

The maintainer ran the Linux validation/build script successfully: Rust formatting, Clippy, 112 Rust tests, locked Flutter dependency resolution, Dart formatting, Flutter analysis, 50 Flutter tests, and Linux release packaging passed. The maintainer also built the signed Android release and confirmed that the corrected Version 3 application works.

The Android APK reports package com.daybook.app, version 3.0.0, and build 6, and passes APK signature verification. The locally validated Linux archive has SHA-256 9784b8e8e539899d1d2d0d123c49047ec6743a7ae974244342407ae357907fb1. The signed Android APK has SHA-256 700d06c8d79d363f51abbdde643ae1b3aafb218978485b8236611e9acd6e51ab.

Windows and Linux GitHub Actions validate and package the reviewed correction commit. Windows CI verifies the executable version against 3.0.0+6. Interactive testing of the Windows package is not performed by CI. The published Linux package is built on Ubuntu 24.04 in CI; the local Linux validation above is separate evidence.

## Replacement publication

The existing [Version 3 release](https://github.com/AlighasemiQWxp/Pouch/releases/tag/v3.0.0) is the publication location for all three corrected packages:

- pouch-3.0.0-android.apk
- pouch-3.0.0-linux-x64.tar.gz
- pouch-3.0.0-windows-x64.zip
- SHA256SUMS

The original source tag v3.0.0 remains at 69d94745d5a8295ac7dec17be8a4264e7bd669cd. The release notes identify the exact correction commit and successful Windows/Linux CI runs for the replacement build 6 packages. The automatic source archives attached to the original tag still represent build 5; use the correction commit linked in the release notes for build 6 source.

All replacement packages must be verified before upload. SHA256SUMS covers the three published application packages. Publication verification downloads the replacement assets and compares their hashes with the prepared packages. The release notes provide the final source and CI evidence, avoiding a moving tag or rewritten history.

## Original release validation

The original release notes report successful Windows and Linux CI builds and a maintainer-built, signed Android APK with version 3.0.0/build 5. The [Linux release workflow](https://github.com/AlighasemiQWxp/Pouch/actions/runs/39499628065) built the Linux package from the original tagged source. Earlier maintainer Android/Linux runtime checks preceded the version metadata update and do not validate build 6. Windows interactive runtime testing was not performed by CI.

## Platform notes

Extract the complete Windows ZIP and run pouch.exe, retaining its DLLs and data directory. It is an unsigned portable application, not an installer, and requires a compatible Microsoft Visual C++ runtime. Extract the complete Linux archive and run ./pouch; compatible glibc, GTK 3, and graphics libraries are required. The Android package must retain the existing application ID and signing certificate to support an in-place update.
