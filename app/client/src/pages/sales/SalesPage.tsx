import { useAnalyticsQuery, BarChart, DonutChart, Label, Select, SelectContent, SelectItem, SelectTrigger, SelectValue, sql } from '../../lib/components';
import { useState } from 'react';

import { ChartCard, DashboardHeader, Kpi, count, currency, percent } from '../shared/dashboard-ui';
import { YEARS, DEFAULT_YEAR } from '../shared/years';


export function SalesPage() {
  const [year, setYear] = useState<number>(DEFAULT_YEAR);
  const parameters = { target_year: sql.number(year) };

  const { data: summary, loading, error } = useAnalyticsQuery('sales_summary', parameters);
  const totals = summary?.[0];

  return (
    <div className="space-y-6 w-full max-w-7xl mx-auto">
      <DashboardHeader title="Sales" source="gold.fact_sales + dim_products + dim_customers">
        <div className="space-y-2 w-48">
          <Label htmlFor="sales-year">Year</Label>
          <Select value={year.toString()} onValueChange={(value) => setYear(parseInt(value))}>
            <SelectTrigger id="sales-year">
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
        <Kpi label="Units Sold" value={totals && count(totals.total_quantity)} loading={loading} />
        <Kpi label="Orders" value={totals && count(totals.order_count)} loading={loading} />
        <Kpi
          label="Avg Discount"
          value={totals && percent(Number(totals.avg_discount) * 100)}
          loading={loading}
        />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <ChartCard title="Sales by Customer Segment">
          <DonutChart
            queryKey="sales_by_segment"
            parameters={parameters}
            xKey="segment"
            yKey="total_sales"
            valueFormatter={currency}
            showLegend
          />
        </ChartCard>

        <ChartCard title="Sales by Ship Mode">
          <BarChart
            queryKey="sales_by_ship_mode"
            parameters={parameters}
            xKey="ship_mode"
            yKey="total_sales"
            valueFormatter={currency}
          />
        </ChartCard>

        <ChartCard title="Sales by Payment Method">
          <BarChart
            queryKey="sales_by_payment"
            parameters={parameters}
            xKey="payment_type"
            yKey="total_sales"
            valueFormatter={currency}
          />
        </ChartCard>

        <ChartCard title="Orders by Ship Mode">
          <BarChart
            queryKey="sales_by_ship_mode"
            parameters={parameters}
            xKey="ship_mode"
            yKey="order_count"
            valueFormatter={count}
          />
        </ChartCard>

        <ChartCard title="Top 10 Brands by Sales" wide>
          <BarChart
            queryKey="sales_by_brand"
            parameters={parameters}
            xKey="brand"
            yKey={['total_sales']}
            valueFormatter={currency}
          />
        </ChartCard>
      </div>
    </div>
  );
}
