# Pouch data formats

The savings correction reads the two previous Flutter/Rust data formats and repairs derived savings allocations once. It does not import legacy WebView data or older incompatible development formats. Incompatible files are never silently deleted or overwritten.

## Binary state

The binary envelope is version **5**, and AppState schema is **7**. The envelope contains `POUCHDAT`, the version, payload length, checksum, and Serde/Postcard payload. Money is integer minor units; dates are Gregorian day offsets. Validated mutations use same-directory atomic writes and retain a recovery copy.

Envelopes 3/schema 5 and 4/schema 6 are upgraded through dedicated adapters. Savings allocations are rebuilt in date order through today using saved allocation dates, income and purchase dates, savings revision dates, and period starts. Goal funding credits the existing period contribution and opening savings. Income, purchases, periods, plans, target definitions, payment links, internal IDs, and existing period names and assignments are preserved. Only derived allocation history is recalculated from the currently saved targets; earlier edits or deleted targets cannot be reconstructed. On application open, the corrected state is persisted while the original valid bytes remain in the recovery file. Reopening envelope 5/schema 7 does not replay the repair. Unsupported envelopes or schemas return an incompatibility error without falling back to another format. A confirmed incompatible-data reset moves both existing `pouch.data` and `pouch.data.backup` into a unique `incompatible-<timestamp>` directory before creating an empty current-format state. Legacy JSON candidates remain rejected and are not migrated. Corruption/recovery and incompatibility are separate conditions. A normal save also rejects an incompatible primary file.

## JSON backup

Portable backups export version **10** and accept versions **8**, **9**, and **10**, with a `version` and complete `state`. Each backup version must match its state schema (5, 6, and 7 respectively). Versions 8 and 9 receive the savings repair before replacement; version 8 also adds period metadata without resetting ledger records. Version 10 round-trips existing allocations without replaying the repair. PeriodContext contains generated names and explicit income/expected-income and expense/goal associations keyed by stable record IDs. Backups include preferences, explicit periods, dated period plans, savings allocations, essential rules and payment links, received and expected income, receipt metadata, purchases, planned expenses/goals, and economic customizations. The limit is 5,000,000 bytes. JSON dates are ISO Gregorian strings, including daily-record keys.

Import parses and validates all state before replacement. Unsupported, oversized, invalid, or inconsistent backups leave active state unchanged. Backups contain private financial records.

## Periods and rollover

Each persisted `BudgetPeriod` contains a stable unique ID, inclusive `start`, exclusive `end`, planning preset (`recurrence`), and original `calendar`. Presets only suggest horizons; they never create financial records or further periods. A fresh state contains no period. At most 1000 periods are supported, with each horizon spanning at most 3660 days. Historical adjacent periods meet at a shared boundary; the last period can expire until the user edits its horizon or creates another period.

Income can explicitly belong to a period independently of its receipt date; expected income uses the same association. Expenses and goals can also have an explicit period independent of their due date. Purchases remain dated ledger records, and no financial record is copied between periods. Records without explicit associations keep their earlier date-based income or cross-period target behavior. Starting a new period closes the previous one at the new start. Boundary edits rebind dated plans and allocations atomically. Invalid ranges and orphaned plans/allocations are rejected. IDs and generated display names remain stable after date edits. Generated display names are unique within the saved state and do not replace internal reference IDs.

Rollover is derived from the complete dated cash ledger, outstanding obligations, and savings allocations. Free surplus/deficit, protected savings, funded reservations, and unpaid obligations continue without synthetic income or double-counting. Essential rules retain their own calendar, recurrence, due dates, and stable occurrence IDs independently of budget duration.

## Validation and payment links

Plans reference a period ID and effective date. Savings allocations are signed dated adjustments referring to a period. Actual goal payments consume savings once. Essential occurrences link to one actual purchase when paid; deleting the purchase reopens the obligation. Reservations are not actual spending. Reports use the payment date when determining historical outstanding obligations.

Expected receipts retain the original expected date and amount after actual confirmation. Actual amount/date can differ, and the user explicitly chooses the receipt's period action. Expected income never funds a daily allowance or protected balance.

State validation checks formats, supported dates, unique IDs, period boundaries, references, recurrence, integer amounts, and payment links before persistence. Failed mutations leave active state and revision unchanged. Current-format recovery export and single-step undo remain supported.
