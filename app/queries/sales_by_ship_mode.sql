-- @param target_year INT64
-- Orders and sales by shipping class.
-- Source: gold.fact_sales
SELECT
  ship_mode,
  COUNT(DISTINCT order_id) AS order_count,
  SUM(sales)               AS total_sales
FROM gold.fact_sales
WHERE EXTRACT(YEAR FROM order_date_key) = @target_year
GROUP BY ship_mode
ORDER BY total_sales DESC
