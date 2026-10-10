-- Yearly revenue, profit and orders across all regions, Oct 2016 - Sep 2026.
-- Source: gold.mv_revenue_by_region
SELECT
  CAST(year AS STRING)  AS year,
  SUM(total_sales)      AS total_sales,
  SUM(total_profit)     AS total_profit,
  SUM(order_count)      AS order_count
FROM gold.mv_revenue_by_region
GROUP BY year
ORDER BY year
