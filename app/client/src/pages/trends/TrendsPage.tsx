import { useAnalyticsQuery, BarChart, LineChart } from '../../lib/appkit';

import { ChartCard, DashboardHeader, Kpi, count, currency, percent } from '../shared/dashboard-ui';
import { DEFAULT_YEAR } from '../shared/years';

const NO_PARAMS: Record<string, never> = {};

export function TrendsPage() {
  const { data: years, loading, error } = useAnalyticsQuery('revenue_trend', NO_PARAMS);

  const total = years?.reduce((sum, y) => sum + Number(y.total_sales), 0);
  const latest = years?.find((y) => Number(y.year) === DEFAULT_YEAR);
  const previous = years?.find((y) => Number(y.year) === DEFAULT_YEAR - 1);
  const growth =
    latest && previous
      ? ((Number(latest.total_sales) - Number(previous.total_sales)) / Number(previous.total_sales)) * 100
      : undefined;
  const ytd = years?.find((y) => Number(y.year) === DEFAULT_YEAR + 1);

  return (
    <div className="space-y-6 w-full max-w-7xl mx-auto">
      <DashboardHeader title="Trends 2016 – 2026" source="gold.mv_revenue_by_region" />

      {error && (
        <div className="text-destructive bg-destructive/10 p-3 rounded-md">Error: {error}</div>
      )}

      <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
        <Kpi label="Revenue, all years" value={total !== undefined ? currency(total) : undefined} loading={loading} />
        <Kpi label={`Revenue ${DEFAULT_YEAR}`} value={latest && currency(latest.total_sales)} loading={loading} />
        <Kpi
          label={`Growth vs ${DEFAULT_YEAR - 1}`}
          value={growth !== undefined ? percent(growth) : undefined}
          loading={loading}
        />
        <Kpi label={`${DEFAULT_YEAR + 1} to date (Jan–Sep)`} value={ytd && currency(ytd.total_sales)} loading={loading} />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <ChartCard title="Revenue and Profit by Year" wide>
          <LineChart
            queryKey="revenue_trend"
            parameters={NO_PARAMS}
            xKey="year"
            yKey={['total_sales', 'total_profit']}
            valueFormatter={currency}
            showLegend
            showSymbol
          />
        </ChartCard>

        <ChartCard title="Revenue by Region and Year" wide>
          <LineChart
            queryKey="revenue_trend_by_region"
            parameters={NO_PARAMS}
            xKey="year"
            yKey={['west', 'east', 'central', 'south', 'north']}
            valueFormatter={currency}
            showLegend
          />
        </ChartCard>

        <ChartCard title="Orders by Year" wide>
          <BarChart
            queryKey="revenue_trend"
            parameters={NO_PARAMS}
            xKey="year"
            yKey="order_count"
            valueFormatter={count}
          />
        </ChartCard>
      </div>
    </div>
  );
}
