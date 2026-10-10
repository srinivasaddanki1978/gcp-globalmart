-- @param target_year INT64
-- Customer-base headline figures for a single year.
-- Source: gold.fact_sales x dim_customers
SELECT
  COUNT(DISTINCT c.customer_id)            AS customers,
  SUM(f.sales)                             AS total_sales,
  COUNT(DISTINCT f.order_id)               AS orders,
  SUM(f.sales) / COUNT(DISTINCT f.order_id) AS avg_order_value
FROM gold.fact_sales f
JOIN gold.dim_customers c ON f.customer_sk = c.customer_sk
WHERE EXTRACT(YEAR FROM f.order_date_key) = @target_year
