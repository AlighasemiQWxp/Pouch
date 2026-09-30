use thiserror::Error;

pub type PouchResult<T> = Result<T, PouchError>;

#[derive(Debug, Error)]
pub enum PouchError {
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
    #[error("This storage format version is newer than this application supports.")]
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
