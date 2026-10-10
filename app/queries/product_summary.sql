-- @param target_year INT64
-- Product-catalogue headline figures for a single year.
-- Source: gold.fact_sales
SELECT
  COUNT(DISTINCT product_id)   AS products_sold,
  SUM(quantity)                AS total_units,
  SUM(sales)                   AS total_sales,
  SUM(sales) / SUM(quantity)   AS avg_unit_price
FROM gold.fact_sales
WHERE EXTRACT(YEAR FROM order_date_key) = @target_year
