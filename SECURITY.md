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

Pouch validates imported backup data before saving it. The Android app does not require a hosted account for its budgeting features. Build signing files, SDK paths, and credentials must remain outside the repository.
