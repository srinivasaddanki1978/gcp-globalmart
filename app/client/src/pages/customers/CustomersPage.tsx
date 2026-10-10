import { useAnalyticsQuery, BarChart, DonutChart, Label, Select, SelectContent, SelectItem, SelectTrigger, SelectValue, sql } from '../../lib/components';
import { useState } from 'react';

import { ChartCard, DashboardHeader, Kpi, count, currency } from '../shared/dashboard-ui';
import { YEARS, DEFAULT_YEAR } from '../shared/years';


/** flagged_return_customers scores run 0-100; 1 keeps every flagged row. */
const MIN_ANOMALY = 1;

export function CustomersPage() {
  const [year, setYear] = useState<number>(DEFAULT_YEAR);
  const parameters = { target_year: sql.number(year) };
  const flaggedParams = { min_anomaly: sql.number(MIN_ANOMALY) };

  const { data: summary, loading, error } = useAnalyticsQuery('customer_summary', parameters);
  const { data: flagged } = useAnalyticsQuery('flagged_by_region', flaggedParams);
  const totals = summary?.[0];
  const flaggedCount = flagged?.reduce((sum, r) => sum + Number(r.flagged_customers), 0);

  return (
    <div className="space-y-6 w-full max-w-7xl mx-auto">
      <DashboardHeader
        title="Customers"
        source="gold.dim_customers + fact_sales + flagged_return_customers"
      >
        <div className="space-y-2 w-48">
          <Label htmlFor="customer-year">Year</Label>
          <Select value={year.toString()} onValueChange={(value) => setYear(parseInt(value))}>
            <SelectTrigger id="customer-year">
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
        <Kpi label="Active Customers" value={totals && count(totals.customers)} loading={loading} />
        <Kpi label="Total Sales" value={totals && currency(totals.total_sales)} loading={loading} />
        <Kpi
          label="Avg Order Value"
          value={totals && currency(totals.avg_order_value)}
          loading={loading}
        />
        <Kpi
          label="Flagged for Returns"
          value={flaggedCount !== undefined ? count(flaggedCount) : undefined}
          loading={loading}
        />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <ChartCard title="Customers by Region">
          <BarChart
            queryKey="customers_by_region"
            parameters={parameters}
            xKey="region"
            yKey="customers"
            valueFormatter={count}
          />
        </ChartCard>

        <ChartCard title="Sales by Customer Segment">
          <DonutChart
            queryKey="customers_by_segment"
            parameters={parameters}
            xKey="segment"
            yKey="total_sales"
            valueFormatter={currency}
            showLegend
          />
        </ChartCard>

        <ChartCard title="Avg Order Value by Segment">
          <BarChart
            queryKey="customers_by_segment"
            parameters={parameters}
            xKey="segment"
            yKey="avg_order_value"
            valueFormatter={currency}
          />
        </ChartCard>

        <ChartCard title="Flagged Return Customers by Region">
          <BarChart
            queryKey="flagged_by_region"
            parameters={flaggedParams}
            xKey="region"
            yKey="flagged_customers"
            valueFormatter={count}
          />
        </ChartCard>

        <ChartCard title="Top 10 States by Sales" wide>
          <BarChart
            queryKey="top_states"
            parameters={parameters}
            xKey="state"
            yKey="total_sales"
            valueFormatter={currency}
          />
        </ChartCard>

        <ChartCard title="Top 10 Customers by Spend" wide>
          <BarChart
            queryKey="top_customers"
            parameters={parameters}
            xKey="customer_name"
            yKey="total_sales"
            valueFormatter={currency}
          />
        </ChartCard>
      </div>
    </div>
  );
}
