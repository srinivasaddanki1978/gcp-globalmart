-- @param min_quantity INT64
-- Slow-moving inventory rolled up by region.
-- Source: gold.mv_slow_moving_products
SELECT
  region,
  COUNT(*)              AS product_count,
  SUM(total_sales)      AS total_sales,
  SUM(total_quantity)   AS total_quantity,
  SUM(total_profit)     AS total_profit
FROM gold.mv_slow_moving_products
WHERE is_slow_moving = true
  AND total_quantity >= @min_quantity
GROUP BY region
ORDER BY product_count DESC
