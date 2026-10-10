-- @param target_year INT64
-- Headline KPIs for a single year, across all regions.
-- Source: gold.mv_revenue_by_region
SELECT
  SUM(total_sales)      AS total_sales,
  SUM(total_profit)     AS total_profit,
  SUM(order_count)      AS order_count,
  SUM(unique_customers) AS unique_customers
FROM gold.mv_revenue_by_region
WHERE year = @target_year
