-- @param min_quantity INT64
-- Top brands by count of slow-moving products.
-- Source: gold.mv_slow_moving_products
SELECT
  brand,
  COUNT(*)         AS product_count,
  SUM(total_sales) AS total_sales
FROM gold.mv_slow_moving_products
WHERE is_slow_moving = true
  AND total_quantity >= @min_quantity
GROUP BY brand
ORDER BY product_count DESC
LIMIT 10
