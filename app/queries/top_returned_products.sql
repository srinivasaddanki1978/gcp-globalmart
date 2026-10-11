-- @param target_year INT64
-- @param period STRING FY|Q1|Q2|Q3|Q4|YTD
-- @param region STRING
-- @param segment STRING
-- @param vendor STRING
-- @param ship_mode STRING
-- @param payment_type STRING
-- @param brand STRING
-- Top 10 products by allocated refunds, by return date, current vs prior period.
-- YoY % compares only months with data in both years (gold.rpt_period_months), and is NULL
-- when fewer than half the period's months can be compared.
WITH p AS (  -- months of the selected period; `comparable` = data in this and the prior year (like-for-like)
  SELECT month, has_data, comparable FROM gold.rpt_period_months
  WHERE year = @target_year AND period = @period AND in_period
),
f AS (
  SELECT * FROM gold.rpt_return_product_lines
  WHERE (@region = 'All' OR region = @region) AND (@segment = 'All' OR segment = @segment)
    AND (@vendor = 'All' OR vendor_name = @vendor) AND (@ship_mode = 'All' OR ship_mode = @ship_mode)
    AND (@payment_type = 'All' OR payment_type = @payment_type) AND (@brand = 'All' OR brand = @brand)
),
cur AS (
  SELECT SUBSTR(f.product_name, 1, 38) AS product_name, SUM(f.allocated_refund) AS refunded, SUM(IF(p.comparable, f.allocated_refund, 0)) AS refunded_cmp, COUNT(*) AS return_lines
  FROM f JOIN p ON f.month = p.month
  WHERE f.year = @target_year
  GROUP BY 1
),
pri AS (
  SELECT SUBSTR(f.product_name, 1, 38) AS product_name, SUM(f.allocated_refund) AS refunded_prior
  FROM f JOIN p ON f.month = p.month AND p.comparable
  WHERE f.year = @target_year - 1
  GROUP BY 1
)
SELECT
  cur.product_name,
  ROUND(cur.refunded, 2) AS refunded,
  ROUND(pri.refunded_prior, 2) AS refunded_prior,
  IF((SELECT COUNTIF(comparable) * 2 >= COUNTIF(has_data) FROM p), ROUND(100 * SAFE_DIVIDE(cur.refunded_cmp - pri.refunded_prior, pri.refunded_prior), 1), NULL) AS yoy_pct,
  cur.return_lines
FROM cur
LEFT JOIN pri USING (product_name)
ORDER BY refunded DESC
LIMIT 10
