import { AreaChart, BarChart, LineChart, useAnalyticsQuery } from '../../lib/components';
import { FilterBar } from '../../components/FilterBar';
import { YoyTable } from '../../components/YoyTable';
import { comparisonNote, useFilters, yoyDelta } from '../../lib/filters';
import { ChartCard, DashboardHeader, Kpi, count, currency, percent } from '../shared/dashboard-ui';

/** Revenue audit for one period: KPIs with year-over-year changes, monthly and regional comparisons. */
export function AnalyticsPage() {
  const { filters } = useFilters();
  const year = filters.target_year;
  const yoyLabels = { revenue: String(year), revenue_prior: String(year - 1), orders: String(year), orders_prior: String(year - 1) };
  const { data, loading, error } = useAnalyticsQuery('kpi_yoy', filters);
  const k = data?.[0];
  const note = comparisonNote(k);

  return (
    <div className="space-y-6 w-full max-w-7xl mx-auto">
      <DashboardHeader title="Revenue" source="gold.rpt_sales_lines" />
      <FilterBar />
      {error && <div className="text-destructive bg-destructive/10 p-3 rounded-md">Error: {error}</div>}

      <div className="grid grid-cols-2 md:grid-cols-5 gap-4">
        <Kpi label="Revenue" value={k && currency(k.revenue)} delta={yoyDelta(k, k?.revenue_yoy)} note={note} loading={loading} />
        <Kpi label="Profit" value={k && currency(k.profit)} delta={yoyDelta(k, k?.profit_yoy)} note={note} loading={loading} />
        <Kpi label="Margin" value={k && percent(k.margin_pct)} delta={yoyDelta(k, k?.margin_change_pts)} deltaSuffix=" pts" note={note} loading={loading} />
        <Kpi label="Orders" value={k && count(k.orders)} delta={yoyDelta(k, k?.orders_yoy)} note={note} loading={loading} />
        <Kpi label="Avg Order Value" value={k && currency(k.aov)} delta={yoyDelta(k, k?.aov_yoy)} note={note} loading={loading} />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <ChartCard title={`Revenue by Month: ${year} vs ${year - 1}`} wide>
          <LineChart queryKey="revenue_by_month" parameters={filters} xKey="month_name" yKey={['revenue', 'revenue_prior']}
            labels={yoyLabels} dashed={['revenue_prior']} valueFormatter={currency} showLegend showSymbol />
        </ChartCard>
        <ChartCard title={`Orders by Month: ${year} vs ${year - 1}`}>
          <BarChart queryKey="revenue_by_month" parameters={filters} xKey="month_name" yKey={['orders', 'orders_prior']}
            labels={yoyLabels} dashed={['orders_prior']} valueFormatter={count} showLegend />
        </ChartCard>
        <ChartCard title="Profit by Month">
          <AreaChart queryKey="revenue_by_month" parameters={filters} xKey="month_name" yKey="profit" valueFormatter={currency} />
        </ChartCard>
        <ChartCard title={`Revenue by Region: ${year} vs ${year - 1}`}>
          <BarChart queryKey="revenue_by_region" parameters={filters} xKey="region" yKey={['revenue', 'revenue_prior']}
            labels={yoyLabels} dashed={['revenue_prior']} valueFormatter={currency} showLegend />
        </ChartCard>
        <ChartCard title="Region Growth and Margin">
          <YoyTable queryKey="revenue_by_region" parameters={filters} columns={[
            { key: 'region', header: 'Region' },
            { key: 'revenue', header: String(year), format: currency },
            { key: 'revenue_prior', header: String(year - 1), format: currency },
            { key: 'yoy_pct', header: 'YoY', change: {} },
            { key: 'margin_pct', header: 'Margin', format: percent },
          ]} />
        </ChartCard>
        <ChartCard title="Segment Growth and Margin" wide>
          <YoyTable queryKey="segment_yoy" parameters={filters} columns={[
            { key: 'segment', header: 'Segment' },
            { key: 'revenue', header: String(year), format: currency },
            { key: 'revenue_prior', header: String(year - 1), format: currency },
            { key: 'yoy_pct', header: 'YoY', change: {} },
            { key: 'margin_pct', header: 'Margin', format: percent },
            { key: 'customers', header: 'Customers', format: count },
          ]} />
        </ChartCard>
      </div>
    </div>
  );
}
