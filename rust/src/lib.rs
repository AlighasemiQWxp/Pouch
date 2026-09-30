pub mod api;
pub mod backup;
pub mod budget;
pub mod calendar;
pub mod core;
pub mod error;
pub mod expenses;
mod frb_generated; /* AUTO INJECTED BY flutter_rust_bridge. This line may not be accurate, and you can change it according to your needs. */
pub mod goals;
pub mod income;

pub mod models;
pub mod money;
pub mod preferences;
pub mod purchases;
pub mod reports;
pub mod savings;
pub mod storage;

pub use core::PouchCore;
pub use error::{PouchError, PouchResult};
pub use models::{AppState, Calendar, Date, Language, WeekStart};
pub use money::Money;
