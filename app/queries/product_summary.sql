-- @param target_year INT64
-- @param period STRING FY|Q1|Q2|Q3|Q4|YTD
-- @param region STRING
-- @param segment STRING
-- @param vendor STRING
-- @param ship_mode STRING
-- @param payment_type STRING
-- @param brand STRING
-- Catalogue KPIs for the period: products sold, average unit price, with year-over-year changes.
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
cur AS (
  SELECT COUNT(DISTINCT product_id) AS products_sold, SUM(quantity) AS units, SUM(sales) AS revenue,
         COUNT(DISTINCT IF(p.comparable, product_id, NULL)) AS products_c,
         SUM(IF(p.comparable, sales, 0)) AS revenue_c, SUM(IF(p.comparable, quantity, 0)) AS units_c
  FROM f JOIN p ON f.month = p.month WHERE f.year = @target_year
),
pri AS (
  SELECT COUNT(DISTINCT product_id) AS products_sold, SUM(quantity) AS units, SUM(sales) AS revenue
  FROM f JOIN p ON f.month = p.month AND p.comparable WHERE f.year = @target_year - 1
),
ret AS (
  SELECT SUM(IF(r.year = @target_year, r.allocated_refund, 0)) AS refunded,
         SUM(IF(r.year = @target_year AND p.comparable, r.allocated_refund, 0)) AS refunded_c,
         SUM(IF(r.year = @target_year - 1 AND p.comparable, r.allocated_refund, 0)) AS refunded_prior
  FROM gold.rpt_return_product_lines AS r JOIN p ON r.month = p.month
  WHERE r.year IN (@target_year, @target_year - 1)
    AND (@region = 'All' OR r.region = @region) AND (@segment = 'All' OR r.segment = @segment)
    AND (@vendor = 'All' OR r.vendor_name = @vendor) AND (@ship_mode = 'All' OR r.ship_mode = @ship_mode)
    AND (@payment_type = 'All' OR r.payment_type = @payment_type) AND (@brand = 'All' OR r.brand = @brand)
),
months AS (
  SELECT COUNTIF(has_data) AS months_with_data, COUNTIF(comparable) AS months_compared,
         STRING_AGG(IF(comparable, FORMAT_DATE('%b', DATE(2000, month, 1)), NULL), ', ' ORDER BY month) AS compared_months
  FROM p
)
SELECT
  @target_year - 1 AS prior_year, m.months_with_data, m.months_compared, m.compared_months,
  cur.products_sold, pri.products_sold AS products_sold_prior, ROUND(100 * SAFE_DIVIDE(cur.products_c - pri.products_sold, pri.products_sold), 1) AS products_sold_yoy,
  cur.units, pri.units AS units_prior, ROUND(100 * SAFE_DIVIDE(cur.units_c - pri.units, pri.units), 1) AS units_yoy,
  ROUND(SAFE_DIVIDE(cur.revenue, cur.units), 2) AS avg_unit_price,
  ROUND(SAFE_DIVIDE(pri.revenue, pri.units), 2) AS avg_unit_price_prior,
  ROUND(100 * SAFE_DIVIDE(SAFE_DIVIDE(cur.revenue_c, cur.units_c) - SAFE_DIVIDE(pri.revenue, pri.units), SAFE_DIVIDE(pri.revenue, pri.units)), 1) AS avg_unit_price_yoy,
  ROUND(ret.refunded, 2) AS refunded, ROUND(ret.refunded_prior, 2) AS refunded_prior, ROUND(100 * SAFE_DIVIDE(ret.refunded_c - ret.refunded_prior, ret.refunded_prior), 1) AS refunded_yoy
FROM cur, pri, ret, months AS m
