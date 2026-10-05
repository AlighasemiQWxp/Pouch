# Third-party notices

Pouch's application code is covered by the license in LICENSE. Third-party libraries retain their own licenses.

Desktop reports bundle unmodified Amiri Regular and Bold from the Amiri Project Authors through the Google Fonts repository. These fonts are licensed under the SIL Open Font License 1.1. The full copyright and license text is included in flutter/assets/fonts/OFL.txt and in desktop bundles as Amiri-LICENSE.txt. Font assets are used for offline PDF reports and do not change the app's interface font.

Desktop builds include Flutter and its engine (BSD-style licenses), Flutter plugins and Rust dependencies under their respective upstream licenses. Flutter's built-in license registry contains package notices; generated Flutter assets include the bundled NOTICES file. The printing plugin uses PDFium binaries under PDFium and third-party component licenses. Preserve its bundled notices and review the PDFium distribution's license files before public desktop distribution.

Dependency versions are recorded in flutter/pubspec.lock and rust/Cargo.lock. This file highlights desktop additions and does not replace the full upstream license texts.

## Economic profile sources

The Canada Standard Forecast attributes OECD Taxing Wages, Statistics Canada Household Spending/CPI tables and Bank of Canada indicative daily exchange rates. The displayed scenario combines and adjusts these sources; calculated estimates are Pouch's own and no provider endorsement is implied. Statistics Canada data are used under its Open Licence (https://www.statcan.gc.ca/en/terms-conditions/open-licence). OECD and Bank of Canada data remain subject to their source terms; preserve attribution and distinguish adjustments from original statistics. Exact series, reference periods and source/terms links are recorded in docs/ECONOMIC_PROFILES.md. Iran survey content is not embedded as an automatic forecast; reuse rights still require review before a future distributed profile.

The economic HTTP adapter adds reqwest, rustls and csv dependencies. Preserve their upstream licenses and transitive notices after Cargo dependency resolution; no paid API library or embedded credential is included.
