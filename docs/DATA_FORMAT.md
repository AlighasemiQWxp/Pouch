# Pouch data formats

The savings correction reads the two previous Flutter/Rust data formats and repairs derived savings allocations once. It does not import legacy WebView data or older incompatible development formats. Incompatible files are never silently deleted or overwritten.

## Binary state

The binary envelope is version **6**, and AppState schema is **8**. The envelope contains `POUCHDAT`, a version, payload length, checksum, and Serde/Postcard payload. Money is integer minor units; dates are Gregorian day offsets. Validated mutations use same-directory atomic writes and retain a recovery copy.

Envelopes 3/schema 5, 4/schema 6, and 5/schema 7 are upgraded through dedicated adapters. The upgrade rebuilds derived savings from saved savings plans and ledger records; goals do not create savings. Income, purchases, periods, plans, goal definitions, payment links, IDs, and period metadata are preserved. Previous versions did not store explicit goal assignments, so migrated goals begin with no amount assigned. The original valid binary bytes remain in the recovery file. Current-format reads do not repeat the repair. Unsupported formats remain untouched.

## JSON backup

Portable backups export version **11** with schema **8** and import versions **8**, **9**, **10**, and **11** with matching schemas **5**, **6**, **7**, and **8**. Older versions receive the same one-time savings repair. FinancialMetadata stores income labels, current explicit goal assignments, and savings-funded purchase IDs. Goal assignment history before the current value is not recorded. Backups retain the existing financial records, period metadata, preferences, and economic customizations. The limit is 5,000,000 bytes. JSON dates are ISO Gregorian strings.

Import validates the complete state before replacement. Invalid or unsupported backups leave active state unchanged. Backups contain private financial records.

## Periods and rollover

Each persisted `BudgetPeriod` contains a stable unique ID, inclusive `start`, exclusive `end`, planning preset (`recurrence`), and original `calendar`. Presets only suggest horizons; they never create financial records or further periods. A fresh state contains no period. At most 1000 periods are supported, with each horizon spanning at most 3660 days. Historical adjacent periods meet at a shared boundary; the last period can expire until the user edits its horizon or creates another period.

Income can explicitly belong to a period independently of its receipt date; expected income uses the same association. Expenses and goals can also have an explicit period independent of their due date. Purchases remain dated ledger records, and no financial record is copied between periods. Records without explicit associations keep their earlier date-based income or cross-period target behavior. Starting a new period closes the previous one at the new start. Boundary edits rebind dated plans and allocations atomically. Invalid ranges and orphaned plans/allocations are rejected. IDs and generated display names remain stable after date edits. Generated display names are unique within the saved state and do not replace internal reference IDs.

Rollover is derived from the complete dated cash ledger, outstanding obligations, and savings allocations. Free surplus/deficit, protected savings, funded reservations, and unpaid obligations continue without synthetic income or double-counting. Essential rules retain their own calendar, recurrence, due dates, and stable occurrence IDs independently of budget duration.

## Validation and payment links

Plans reference a period ID and effective date. Savings allocations are signed dated adjustments referring to a period. Actual goal payments consume savings once. Essential occurrences link to one actual purchase when paid; deleting the purchase reopens the obligation. Reservations are not actual spending. Reports use the payment date when determining historical outstanding obligations.

Expected receipts retain the original expected date and amount after actual confirmation. Actual amount/date can differ, and the user explicitly chooses the receipt's period action. Expected income never funds a daily allowance or protected balance.

State validation checks formats, supported dates, unique IDs, period boundaries, references, recurrence, integer amounts, and payment links before persistence. Failed mutations leave active state and revision unchanged. Current-format recovery export and single-step undo remain supported.
