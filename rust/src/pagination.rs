use std::ops::Range;

use crate::{PouchError, PouchResult};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Pagination {
    pub page: usize,
    pub page_size: usize,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Page<T> {
    pub items: Vec<T>,
    pub page: usize,
    pub page_size: usize,
    pub total_items: usize,
}

impl Pagination {
    pub fn validate(&self) -> PouchResult<()> {
        if self.page == 0 || !(1..=100).contains(&self.page_size) {
            return Err(PouchError::InvalidPagination);
        }
        Ok(())
    }

    pub fn range(&self, total_items: usize) -> PouchResult<Range<usize>> {
        self.validate()?;
        let start = (self.page - 1)
            .saturating_mul(self.page_size)
            .min(total_items);
        let end = start.saturating_add(self.page_size).min(total_items);
        Ok(start..end)
    }

    pub fn paginate<T>(&self, items: Vec<T>) -> PouchResult<Page<T>> {
        let total_items = items.len();
        let range = self.range(total_items)?;
        Ok(Page {
            items: items
                .into_iter()
                .skip(range.start)
                .take(range.len())
                .collect(),
            page: self.page,
            page_size: self.page_size,
            total_items,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::Pagination;
    use crate::PouchError;

    #[test]
    fn invalid_requests_are_rejected_even_for_empty_lists() {
        for (page, page_size) in [(0, 10), (1, 0), (1, 101), (0, 0)] {
            let pagination = Pagination { page, page_size };
            assert!(matches!(
                pagination.paginate(Vec::<u8>::new()),
                Err(PouchError::InvalidPagination)
            ));
        }
        for page_size in [1, 100] {
            assert!(Pagination { page: 1, page_size }.validate().is_ok());
        }
    }

    #[test]
    fn pages_include_metadata_and_a_partial_last_page() {
        let items: Vec<_> = (0..5).collect();
        let mut combined = Vec::new();
        for page in 1..=3 {
            let result = Pagination { page, page_size: 2 }
                .paginate(items.clone())
                .expect("valid page");
            assert_eq!(result.page, page);
            assert_eq!(result.page_size, 2);
            assert_eq!(result.total_items, 5);
            combined.extend(result.items);
        }
        assert_eq!(combined, items);
    }

    #[test]
    fn empty_and_out_of_range_pages_preserve_the_request() {
        for items in [vec![], vec![1, 2, 3]] {
            let total = items.len();
            let result = Pagination {
                page: usize::MAX,
                page_size: 100,
            }
            .paginate(items)
            .expect("valid page");
            assert!(result.items.is_empty());
            assert_eq!(result.page, usize::MAX);
            assert_eq!(result.page_size, 100);
            assert_eq!(result.total_items, total);
        }
        assert_eq!(
            Pagination {
                page: 1,
                page_size: 10
            }
            .range(0)
            .expect("valid range"),
            0..0
        );
        assert_eq!(
            Pagination {
                page: 4,
                page_size: 1
            }
            .range(3)
            .expect("valid range"),
            3..3
        );
    }

    #[test]
    fn range_calculation_does_not_overflow() {
        let pagination = Pagination {
            page: usize::MAX,
            page_size: 100,
        };
        assert_eq!(
            pagination.range(usize::MAX).expect("valid range"),
            usize::MAX..usize::MAX
        );
        let pagination = Pagination {
            page: usize::MAX,
            page_size: 1,
        };
        assert_eq!(
            pagination.range(usize::MAX).expect("valid range"),
            (usize::MAX - 1)..usize::MAX
        );
    }
}
