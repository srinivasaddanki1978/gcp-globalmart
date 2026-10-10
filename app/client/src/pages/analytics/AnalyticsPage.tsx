import { useAnalyticsQuery, AreaChart, BarChart, LineChart, Label, Select, SelectContent, SelectItem, SelectTrigger, SelectValue, sql } from '../../lib/appkit';
import { useState } from 'react';

import { ChartCard, DashboardHeader, Kpi, count, currency } from '../shared/dashboard-ui';
import { YEARS, DEFAULT_YEAR } from '../shared/years';

/** Years present in gold.mv_revenue_by_region. */

export function AnalyticsPage() {
  const [year, setYear] = useState<number>(DEFAULT_YEAR);
  const parameters = { target_year: sql.number(year) };

  const { data: summary, loading, error } = useAnalyticsQuery('revenue_summary', parameters);
  const totals = summary?.[0];

  return (
    <div className="space-y-6 w-full max-w-7xl mx-auto">
      <DashboardHeader title="Revenue" source="gold.mv_revenue_by_region">
        <div className="space-y-2 w-48">
          <Label htmlFor="year">Year</Label>
          <Select value={year.toString()} onValueChange={(value) => setYear(parseInt(value))}>
            <SelectTrigger id="year">
              <SelectValue placeholder="Select year" />
            </SelectTrigger>
            <SelectContent>
              {YEARS.map((y) => (
                <SelectItem key={y} value={y.toString()}>
                  {y}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
      </DashboardHeader>

      {error && (
        <div className="text-destructive bg-destructive/10 p-3 rounded-md">Error: {error}</div>
      )}

      <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
        <Kpi label="Total Sales" value={totals && currency(totals.total_sales)} loading={loading} />
        <Kpi label="Total Profit" value={totals && currency(totals.total_profit)} loading={loading} />
        <Kpi label="Orders" value={totals && count(totals.order_count)} loading={loading} />
        <Kpi
          label="Unique Customers"
          value={totals && count(totals.unique_customers)}
          loading={loading}
        />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <ChartCard title="Sales by Month">
          <AreaChart
            queryKey="revenue_by_month"
            parameters={parameters}
            xKey="month_name"
            yKey={['total_sales', 'total_profit']}
            valueFormatter={currency}
            showLegend
          />
        </ChartCard>

        <ChartCard title="Orders by Month">
          <LineChart
            queryKey="revenue_by_month"
            parameters={parameters}
            xKey="month_name"
            yKey="order_count"
            valueFormatter={count}
          />
        </ChartCard>

        <ChartCard title="Sales by Region" wide>
          <BarChart
            queryKey="revenue_by_region"
            parameters={parameters}
            xKey="region"
            yKey={['total_sales', 'total_profit']}
            valueFormatter={currency}
            showLegend
          />
        </ChartCard>
      </div>
    </div>
  );
}
