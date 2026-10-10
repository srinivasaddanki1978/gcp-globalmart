-- @param target_year INT64
-- Catalogue breadth vs revenue per brand.
-- Source: gold.fact_sales x dim_products
SELECT
  p.brand,
  COUNT(DISTINCT p.product_id) AS products,
  SUM(f.sales)                 AS total_sales,
  SUM(f.quantity)              AS total_quantity
FROM gold.fact_sales f
JOIN gold.dim_products p ON f.product_sk = p.product_sk
WHERE EXTRACT(YEAR FROM f.order_date_key) = @target_year
GROUP BY p.brand
ORDER BY total_sales DESC
LIMIT 10
