# Security policy

## Reporting a vulnerability

Please do not post vulnerability details, private backups, or personal budget data in a public issue.

If private vulnerability reporting is enabled for this repository, use GitHub's **Report a vulnerability** feature. Otherwise, contact the maintainer through [AlighasemiQWxp's GitHub profile](https://github.com/AlighasemiQWxp) and request a private reporting route before sending technical details.

Include the affected Pouch version, Android version and device, a concise description of the impact, and steps to reproduce. Use synthetic records in examples. Do not include real backups, signing keys, passwords, or access tokens.

## Supported versions

| Version | Status |
| --- | --- |
| 1.0 | Current |

Security fixes are prepared for the current version. This project does not currently publish a separate support window for older versions.

## Data handling

Budget records are stored in the app's private Android storage. JSON backups and printed reports can contain sensitive financial details; keep exported files private and remove them from shared locations when they are no longer needed.

Pouch validates imported backup data before saving it. The app does not require a hosted account for its budgeting features. Build signing files, SDK paths, and credentials must remain outside the repository.

## Desktop data

Windows and Linux records are stored in per-user application support directories, separate from the application bundle. Desktop storage is protected by operating-system user permissions and is not encrypted by Pouch. Keep backups and exported PDFs private. A process lock prevents multiple app instances from writing the same records. Desktop compilation and runtime security checks remain pending.

## Public economic data requests

Standard Forecast may retrieve country statistics and indicative currency rates directly from OECD, Statistics Canada, World Bank, Statistical Centre of Iran, Bank of Canada and TGJU over HTTPS. Only public country, scenario, indicator and currency identifiers are requested; financial records, goals, amounts and custom assumptions remain on the device. Providers can observe ordinary connection metadata such as the source IP address. No API credentials or dedicated backend are used. The HTTP adapter has fixed hosts, no redirects, bounded response sizes and request timeouts. Downloaded caches are independent from financial state and remain usable offline after initial retrieval. Custom assumptions are included in private financial backups; public economic cache files are not. Network and device validation of this new feature remains pending.
