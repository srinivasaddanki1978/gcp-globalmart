import { BarChart, useAnalyticsQuery } from '../../lib/components';
import { FilterBar, FilterSelect, useFilterOptions } from '../../components/FilterBar';
import { YoyTable } from '../../components/YoyTable';
import { useFilters } from '../../lib/filters';
import { ChartCard, DashboardHeader, Kpi, count, currency, percent } from '../shared/dashboard-ui';

/** Slow movers that never shipped a unit aren't actionable. */
const MIN_QUANTITY = 1;

/** Vendor return rates (with YoY change) and inventory tied up in slow movers. */
export function OperationsPage() {
  const { filters } = useFilters();
  const options = useFilterOptions();
  const year = filters.target_year;
  const params = { ...filters, min_quantity: MIN_QUANTITY };
  const { data: vendors, loading: vl, error: ve } = useAnalyticsQuery('vendor_return_yoy', params);
  const { data: regions, loading: rl, error: re } = useAnalyticsQuery('slow_moving_by_region', params);
  const worst = vendors?.[0];
  const returned = vendors?.reduce((s, v) => s + Number(v.returned_orders), 0);
  const slowCount = regions?.reduce((s, r) => s + Number(r.product_count), 0);
  const slowValue = regions?.reduce((s, r) => s + Number(r.total_sales), 0);
  const error = ve || re;

  return (
    <div className="space-y-6 w-full max-w-7xl mx-auto">
      <DashboardHeader title="Operations" source="gold.rpt_sales_lines + mv_slow_moving_products" />
      <FilterBar>
        <FilterSelect name="brand" label="Brand" options={options('brand')} />
      </FilterBar>
      {error && <div className="text-destructive bg-destructive/10 p-3 rounded-md">Error: {error}</div>}

      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <Kpi label={`Highest Return Rate${worst ? ` · ${worst.vendor_name}` : ''}`} value={worst && percent(worst.return_rate_pct)}
          delta={worst?.change_pts} deltaSuffix=" pts" invert note={`vs ${year - 1}`} loading={vl} />
        <Kpi label="Orders Returned" value={returned !== undefined ? count(returned) : undefined} note={`orders placed in ${year}`} loading={vl} />
        <Kpi label="Slow-Moving Products" value={slowCount !== undefined ? count(slowCount) : undefined} note="all history" loading={rl} />
        <Kpi label="Value Tied Up" value={slowValue !== undefined ? currency(slowValue) : undefined} note="all history" loading={rl} />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <ChartCard title={`Vendor Return Rate: ${year} vs ${year - 1}`}>
          <BarChart queryKey="vendor_return_yoy" parameters={params} xKey="vendor_name" yKey={['return_rate_pct', 'return_rate_pct_prior']}
            labels={{ return_rate_pct: String(year), return_rate_pct_prior: String(year - 1) }} dashed={['return_rate_pct_prior']}
            valueFormatter={percent} showLegend />
        </ChartCard>
        <ChartCard title="Vendors: Is Anyone Getting Worse?">
          <YoyTable queryKey="vendor_return_yoy" parameters={params} columns={[
            { key: 'vendor_name', header: 'Vendor' },
            { key: 'orders', header: 'Orders', format: count },
            { key: 'return_rate_pct', header: String(year), format: percent },
            { key: 'return_rate_pct_prior', header: String(year - 1), format: percent },
            { key: 'change_pts', header: 'Change', change: { suffix: ' pts', invert: true } },
          ]} />
        </ChartCard>
        <ChartCard title="Slow-Moving Products by Region (all history)">
          <BarChart queryKey="slow_moving_by_region" parameters={params} xKey="region" yKey="product_count" valueFormatter={count} />
        </ChartCard>
        <ChartCard title="Brands with Most Slow Movers (all history)">
          <BarChart queryKey="slow_moving_by_brand" parameters={params} xKey="brand" yKey="product_count" valueFormatter={count} />
        </ChartCard>
      </div>
    </div>
  );
}
