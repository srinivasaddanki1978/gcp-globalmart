-- @param min_quantity INT64
-- @param region STRING
-- @param brand STRING
-- Top brands by count of slow-moving product-regions (all history).
SELECT
  brand,
  COUNT(*) AS product_count,
  ROUND(SUM(total_sales), 2) AS total_sales,
  SUM(total_quantity) AS total_quantity,
  ROUND(SUM(total_profit), 2) AS total_profit
FROM gold.mv_slow_moving_products
WHERE is_slow_moving
  AND total_quantity >= @min_quantity
  AND (@region = 'All' OR region = @region)
  AND (@brand = 'All' OR brand = @brand)
GROUP BY brand
ORDER BY product_count DESC
LIMIT 10
