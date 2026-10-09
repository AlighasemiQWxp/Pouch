# Changelog

## 2.0.0

- Add Linux x64 and Windows x64 desktop applications alongside Android.
- Add desktop report preview, PDF export and printing support with bundled Persian fonts.
- Improve financial forecasts with shared goal/expense selection, completion dates, deadline status and optional spending/income scenarios.
- Add country comparisons and standard forecasts for Canada, the United States, the United Kingdom, Germany, Australia, New Zealand and Iran, with cached data and optional local assumptions.
- Keep desktop storage, backup dialogs and platform services separate from the shared Flutter interface and Rust budgeting core.
- Preserve the Android application identity and release signing certificate; version code increases from 3 to 4.

The Linux release was built and tested on Ubuntu 26.04 x64. Compatibility with Ubuntu 24.04 is unverified. The Windows 11 package is an unsigned portable archive, not an installer. See [release verification](docs/RELEASE_V2.md) for validation details.
