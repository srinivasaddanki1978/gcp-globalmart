-- @param target_year INT64
-- Headline sales KPIs for a single year.
-- Source: gold.fact_sales
SELECT
  SUM(sales)              AS total_sales,
  SUM(quantity)           AS total_quantity,
  COUNT(DISTINCT order_id) AS order_count,
  AVG(discount)           AS avg_discount
FROM gold.fact_sales
WHERE EXTRACT(YEAR FROM order_date_key) = @target_year
