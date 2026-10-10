-- @param target_year INT64
-- Customer count, sales, and basket size per segment.
-- Source: gold.fact_sales x dim_customers
SELECT
  c.segment,
  COUNT(DISTINCT c.customer_id)            AS customers,
  SUM(f.sales)                             AS total_sales,
  SUM(f.sales) / COUNT(DISTINCT f.order_id) AS avg_order_value
FROM gold.fact_sales f
JOIN gold.dim_customers c ON f.customer_sk = c.customer_sk
WHERE EXTRACT(YEAR FROM f.order_date_key) = @target_year
GROUP BY c.segment
ORDER BY total_sales DESC
