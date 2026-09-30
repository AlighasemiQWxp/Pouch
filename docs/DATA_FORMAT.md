# Pouch data formats

Pouch stores its active state in an app-private, versioned binary file. Portable JSON backups are available for export and restore.

## Binary state

The Rust storage layer encodes state with Serde and Postcard. A fixed marker, format version, payload length, and checksum protect the file from incomplete or invalid writes. Updates are written to a temporary file in the same private directory and atomically replace the primary file only after validation. A recovery copy is kept for use if the primary cannot be read.

## JSON backups

Pouch exports the current JSON backup schema as version 4. Import accepts supported schema versions 1 through 4, validates all values, and builds a complete state before it is saved. Unsupported, oversized, or invalid JSON is rejected without replacing the active data. The import limit is 5,000,000 bytes.

Money values are stored as integers in the smallest supported unit. Dates in persisted records use ISO Gregorian values; the selected calendar is used for display and entry. English and Persian interfaces share these same stored values.

## Restore and recovery

Restore validates the selected document before replacing active state. If a primary write fails, the in-memory state stays unchanged. A separate recovery copy is available from the app's backup controls when the primary state cannot be read.

Keep exported JSON files private. They may contain purchase descriptions, amounts, income, planned expenses, savings goals, and preferences.
