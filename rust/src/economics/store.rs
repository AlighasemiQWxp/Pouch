use super::{Download, ExchangeRate, METHOD_VERSION, Profile};
use atomicwrites::{AllowOverwrite, AtomicFile};
use serde::{Deserialize, Serialize};
use std::{
    collections::BTreeMap,
    fs,
    io::Write,
    path::{Path, PathBuf},
    sync::Mutex,
};

const MAX_CACHE: u64 = 200_000;

#[derive(Clone, Default, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct Cache {
    version: u16,
    profiles: BTreeMap<String, Profile>,
    exchange_rates: BTreeMap<String, ExchangeRate>,
}

impl Cache {
    fn validate(&self) -> Result<(), String> {
        if self.version != METHOD_VERSION
            || self.profiles.len() > 250
            || self.exchange_rates.len() > 250
        {
            return Err("invalid_cache".into());
        }
        for (country, profile) in &self.profiles {
            profile.validate()?;
            if country != &profile.country {
                return Err("invalid_cache".into());
            }
        }
        for (currency, exchange) in &self.exchange_rates {
            exchange.validate()?;
            if currency != &exchange.currency {
                return Err("invalid_cache".into());
            }
        }
        Ok(())
    }
}

pub struct EconomicStore {
    path: PathBuf,
    write_lock: Mutex<()>,
}

pub struct CachedData {
    cache: Cache,
    warning: bool,
}

impl EconomicStore {
    pub fn new(directory: impl AsRef<Path>) -> Self {
        Self {
            path: directory.as_ref().join("economic-profiles-v1.json"),
            write_lock: Mutex::new(()),
        }
    }

    pub fn read(&self) -> CachedData {
        let empty = || Cache {
            version: METHOD_VERSION,
            ..Cache::default()
        };
        match read(&self.path) {
            Ok(Some(cache)) => CachedData {
                cache,
                warning: false,
            },
            Ok(None) => match read(&self.path.with_extension("json.backup")) {
                Ok(Some(cache)) => CachedData {
                    cache,
                    warning: true,
                },
                Ok(None) => CachedData {
                    cache: empty(),
                    warning: false,
                },
                Err(_) => CachedData {
                    cache: empty(),
                    warning: true,
                },
            },
            Err(_) => match read(&self.path.with_extension("json.backup")) {
                Ok(Some(cache)) => CachedData {
                    cache,
                    warning: true,
                },
                _ => CachedData {
                    cache: empty(),
                    warning: true,
                },
            },
        }
    }

    pub fn save(&self, mut download: Download) -> Result<(), String> {
        download.profile.validate()?;
        if let Some(exchange) = &download.exchange {
            exchange.validate()?;
        }
        let _guard = self.write_lock.lock().map_err(|_| "cache_save_failed")?;
        let previous = self.read();
        if download
            .profile
            .observations
            .iter()
            .any(|entry| entry.indicator == "annual_net")
            && !download
                .profile
                .observations
                .iter()
                .any(|entry| entry.indicator == "cad_per_local")
            && let Some(old) = previous.cache.profiles.get(&download.profile.country)
            && let Some(exchange) = old
                .observations
                .iter()
                .find(|entry| entry.indicator == "cad_per_local")
        {
            download.profile.observations.push(exchange.clone());
        }
        let mut next = previous.cache.clone();
        let country = download.profile.country.clone();
        if next
            .profiles
            .get(&country)
            .is_none_or(|old| old.downloaded <= download.profile.downloaded)
        {
            next.profiles.insert(country, download.profile);
        }
        if let Some(exchange) = download.exchange
            && next
                .exchange_rates
                .get(&exchange.currency)
                .is_none_or(|old| old.date <= exchange.date)
        {
            next.exchange_rates
                .insert(exchange.currency.clone(), exchange);
        }
        next.validate()?;
        let bytes = serde_json::to_vec(&next).map_err(|_| "cache_save_failed")?;
        if bytes.len() > MAX_CACHE as usize {
            return Err("cache_save_failed".into());
        }
        if !previous.warning && !previous.cache.profiles.is_empty() {
            let backup = serde_json::to_vec(&previous.cache).map_err(|_| "cache_save_failed")?;
            write(&self.path.with_extension("json.backup"), &backup)?;
        }
        write(&self.path, &bytes)
    }
}

impl CachedData {
    pub fn profile(&self, country: &str) -> Option<&Profile> {
        self.cache.profiles.get(country)
    }
    pub fn exchange(&self, currency: &str) -> Option<&ExchangeRate> {
        self.cache.exchange_rates.get(currency)
    }
    pub fn warning(&self) -> bool {
        self.warning
    }
}

fn read(path: &Path) -> Result<Option<Cache>, String> {
    match fs::metadata(path) {
        Ok(metadata) if metadata.len() > MAX_CACHE => return Err("invalid_cache".into()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(_) => return Err("invalid_cache".into()),
        _ => {}
    }
    let bytes = fs::read(path).map_err(|_| "invalid_cache")?;
    let cache: Cache = serde_json::from_slice(&bytes).map_err(|_| "invalid_cache")?;
    cache.validate()?;
    Ok(Some(cache))
}

fn write(path: &Path, bytes: &[u8]) -> Result<(), String> {
    AtomicFile::new(path, AllowOverwrite)
        .write(|file| {
            file.write_all(bytes)?;
            file.sync_all()
        })
        .map_err(|_| "cache_save_failed".into())
}
