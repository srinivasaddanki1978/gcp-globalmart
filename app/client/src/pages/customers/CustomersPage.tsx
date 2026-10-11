import { BarChart, useAnalyticsQuery } from '../../lib/components';
import { FilterBar } from '../../components/FilterBar';
import { YoyTable } from '../../components/YoyTable';
import { comparisonNote, useFilters, yoyDelta } from '../../lib/filters';
import { ChartCard, DashboardHeader, Kpi, count, currency } from '../shared/dashboard-ui';

/** Active customers by region, segment and state, with year-over-year changes. */
export function CustomersPage() {
  const { filters } = useFilters();
  const year = filters.target_year;
  const { data, loading, error } = useAnalyticsQuery('kpi_yoy', filters);
  const k = data?.[0];
  const note = comparisonNote(k);
  const perCustomer = k && k.customers ? k.revenue / k.customers : undefined;

  return (
    <div className="space-y-6 w-full max-w-7xl mx-auto">
      <DashboardHeader title="Customers" source="gold.rpt_sales_lines (customer as of the order)" />
      <FilterBar />
      {error && <div className="text-destructive bg-destructive/10 p-3 rounded-md">Error: {error}</div>}

      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <Kpi label="Active Customers" value={k && count(k.customers)} delta={yoyDelta(k, k?.customers_yoy)} note={note} loading={loading} />
        <Kpi label="Revenue" value={k && currency(k.revenue)} delta={yoyDelta(k, k?.revenue_yoy)} note={note} loading={loading} />
        <Kpi label="Revenue per Customer" value={perCustomer !== undefined ? currency(perCustomer) : undefined} loading={loading} />
        <Kpi label="Avg Order Value" value={k && currency(k.aov)} delta={yoyDelta(k, k?.aov_yoy)} note={note} loading={loading} />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <ChartCard title={`Active Customers by Region: ${year} vs ${year - 1}`}>
          <BarChart queryKey="customers_by_region" parameters={filters} xKey="region" yKey={['customers', 'customers_prior']}
            labels={{ customers: String(year), customers_prior: String(year - 1) }} dashed={['customers_prior']} valueFormatter={count} showLegend />
        </ChartCard>
        <ChartCard title="Segments">
          <YoyTable queryKey="customers_by_segment" parameters={filters} columns={[
            { key: 'segment', header: 'Segment' },
            { key: 'customers', header: 'Customers', format: count },
            { key: 'yoy_pct', header: 'YoY', change: {} },
            { key: 'revenue', header: 'Revenue', format: currency },
            { key: 'avg_order_value', header: 'Avg order', format: currency },
          ]} />
        </ChartCard>
        <ChartCard title={`Top 10 States: ${year} vs ${year - 1}`}>
          <BarChart queryKey="top_states" parameters={filters} xKey="state" yKey={['revenue', 'revenue_prior']}
            labels={{ revenue: String(year), revenue_prior: String(year - 1) }} dashed={['revenue_prior']} valueFormatter={currency} showLegend />
        </ChartCard>
        <ChartCard title="Top 10 Customers">
          <YoyTable queryKey="top_customers" parameters={filters} columns={[
            { key: 'customer', header: 'Customer' },
            { key: 'segment', header: 'Segment' },
            { key: 'revenue', header: String(year), format: currency },
            { key: 'revenue_prior', header: String(year - 1), format: currency },
          ]} />
        </ChartCard>
      </div>
    </div>
  );
}
