-- @param target_year INT64
-- Monthly sales/profit trend for a single year, summed over all regions.
-- Source: gold.mv_revenue_by_region
SELECT
  month_name,
  SUM(total_sales)  AS total_sales,
  SUM(total_profit) AS total_profit,
  SUM(order_count)  AS order_count
FROM gold.mv_revenue_by_region
WHERE year = @target_year
GROUP BY month_name, month
ORDER BY month
