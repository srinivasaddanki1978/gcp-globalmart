-- @param target_year INT64
-- Active customers and sales per region.
-- Source: gold.fact_sales x dim_customers
SELECT
  c.region,
  COUNT(DISTINCT c.customer_id) AS customers,
  SUM(f.sales)                  AS total_sales
FROM gold.fact_sales f
JOIN gold.dim_customers c ON f.customer_sk = c.customer_sk
WHERE EXTRACT(YEAR FROM f.order_date_key) = @target_year
GROUP BY c.region
ORDER BY total_sales DESC
