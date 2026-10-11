-- @param target_year INT64
-- @param period STRING FY|Q1|Q2|Q3|Q4|YTD
-- @param region STRING
-- @param segment STRING
-- @param vendor STRING
-- @param ship_mode STRING
-- @param payment_type STRING
-- @param brand STRING
-- Headline sales KPIs for the period with year-over-year changes.
-- YoY % compares only months with data in both years (gold.rpt_period_months).
-- months_compared < months_with_data means the prior year only partly overlaps (shown in the app).
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
cur AS (
  SELECT SUM(sales) AS revenue, SUM(profit) AS profit, COUNT(DISTINCT order_id) AS orders, SUM(quantity) AS units,
         COUNT(DISTINCT customer_id) AS customers,
         SUM(IF(p.comparable, sales, 0)) AS revenue_c, SUM(IF(p.comparable, profit, 0)) AS profit_c,
         COUNT(DISTINCT IF(p.comparable, order_id, NULL)) AS orders_c, SUM(IF(p.comparable, quantity, 0)) AS units_c,
         COUNT(DISTINCT IF(p.comparable, customer_id, NULL)) AS customers_c
  FROM f JOIN p ON f.month = p.month WHERE f.year = @target_year
),
pri AS (
  SELECT SUM(sales) AS revenue, SUM(profit) AS profit, COUNT(DISTINCT order_id) AS orders, SUM(quantity) AS units,
         COUNT(DISTINCT customer_id) AS customers
  FROM f JOIN p ON f.month = p.month AND p.comparable WHERE f.year = @target_year - 1
),
months AS (
  SELECT COUNTIF(has_data) AS months_with_data, COUNTIF(comparable) AS months_compared,
         STRING_AGG(IF(comparable, FORMAT_DATE('%b', DATE(2000, month, 1)), NULL), ', ' ORDER BY month) AS compared_months
  FROM p
)
SELECT
  @target_year - 1 AS prior_year, m.months_with_data, m.months_compared, m.compared_months,
  ROUND(cur.revenue, 2) AS revenue, ROUND(pri.revenue, 2) AS revenue_prior, ROUND(100 * SAFE_DIVIDE(cur.revenue_c - pri.revenue, pri.revenue), 1) AS revenue_yoy,
  ROUND(cur.profit, 2) AS profit, ROUND(pri.profit, 2) AS profit_prior, ROUND(100 * SAFE_DIVIDE(cur.profit_c - pri.profit, pri.profit), 1) AS profit_yoy,
  cur.orders, pri.orders AS orders_prior, ROUND(100 * SAFE_DIVIDE(cur.orders_c - pri.orders, pri.orders), 1) AS orders_yoy,
  cur.units, pri.units AS units_prior, ROUND(100 * SAFE_DIVIDE(cur.units_c - pri.units, pri.units), 1) AS units_yoy,
  cur.customers, pri.customers AS customers_prior, ROUND(100 * SAFE_DIVIDE(cur.customers_c - pri.customers, pri.customers), 1) AS customers_yoy,
  ROUND(100 * SAFE_DIVIDE(cur.profit, cur.revenue), 2) AS margin_pct,
  ROUND(100 * SAFE_DIVIDE(pri.profit, pri.revenue), 2) AS margin_pct_prior,
  ROUND(100 * (SAFE_DIVIDE(cur.profit_c, cur.revenue_c) - SAFE_DIVIDE(pri.profit, pri.revenue)), 2) AS margin_change_pts,
  ROUND(SAFE_DIVIDE(cur.revenue, cur.orders), 2) AS aov,
  ROUND(SAFE_DIVIDE(pri.revenue, pri.orders), 2) AS aov_prior,
  ROUND(100 * SAFE_DIVIDE(SAFE_DIVIDE(cur.revenue_c, cur.orders_c) - SAFE_DIVIDE(pri.revenue, pri.orders), SAFE_DIVIDE(pri.revenue, pri.orders)), 1) AS aov_yoy
FROM cur, pri, months AS m
