use thiserror::Error;

pub type PouchResult<T> = Result<T, PouchError>;

#[derive(Debug, Error)]
pub enum PouchError {
    #[error("Choose a planning horizon for this date.")]
    MissingPeriod,
    #[error("A period already starts on this date. Add income to that period.")]
    PeriodAlreadyStarts,
    #[error("These dates would leave saved plans or savings outside a period.")]
    PeriodContainsPlan,
    #[error("Budget periods must have valid, non-overlapping boundaries.")]
    InvalidPeriod,
    #[error("Choose a page starting at 1 and a page size between 1 and 100.")]
    InvalidPagination,
    #[error("The amount is invalid or outside the supported range.")]
    InvalidAmount,
    #[error("The date or calendar preference is invalid.")]
    InvalidDate,
    #[error("The saved application data is invalid.")]
    InvalidState,
    #[error("This backup version is not supported.")]
    UnsupportedBackupVersion,
    #[error("The backup is invalid or could not be imported.")]
    InvalidBackup,
    #[error("There is no saved recovery copy.")]
    NoRecoveryCopy,
    #[error("Backup data exceeds the supported size.")]
    BackupTooLarge,
    #[error(
        "This development data format is incompatible. Reset local data to start a new budget."
    )]
    UnsupportedStorageVersion,
    #[error("The saved application data could not be read or recovered.")]
    StorageUnavailable,
    #[error("The saved application data failed its integrity check.")]
    CorruptStorage,
    #[error("The application data could not be saved.")]
    SaveFailed,
    #[error("The requested record does not exist or cannot be changed.")]
    InvalidEntry,
    #[error("Currency cannot change while budget amounts are recorded.")]
    CurrencyLocked,
    #[error("The calculated total is outside the supported range.")]
    TotalTooLarge,
    #[error("Choose a valid report period with no more than 366 days.")]
    InvalidReport,
}
