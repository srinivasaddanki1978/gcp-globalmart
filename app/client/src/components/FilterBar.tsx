import type { ReactNode } from 'react';
import { RotateCcw } from 'lucide-react';
import { useAnalyticsQuery } from '../lib/api';
import { DEFAULTS, GLOBAL_KEYS, PERIODS, REGIONS, SEGMENTS, useFilters, type FilterKey } from '../lib/filters';
import { YEARS } from '../pages/shared/years';

type Option = { value: string; label: string };
const all = (values: string[]): Option[] => [{ value: 'All', label: 'All' }, ...values.map((v) => ({ value: v, label: v }))];

/** Filter options that come from the data (vendors, brands, ship modes, payment types, return reasons). */
export function useFilterOptions() {
  const { data } = useAnalyticsQuery('filter_options');
  return (kind: string) => all((data ?? []).filter((r) => r.kind === kind).map((r) => String(r.value)));
}

export function FilterSelect({ name, label, options }: { name: FilterKey; label: string; options: Option[] }) {
  const { filters, set } = useFilters();
  const value = String(filters[name]);
  const changed = value !== String(DEFAULTS[name]);
  return (
    <label className="flex flex-col gap-1 text-xs font-medium text-muted-foreground">
      {label}
      <select
        value={value}
        onChange={(e) => set(name, name === 'target_year' ? Number(e.target.value) : e.target.value)}
        className={`h-9 min-w-32 rounded-md border bg-background px-2 text-sm text-foreground ${changed ? 'border-primary ring-1 ring-primary/30' : ''}`}
      >
        {options.map((o) => (
          <option key={o.value} value={o.value}>
            {o.label}
          </option>
        ))}
      </select>
    </label>
  );
}

/**
 * Global filters (year, period, region, segment, vendor) plus any page filters passed as
 * children. `show` limits the global filters, e.g. the Trends page has no year or period.
 */
export function FilterBar({ show = GLOBAL_KEYS, children }: { show?: FilterKey[]; children?: ReactNode }) {
  const { active, reset } = useFilters();
  const options = useFilterOptions();
  const has = (k: FilterKey) => show.includes(k);
  return (
    <div className="flex flex-wrap items-end gap-3 rounded-lg border bg-muted/40 p-3">
      {has('target_year') && (
        <FilterSelect name="target_year" label="Year" options={YEARS.map((y) => ({ value: String(y), label: String(y) }))} />
      )}
      {has('period') && <FilterSelect name="period" label="Period" options={PERIODS} />}
      {has('region') && <FilterSelect name="region" label="Region" options={all(REGIONS)} />}
      {has('segment') && <FilterSelect name="segment" label="Segment" options={all(SEGMENTS)} />}
      {has('vendor') && <FilterSelect name="vendor" label="Vendor" options={options('vendor')} />}
      {children}
      {active.length > 0 && (
        <button onClick={reset} className="ml-auto inline-flex h-9 items-center gap-1 rounded-md px-3 text-sm text-muted-foreground hover:bg-muted">
          <RotateCcw className="h-4 w-4" /> Reset filters
        </button>
      )}
    </div>
  );
}
