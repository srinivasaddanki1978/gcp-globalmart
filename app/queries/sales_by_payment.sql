-- @param target_year INT64
-- Sales by payment method. Source data carries '?' and NULL for unknown
-- methods; both are folded into a single 'unknown' bucket.
-- Source: gold.fact_sales
SELECT
  COALESCE(NULLIF(payment_type, '?'), 'unknown') AS payment_type,
  COUNT(DISTINCT order_id)                       AS order_count,
  SUM(sales)                                     AS total_sales
FROM gold.fact_sales
WHERE EXTRACT(YEAR FROM order_date_key) = @target_year
GROUP BY COALESCE(NULLIF(payment_type, '?'), 'unknown')
ORDER BY total_sales DESC
