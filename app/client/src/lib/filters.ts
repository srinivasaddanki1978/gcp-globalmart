// Dashboard filters, kept in the URL (?target_year=2024&region=East…) so a filtered view can
// be bookmarked or shared. Global filters follow you between pages; page filters (ship mode,
// brand, return reason…) reset when you leave the page.
import { useMemo } from 'react';
import { useSearchParams } from 'react-router';

export const DEFAULTS = {
  target_year: 2025,
  period: 'FY',
  region: 'All',
  segment: 'All',
  vendor: 'All',
  ship_mode: 'All',
  payment_type: 'All',
  brand: 'All',
  return_reason: 'All',
  return_status: 'All',
};
export type Filters = typeof DEFAULTS;
export type FilterKey = keyof Filters;

export const GLOBAL_KEYS: FilterKey[] = ['target_year', 'period', 'region', 'segment', 'vendor'];

export const PERIODS: { value: string; label: string }[] = [
  { value: 'FY', label: 'Full year' },
  { value: 'YTD', label: 'Year to date' },
  { value: 'Q1', label: 'Q1 (Jan–Mar)' },
  { value: 'Q2', label: 'Q2 (Apr–Jun)' },
  { value: 'Q3', label: 'Q3 (Jul–Sep)' },
  { value: 'Q4', label: 'Q4 (Oct–Dec)' },
];
export const REGIONS = ['East', 'West', 'South', 'Central', 'North'];
export const SEGMENTS = ['Consumer', 'Corporate', 'Home Office'];
export const RETURN_STATUSES = ['Approved', 'Pending', 'Rejected'];

export function useFilters() {
  const [search, setSearch] = useSearchParams();

  const filters = useMemo(() => {
    const f = { ...DEFAULTS } as Record<FilterKey, string | number>;
    for (const key of Object.keys(DEFAULTS) as FilterKey[]) {
      const v = search.get(key);
      if (v !== null) f[key] = key === 'target_year' ? Number(v) || DEFAULTS.target_year : v;
    }
    return f as Filters;
  }, [search]);

  function set(key: FilterKey, value: string | number) {
    setSearch(
      (prev) => {
        const next = new URLSearchParams(prev);
        if (value === DEFAULTS[key]) next.delete(key);
        else next.set(key, String(value));
        return next;
      },
      { replace: true },
    );
  }

  const active = (Object.keys(DEFAULTS) as FilterKey[]).filter((k) => filters[k] !== DEFAULTS[k]);
  return { filters, set, active, reset: () => setSearch({}, { replace: true }) };
}

/** Query string carrying only the global filters, for links between pages. */
export function globalSearch(search: URLSearchParams): string {
  const keep = new URLSearchParams();
  for (const k of GLOBAL_KEYS) {
    const v = search.get(k);
    if (v !== null) keep.set(k, v);
  }
  const s = keep.toString();
  return s ? `?${s}` : '';
}

/** "vs 2024", or "vs Jan, Feb, Mar 2024 only" when the prior year only partly overlaps. */
export function comparisonNote(k?: {
  prior_year?: number;
  months_with_data?: number;
  months_compared?: number;
  compared_months?: string | null;
}): string | undefined {
  if (!k || k.prior_year === undefined) return undefined;
  if (!k.months_with_data) return 'No data in this period';
  if (!k.months_compared) return `No ${k.prior_year} data to compare`;
  if (k.months_compared < k.months_with_data) return `vs ${k.compared_months} ${k.prior_year} only (like-for-like)`;
  return `vs ${k.prior_year}`;
}

/** The YoY change, or null when fewer than half the period's months can be compared
 *  (e.g. 2017 vs 2016, which overlap in October only). The note still explains it. */
export function yoyDelta(
  k: { months_with_data?: number; months_compared?: number } | undefined,
  value: number | null | undefined,
): number | null {
  if (!k || value === null || value === undefined) return null;
  return (k.months_compared ?? 0) * 2 >= (k.months_with_data ?? 0) ? value : null;
}
