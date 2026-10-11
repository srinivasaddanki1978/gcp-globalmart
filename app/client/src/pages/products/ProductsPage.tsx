import { BarChart, DonutChart, useAnalyticsQuery } from '../../lib/components';
import { FilterBar, FilterSelect, useFilterOptions } from '../../components/FilterBar';
import { YoyTable } from '../../components/YoyTable';
import { comparisonNote, useFilters, yoyDelta } from '../../lib/filters';
import { ChartCard, DashboardHeader, Kpi, count, currency } from '../shared/dashboard-ui';

/** Catalogue performance and return cost, with year-over-year changes. */
export function ProductsPage() {
  const { filters } = useFilters();
  const options = useFilterOptions();
  const year = filters.target_year;
  const { data, loading, error } = useAnalyticsQuery('product_summary', filters);
  const k = data?.[0];
  const note = comparisonNote(k);

  return (
    <div className="space-y-6 w-full max-w-7xl mx-auto">
      <DashboardHeader title="Products" source="gold.rpt_sales_lines + rpt_return_product_lines" />
      <FilterBar>
        <FilterSelect name="brand" label="Brand" options={options('brand')} />
      </FilterBar>
      {error && <div className="text-destructive bg-destructive/10 p-3 rounded-md">Error: {error}</div>}

      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <Kpi label="Products Sold" value={k && count(k.products_sold)} delta={yoyDelta(k, k?.products_sold_yoy)} note={note} loading={loading} />
        <Kpi label="Units Sold" value={k && count(k.units)} delta={yoyDelta(k, k?.units_yoy)} note={note} loading={loading} />
        <Kpi label="Avg Unit Price" value={k && currency(k.avg_unit_price)} delta={yoyDelta(k, k?.avg_unit_price_yoy)} note={note} loading={loading} />
        <Kpi label="Refunded (by return date)" value={k && currency(k.refunded)} delta={yoyDelta(k, k?.refunded_yoy)} invert note={note} loading={loading} />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <ChartCard title={`Top 10 Products: ${year} vs ${year - 1}`} wide>
          <BarChart queryKey="top_products" parameters={filters} xKey="product_name" yKey={['revenue', 'revenue_prior']}
            labels={{ revenue: String(year), revenue_prior: String(year - 1) }} dashed={['revenue_prior']} valueFormatter={currency} showLegend />
        </ChartCard>
        <ChartCard title="Brands: Revenue, Growth and Range">
          <YoyTable queryKey="brand_yoy" parameters={filters} columns={[
            { key: 'brand', header: 'Brand' },
            { key: 'revenue', header: String(year), format: currency },
            { key: 'yoy_pct', header: 'YoY', change: {} },
            { key: 'products', header: 'Products', format: count },
          ]} />
        </ChartCard>
        <ChartCard title="Refunds by Return Reason">
          <DonutChart queryKey="returns_by_reason" parameters={filters} xKey="return_reason" yKey="refunded" valueFormatter={currency} />
        </ChartCard>
        <ChartCard title={`Most Refunded Products: ${year} vs ${year - 1}`} wide>
          <BarChart queryKey="top_returned_products" parameters={filters} xKey="product_name" yKey={['refunded', 'refunded_prior']}
            labels={{ refunded: String(year), refunded_prior: String(year - 1) }} dashed={['refunded_prior']} valueFormatter={currency} showLegend />
        </ChartCard>
        <ChartCard title="Return Reasons: Change in Refunds" wide>
          <YoyTable queryKey="returns_by_reason" parameters={filters} columns={[
            { key: 'return_reason', header: 'Reason' },
            { key: 'refunded', header: String(year), format: currency },
            { key: 'refunded_prior', header: String(year - 1), format: currency },
            { key: 'yoy_pct', header: 'YoY', change: { invert: true } },
            { key: 'return_lines', header: 'Return lines', format: count },
          ]} />
        </ChartCard>
      </div>
    </div>
  );
}
