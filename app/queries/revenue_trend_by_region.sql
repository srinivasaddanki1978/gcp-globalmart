-- Yearly revenue per region, one column per region for a multi-series chart.
-- Source: gold.mv_revenue_by_region
SELECT
  CAST(year AS STRING)                                         AS year,
  SUM(CASE WHEN region = 'East'    THEN total_sales ELSE 0 END) AS east,
  SUM(CASE WHEN region = 'West'    THEN total_sales ELSE 0 END) AS west,
  SUM(CASE WHEN region = 'South'   THEN total_sales ELSE 0 END) AS south,
  SUM(CASE WHEN region = 'Central' THEN total_sales ELSE 0 END) AS central,
  SUM(CASE WHEN region = 'North'   THEN total_sales ELSE 0 END) AS north
FROM gold.mv_revenue_by_region
GROUP BY year
ORDER BY year
