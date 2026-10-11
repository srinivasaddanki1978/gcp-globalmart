-- @param target_year INT64
-- @param period STRING FY|Q1|Q2|Q3|Q4|YTD
-- @param region STRING
-- @param segment STRING
-- @param vendor STRING
-- @param ship_mode STRING
-- @param payment_type STRING
-- @param brand STRING
-- Monthly revenue, profit and orders for the period next to the same months of the prior year.
-- Months with no data in a year are NULL (gaps in the chart, not zeros).
WITH p AS (  -- months of the selected period; `comparable` = data in this and the prior year (like-for-like)
  SELECT month, has_data, comparable FROM gold.rpt_period_months
  WHERE year = @target_year AND period = @period AND in_period
),
f AS (
  SELECT * FROM gold.rpt_sales_lines
  WHERE ((@region = 'All' OR region = @region) AND (@segment = 'All' OR segment = @segment)
    AND (@vendor = 'All' OR vendor_name = @vendor) AND (@ship_mode = 'All' OR ship_mode = @ship_mode)
    AND (@payment_type = 'All' OR payment_type = @payment_type) AND (@brand = 'All' OR brand = @brand))
    AND year IN (@target_year, @target_year - 1)
)
SELECT
  p.month,
  FORMAT_DATE('%b', DATE(2000, p.month, 1)) AS month_name,
  ROUND(NULLIF(SUM(IF(f.year = @target_year, f.sales, 0)), 0), 2) AS revenue,
  ROUND(NULLIF(SUM(IF(f.year = @target_year - 1, f.sales, 0)), 0), 2) AS revenue_prior,
  ROUND(NULLIF(SUM(IF(f.year = @target_year, f.profit, 0)), 0), 2) AS profit,
  NULLIF(COUNT(DISTINCT IF(f.year = @target_year, f.order_id, NULL)), 0) AS orders,
  NULLIF(COUNT(DISTINCT IF(f.year = @target_year - 1, f.order_id, NULL)), 0) AS orders_prior
FROM p
LEFT JOIN f ON f.month = p.month
GROUP BY p.month
ORDER BY p.month
