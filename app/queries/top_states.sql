-- @param target_year INT64
-- Top 10 states by sales.
-- Source: gold.fact_sales x dim_customers
SELECT
  c.state,
  COUNT(DISTINCT c.customer_id) AS customers,
  SUM(f.sales)                  AS total_sales
FROM gold.fact_sales f
JOIN gold.dim_customers c ON f.customer_sk = c.customer_sk
WHERE EXTRACT(YEAR FROM f.order_date_key) = @target_year
GROUP BY c.state
ORDER BY total_sales DESC
LIMIT 10
