-- @param target_year INT64
-- @param period STRING FY|Q1|Q2|Q3|Q4|YTD
-- @param region STRING
-- @param segment STRING
-- @param vendor STRING
-- @param ship_mode STRING
-- @param payment_type STRING
-- @param brand STRING
-- Vendor return rate for orders placed in the period (orders with a return / orders),
-- current vs the same months of the prior year (change in percentage points).
-- YoY % compares only months with data in both years (gold.rpt_period_months).
WITH p AS (  -- months of the selected period; `comparable` = data in this and the prior year (like-for-like)
  SELECT month, has_data, comparable FROM gold.rpt_period_months
  WHERE year = @target_year AND period = @period AND in_period
),
f AS (
  SELECT * FROM gold.rpt_sales_lines
  WHERE (@region = 'All' OR region = @region) AND (@segment = 'All' OR segment = @segment)
    AND (@vendor = 'All' OR vendor_name = @vendor) AND (@ship_mode = 'All' OR ship_mode = @ship_mode)
    AND (@payment_type = 'All' OR payment_type = @payment_type) AND (@brand = 'All' OR brand = @brand)
),
orders AS (  -- one row per order (an order has one vendor)
  SELECT f.year, f.vendor_name, f.order_id, LOGICAL_OR(f.order_has_return) AS returned, SUM(f.sales) AS revenue,
         LOGICAL_OR(p.comparable) AS comparable
  FROM f JOIN p ON f.month = p.month
  WHERE f.year IN (@target_year, @target_year - 1)
  GROUP BY 1, 2, 3
),
cur AS (
  SELECT vendor_name, COUNT(*) AS orders, COUNTIF(returned) AS returned_orders, SUM(revenue) AS revenue,
         SAFE_DIVIDE(COUNTIF(returned AND comparable), COUNTIF(comparable)) AS rate_c
  FROM orders WHERE year = @target_year GROUP BY 1
),
pri AS (
  SELECT vendor_name, SAFE_DIVIDE(COUNTIF(returned), COUNT(*)) AS rate_prior
  FROM orders WHERE year = @target_year - 1 AND comparable GROUP BY 1
)
SELECT
  cur.vendor_name, cur.orders, cur.returned_orders, ROUND(cur.revenue, 2) AS revenue,
  ROUND(100 * SAFE_DIVIDE(cur.returned_orders, cur.orders), 2) AS return_rate_pct,
  ROUND(100 * pri.rate_prior, 2) AS return_rate_pct_prior,
  ROUND(100 * (cur.rate_c - pri.rate_prior), 2) AS change_pts
FROM cur LEFT JOIN pri USING (vendor_name)
ORDER BY return_rate_pct DESC
