-- @param target_year INT64
-- Top 10 customers by spend. Email is deliberately not selected.
-- Grouped by customer_id; the label carries the ID to keep the bars distinct.
-- Source: gold.fact_sales x dim_customers
SELECT
  concat(c.customer_name, ' · ', c.customer_id) AS customer_name,
  c.segment,
  SUM(f.sales)               AS total_sales,
  COUNT(DISTINCT f.order_id) AS orders
FROM gold.fact_sales f
JOIN gold.dim_customers c ON f.customer_sk = c.customer_sk
WHERE EXTRACT(YEAR FROM f.order_date_key) = @target_year
GROUP BY c.customer_id, c.customer_name, c.segment
ORDER BY total_sales DESC
LIMIT 10
