-- @param target_year INT64
-- @param period STRING FY|Q1|Q2|Q3|Q4|YTD
-- @param region STRING
-- @param segment STRING
-- @param vendor STRING
-- @param ship_mode STRING
-- @param payment_type STRING
-- @param brand STRING
-- Active customers, revenue and basket size by segment, current vs prior period.
-- YoY % compares only months with data in both years (gold.rpt_period_months), and is NULL
-- when fewer than half the period's months can be compared.
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
  SELECT f.segment AS segment, COUNT(DISTINCT f.customer_id) AS customers, SUM(f.sales) AS revenue,
         COUNT(DISTINCT f.order_id) AS orders, COUNT(DISTINCT IF(p.comparable, f.customer_id, NULL)) AS customers_c
  FROM f JOIN p ON f.month = p.month WHERE f.year = @target_year GROUP BY 1
),
pri AS (
  SELECT f.segment AS segment, COUNT(DISTINCT f.customer_id) AS customers_prior
  FROM f JOIN p ON f.month = p.month AND p.comparable WHERE f.year = @target_year - 1 GROUP BY 1
)
SELECT
  cur.segment, cur.customers, pri.customers_prior, ROUND(100 * SAFE_DIVIDE(cur.customers_c - pri.customers_prior, pri.customers_prior), 1) AS yoy_pct,
  ROUND(cur.revenue, 2) AS revenue, ROUND(SAFE_DIVIDE(cur.revenue, cur.orders), 2) AS avg_order_value
FROM cur LEFT JOIN pri USING (segment)
ORDER BY revenue DESC
