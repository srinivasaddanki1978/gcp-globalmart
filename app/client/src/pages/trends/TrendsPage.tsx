import { BarChart, LineChart } from '../../lib/components';
import { FilterBar } from '../../components/FilterBar';
import { YoyTable } from '../../components/YoyTable';
import { useFilters } from '../../lib/filters';
import { ChartCard, DashboardHeader, count, currency, percent } from '../shared/dashboard-ui';

const pct = (v: number) => `${v > 0 ? '+' : ''}${v.toFixed(1)}%`;

/** Ten years at a glance, with like-for-like year-over-year growth. */
export function TrendsPage() {
  const { filters } = useFilters();
  return (
    <div className="space-y-6 w-full max-w-7xl mx-auto">
      <DashboardHeader title="Trends 2016 – 2026" source="gold.rpt_sales_lines" />
      <FilterBar show={['region', 'segment', 'vendor']} />
      <p className="text-sm text-muted-foreground">
        Growth compares each year with the previous one over the months both have data. 2016 has only October, so 2017
        has no annual growth figure; 2026 runs to September and is compared with January–September 2025.
      </p>
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <ChartCard title="Revenue and Profit by Year" wide>
          <LineChart queryKey="revenue_trend" parameters={filters} xKey="year" yKey={['total_sales', 'total_profit']}
            labels={{ total_sales: 'Revenue', total_profit: 'Profit' }} valueFormatter={currency} showLegend showSymbol />
        </ChartCard>
        <ChartCard title="Year-over-Year Revenue Growth (like-for-like)">
          <BarChart queryKey="revenue_trend" parameters={filters} xKey="year" yKey="yoy_pct" labels={{ yoy_pct: 'YoY growth' }} valueFormatter={pct} />
        </ChartCard>
        <ChartCard title="Margin by Year">
          <LineChart queryKey="revenue_trend" parameters={filters} xKey="year" yKey="margin_pct" labels={{ margin_pct: 'Margin' }} valueFormatter={percent} showSymbol />
        </ChartCard>
        <ChartCard title="Revenue by Region and Year" wide>
          <LineChart queryKey="revenue_trend_by_region" parameters={filters} xKey="year" yKey={['east', 'west', 'south', 'central', 'north']}
            valueFormatter={currency} showLegend showSymbol />
        </ChartCard>
        <ChartCard title="Yearly Summary" wide>
          <YoyTable queryKey="revenue_trend" parameters={filters} columns={[
            { key: 'year', header: 'Year' },
            { key: 'total_sales', header: 'Revenue', format: currency },
            { key: 'total_profit', header: 'Profit', format: currency },
            { key: 'margin_pct', header: 'Margin', format: percent },
            { key: 'order_count', header: 'Orders', format: count },
            { key: 'yoy_pct', header: 'YoY growth', change: {} },
          ]} />
        </ChartCard>
      </div>
    </div>
  );
}
