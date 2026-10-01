# Pouch data formats

Pouch stores its active state in an app-private, versioned binary file. Portable JSON backups are available for export and restore.

## Binary state

The Rust storage layer encodes state with Serde and Postcard. A fixed marker, format version, payload length, and checksum protect the file from incomplete or invalid writes. Updates are written to a temporary file in the same private directory and atomically replace the primary file only after validation. A recovery copy is kept for use if the primary cannot be read.

The current state schema is version 2. It adds the country preference and a separate list of expected income. Version 1 state files are migrated on load without changing their existing currency, language, calendar, week start, or recorded income.

## JSON backups

Pouch exports the current JSON backup schema as version 5. It includes the country preference and expected income entries. Import accepts supported schema versions 1 through 5, validates all values, and builds a complete state before it is saved. Older backups retain their existing currency, language, calendar, and week start; their country is set to manual and they have no expected income entries. Unsupported, oversized, or invalid JSON is rejected without replacing the active data. The import limit is 5,000,000 bytes.

Money values are stored as integers in the smallest supported unit. Dates in persisted records use ISO Gregorian values; the selected calendar is used for display and entry. English and Persian interfaces share these same stored values. Expected income does not affect budget calculations until it is marked received and moved into recorded income.

## Restore and recovery

Restore validates the selected document before replacing active state. If a primary write fails, the in-memory state stays unchanged. A separate recovery copy is available from the app's backup controls when the primary state cannot be read.

Keep exported JSON files private. They may contain purchase descriptions, amounts, income, planned expenses, savings goals, and preferences.
