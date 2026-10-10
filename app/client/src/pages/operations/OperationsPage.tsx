import { useAnalyticsQuery, BarChart, DonutChart, sql } from '../../lib/appkit';

import { ChartCard, DashboardHeader, Kpi, count, currency, percent } from '../shared/dashboard-ui';

/** Vendors below this order count are too small to judge on return rate. */
const MIN_ORDERS = 100;
/** Slow movers that never shipped a unit aren't actionable. */
const MIN_QUANTITY = 1;

export function OperationsPage() {
  const vendorParams = { min_orders: sql.number(MIN_ORDERS) };
  const slowParams = { min_quantity: sql.number(MIN_QUANTITY) };

  const { data: vendors, loading: vendorsLoading, error: vendorsError } = useAnalyticsQuery(
    'vendor_returns',
    vendorParams,
  );
  const { data: regions, loading: regionsLoading, error: regionsError } = useAnalyticsQuery(
    'slow_moving_by_region',
    slowParams,
  );

  const worstVendor = vendors?.[0];
  const totalRefunded = vendors?.reduce((sum, v) => sum + Number(v.total_refunded), 0);
  const slowCount = regions?.reduce((sum, r) => sum + Number(r.product_count), 0);
  const slowValue = regions?.reduce((sum, r) => sum + Number(r.total_sales), 0);

  const error = vendorsError || regionsError;
  const loading = vendorsLoading || regionsLoading;

  return (
    <div className="space-y-6 w-full max-w-7xl mx-auto">
      <DashboardHeader
        title="Operations"
        source="gold.mv_return_rate_by_vendor + mv_slow_moving_products"
      />

      {error && (
        <div className="text-destructive bg-destructive/10 p-3 rounded-md">Error: {error}</div>
      )}

      <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
        <Kpi
          label="Worst Return Rate"
          value={worstVendor && percent(worstVendor.return_rate_pct)}
          loading={loading}
        />
        <Kpi
          label="Total Refunded"
          value={totalRefunded !== undefined ? currency(totalRefunded) : undefined}
          loading={loading}
        />
        <Kpi
          label="Slow-Moving Products"
          value={slowCount !== undefined ? count(slowCount) : undefined}
          loading={loading}
        />
        <Kpi
          label="Value Tied Up"
          value={slowValue !== undefined ? currency(slowValue) : undefined}
          loading={loading}
        />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <ChartCard title="Return Rate by Vendor">
          <BarChart
            queryKey="vendor_returns"
            parameters={vendorParams}
            xKey="vendor_name"
            yKey="return_rate_pct"
            valueFormatter={percent}
          />
        </ChartCard>

        <ChartCard title="Sales vs Refunded by Vendor">
          <BarChart
            queryKey="vendor_returns"
            parameters={vendorParams}
            xKey="vendor_name"
            yKey={['total_sales', 'total_refunded']}
            valueFormatter={currency}
            showLegend
          />
        </ChartCard>

        <ChartCard title="Slow-Moving Products by Region">
          <BarChart
            queryKey="slow_moving_by_region"
            parameters={slowParams}
            xKey="region"
            yKey="product_count"
            valueFormatter={count}
          />
        </ChartCard>

        <ChartCard title="Tied-Up Value by Region">
          <DonutChart
            queryKey="slow_moving_by_region"
            parameters={slowParams}
            xKey="region"
            yKey="total_sales"
            valueFormatter={currency}
            showLegend
          />
        </ChartCard>

        <ChartCard title="Top 10 Brands by Slow-Moving Count" wide>
          <BarChart
            queryKey="slow_moving_by_brand"
            parameters={slowParams}
            xKey="brand"
            yKey="product_count"
            valueFormatter={count}
          />
        </ChartCard>
      </div>
    </div>
  );
}
