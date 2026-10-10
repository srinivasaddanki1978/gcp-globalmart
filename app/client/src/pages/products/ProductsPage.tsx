import { useAnalyticsQuery, BarChart, DonutChart, Label, Select, SelectContent, SelectItem, SelectTrigger, SelectValue, sql } from '../../lib/appkit';
import { useState } from 'react';

import { ChartCard, DashboardHeader, Kpi, count, currency } from '../shared/dashboard-ui';
import { YEARS, DEFAULT_YEAR } from '../shared/years';


export function ProductsPage() {
  const [year, setYear] = useState<number>(DEFAULT_YEAR);
  const parameters = { target_year: sql.number(year) };

  const { data: summary, loading, error } = useAnalyticsQuery('product_summary', parameters);
  const { data: returns } = useAnalyticsQuery('returns_by_reason', parameters);
  const totals = summary?.[0];
  const refunded = returns?.reduce((sum, r) => sum + Number(r.refunded), 0);

  return (
    <div className="space-y-6 w-full max-w-7xl mx-auto">
      <DashboardHeader
        title="Products"
        source="gold.dim_products + fact_sales + bridge_return_products"
      >
        <div className="space-y-2 w-48">
          <Label htmlFor="product-year">Year</Label>
          <Select value={year.toString()} onValueChange={(value) => setYear(parseInt(value))}>
            <SelectTrigger id="product-year">
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
        <Kpi label="Products Sold" value={totals && count(totals.products_sold)} loading={loading} />
        <Kpi label="Units Sold" value={totals && count(totals.total_units)} loading={loading} />
        <Kpi
          label="Avg Unit Price"
          value={totals && currency(totals.avg_unit_price)}
          loading={loading}
        />
        <Kpi
          label="Refunded"
          value={refunded !== undefined ? currency(refunded) : undefined}
          loading={loading}
        />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <ChartCard title="Returns by Reason">
          <DonutChart
            queryKey="returns_by_reason"
            parameters={parameters}
            xKey="return_reason"
            yKey="refunded"
            valueFormatter={currency}
            showLegend
          />
        </ChartCard>

        <ChartCard title="Products per Brand">
          <BarChart
            queryKey="products_by_brand"
            parameters={parameters}
            xKey="brand"
            yKey="products"
            valueFormatter={count}
          />
        </ChartCard>

        <ChartCard title="Top 10 Products by Sales" wide>
          <BarChart
            queryKey="top_products"
            parameters={parameters}
            xKey="product_name"
            yKey="total_sales"
            valueFormatter={currency}
          />
        </ChartCard>

        <ChartCard title="Units Sold by Brand" wide>
          <BarChart
            queryKey="products_by_brand"
            parameters={parameters}
            xKey="brand"
            yKey="total_quantity"
            valueFormatter={count}
          />
        </ChartCard>

        <ChartCard title="Top 10 Products by Refund Value" wide>
          <BarChart
            queryKey="top_returned_products"
            parameters={parameters}
            xKey="product_name"
            yKey="refunded"
            valueFormatter={currency}
          />
        </ChartCard>
      </div>
    </div>
  );
}
