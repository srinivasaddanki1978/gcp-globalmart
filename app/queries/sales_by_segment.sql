-- @param target_year INT64
-- Sales split by customer segment.
-- Source: gold.fact_sales x dim_customers
SELECT
  c.segment,
  SUM(f.sales)                AS total_sales,
  COUNT(DISTINCT f.customer_id) AS customers
FROM gold.fact_sales f
JOIN gold.dim_customers c ON f.customer_sk = c.customer_sk
WHERE EXTRACT(YEAR FROM f.order_date_key) = @target_year
GROUP BY c.segment
ORDER BY total_sales DESC
