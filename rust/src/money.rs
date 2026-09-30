use serde::{Deserialize, Serialize};

use crate::error::{PouchError, PouchResult};

pub const MAX_HUNDREDTHS: i64 = 1_000_000_000_000;

#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, Ord, PartialEq, PartialOrd, Serialize)]
pub struct Money(i64);

impl Money {
    pub fn from_hundredths(value: i64) -> PouchResult<Self> {
        if !(0..=MAX_HUNDREDTHS).contains(&value) {
            return Err(PouchError::InvalidAmount);
        }
        Ok(Self(value))
    }

    pub fn hundredths(self) -> i64 {
        self.0
    }

    pub fn checked_add(self, other: Self) -> PouchResult<Self> {
        let total = self
            .0
            .checked_add(other.0)
            .ok_or(PouchError::TotalTooLarge)?;
        if total > MAX_HUNDREDTHS {
            return Err(PouchError::TotalTooLarge);
        }
        Ok(Self(total))
    }

    pub fn checked_sub(self, other: Self) -> PouchResult<i64> {
        self.0.checked_sub(other.0).ok_or(PouchError::TotalTooLarge)
    }
}

pub fn parse_decimal(value: &str) -> PouchResult<Money> {
    let mut normalized = String::with_capacity(value.len());
    for character in value.trim().chars() {
        let digit = match character {
            '۰'..='۹' => Some((character as u32) - ('۰' as u32)),
            '٠'..='٩' => Some((character as u32) - ('٠' as u32)),
            _ => None,
        };
        if let Some(digit) = digit {
            normalized.push(char::from(b'0' + digit as u8));
        } else {
            match character {
                ',' | '٬' => {}
                '٫' => normalized.push('.'),
                _ => normalized.push(character),
            }
        }
    }
    let mut parts = normalized.split('.');
    let whole = parts.next().ok_or(PouchError::InvalidAmount)?;
    let fraction = parts.next();
    if parts.next().is_some()
        || whole.is_empty()
        || !whole.bytes().all(|digit| digit.is_ascii_digit())
        || fraction.is_some_and(|value| {
            value.is_empty()
                || value.len() > 2
                || !value.bytes().all(|digit| digit.is_ascii_digit())
        })
    {
        return Err(PouchError::InvalidAmount);
    }
    let whole = whole
        .parse::<i64>()
        .map_err(|_| PouchError::InvalidAmount)?;
    let fraction = match fraction {
        Some(value) if value.len() == 1 => {
            value
                .parse::<i64>()
                .map_err(|_| PouchError::InvalidAmount)?
                * 10
        }
        Some(value) => value
            .parse::<i64>()
            .map_err(|_| PouchError::InvalidAmount)?,
        None => 0,
    };
    let amount = whole
        .checked_mul(100)
        .and_then(|whole| whole.checked_add(fraction))
        .ok_or(PouchError::InvalidAmount)?;
    Money::from_hundredths(amount)
}

#[cfg(test)]
mod tests {
    use super::parse_decimal;

    #[test]
    fn decimal_parser_preserves_hundredths_and_local_digits() {
        let amount = parse_decimal("۱۲۳٬۴۵۶٫۷").expect("localized decimal is valid");

        assert_eq!(amount.hundredths(), 12_345_670);
    }

    #[test]
    fn decimal_parser_rejects_unsupported_precision_and_negative_values() {
        assert!(parse_decimal("1.234").is_err());
        assert!(parse_decimal("-1").is_err());
        assert!(parse_decimal("1..2").is_err());
    }
}
