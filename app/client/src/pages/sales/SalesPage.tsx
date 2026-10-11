import { BarChart, DonutChart, useAnalyticsQuery } from '../../lib/components';
import { FilterBar, FilterSelect, useFilterOptions } from '../../components/FilterBar';
import { YoyTable } from '../../components/YoyTable';
import { comparisonNote, useFilters, yoyDelta } from '../../lib/filters';
import { ChartCard, DashboardHeader, Kpi, count, currency, percent } from '../shared/dashboard-ui';

/** Sales mix (segments, shipping, payment, brands) with year-over-year changes. */
export function SalesPage() {
  const { filters } = useFilters();
  const options = useFilterOptions();
  const year = filters.target_year;
  const labels = { revenue: String(year), revenue_prior: String(year - 1) };
  const { data, loading, error } = useAnalyticsQuery('kpi_yoy', filters);
  const k = data?.[0];
  const note = comparisonNote(k);

  return (
    <div className="space-y-6 w-full max-w-7xl mx-auto">
      <DashboardHeader title="Sales" source="gold.rpt_sales_lines" />
      <FilterBar>
        <FilterSelect name="ship_mode" label="Ship mode" options={options('ship_mode')} />
        <FilterSelect name="payment_type" label="Payment" options={options('payment_type')} />
        <FilterSelect name="brand" label="Brand" options={options('brand')} />
      </FilterBar>
      {error && <div className="text-destructive bg-destructive/10 p-3 rounded-md">Error: {error}</div>}

      <div className="grid grid-cols-2 md:grid-cols-5 gap-4">
        <Kpi label="Revenue" value={k && currency(k.revenue)} delta={yoyDelta(k, k?.revenue_yoy)} note={note} loading={loading} />
        <Kpi label="Units Sold" value={k && count(k.units)} delta={yoyDelta(k, k?.units_yoy)} note={note} loading={loading} />
        <Kpi label="Orders" value={k && count(k.orders)} delta={yoyDelta(k, k?.orders_yoy)} note={note} loading={loading} />
        <Kpi label="Avg Order Value" value={k && currency(k.aov)} delta={yoyDelta(k, k?.aov_yoy)} note={note} loading={loading} />
        <Kpi label="Margin" value={k && percent(k.margin_pct)} delta={yoyDelta(k, k?.margin_change_pts)} deltaSuffix=" pts" note={note} loading={loading} />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <ChartCard title="Revenue by Customer Segment">
          <DonutChart queryKey="segment_yoy" parameters={filters} xKey="segment" yKey="revenue" valueFormatter={currency} />
        </ChartCard>
        <ChartCard title={`Revenue by Ship Mode: ${year} vs ${year - 1}`}>
          <BarChart queryKey="sales_by_ship_mode" parameters={filters} xKey="ship_mode" yKey={['revenue', 'revenue_prior']}
            labels={labels} dashed={['revenue_prior']} valueFormatter={currency} showLegend />
        </ChartCard>
        <ChartCard title={`Revenue by Payment Method: ${year} vs ${year - 1}`}>
          <BarChart queryKey="sales_by_payment" parameters={filters} xKey="payment_type" yKey={['revenue', 'revenue_prior']}
            labels={labels} dashed={['revenue_prior']} valueFormatter={currency} showLegend />
        </ChartCard>
        <ChartCard title="Segments: Growth and Margin">
          <YoyTable queryKey="segment_yoy" parameters={filters} columns={[
            { key: 'segment', header: 'Segment' },
            { key: 'revenue', header: String(year), format: currency },
            { key: 'yoy_pct', header: 'YoY', change: {} },
            { key: 'margin_pct', header: 'Margin', format: percent },
          ]} />
        </ChartCard>
        <ChartCard title="Brands: Who's Rising, Who's Falling" wide>
          <YoyTable queryKey="brand_yoy" parameters={filters} columns={[
            { key: 'brand', header: 'Brand' },
            { key: 'revenue', header: String(year), format: currency },
            { key: 'revenue_prior', header: String(year - 1), format: currency },
            { key: 'yoy_pct', header: 'YoY', change: {} },
            { key: 'units', header: 'Units', format: count },
          ]} />
        </ChartCard>
      </div>
    </div>
  );
}
