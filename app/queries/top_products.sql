-- @param target_year INT64
-- Top 10 products by sales. Names are truncated to 38 chars so they fit a
-- chart axis — the source names run well over 60 characters.
-- Source: gold.fact_sales x dim_products
SELECT
  SUBSTRING(p.product_name, 1, 38) AS product_name,
  SUM(f.sales)                     AS total_sales,
  SUM(f.quantity)                  AS total_quantity
FROM gold.fact_sales f
JOIN gold.dim_products p ON f.product_sk = p.product_sk
WHERE EXTRACT(YEAR FROM f.order_date_key) = @target_year
GROUP BY SUBSTRING(p.product_name, 1, 38)
ORDER BY total_sales DESC
LIMIT 10
