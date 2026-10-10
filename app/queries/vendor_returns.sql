-- @param min_orders INT64
-- Return rate per vendor, ranked worst-first.
-- Source: gold.mv_return_rate_by_vendor
SELECT
  vendor_name,
  total_orders,
  total_sales,
  return_order_count,
  total_refunded,
  return_rate_pct
FROM gold.mv_return_rate_by_vendor
WHERE total_orders >= @min_orders
ORDER BY return_rate_pct DESC
