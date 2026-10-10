/**
 * Years present in gold.fact_sales.
 * 2016 has only a few rows (data starts Oct 2016); 2026 runs to September.
 */
export const YEARS = Array.from({ length: 2026 - 2016 + 1 }, (_, i) => 2016 + i);

/** Latest full year of data, used as the default selection. */
export const DEFAULT_YEAR = 2025;
