-- @param target_year INT64
-- Per-region totals for a single year, ranked by sales.
-- Source: gold.mv_revenue_by_region
SELECT
  region,
  SUM(total_sales)      AS total_sales,
  SUM(total_profit)     AS total_profit,
  SUM(unique_customers) AS unique_customers
FROM gold.mv_revenue_by_region
WHERE year = @target_year
GROUP BY region
ORDER BY total_sales DESC
