-- @param target_year INT64
-- @param period STRING FY|Q1|Q2|Q3|Q4|YTD
-- @param region STRING
-- @param segment STRING
-- @param vendor STRING
-- @param return_reason STRING
-- @param return_status STRING
-- Returns by reason (customer-level, by return date): refunds and counts, current vs prior period.
-- YoY % compares only months with data in both years (gold.rpt_period_months), and is NULL
-- when fewer than half the period's months can be compared.
WITH p AS (  -- months of the selected period; `comparable` = data in this and the prior year (like-for-like)
  SELECT month, has_data, comparable FROM gold.rpt_period_months
  WHERE year = @target_year AND period = @period AND in_period
),
f AS (
  SELECT * FROM gold.rpt_return_lines
  WHERE (@region = 'All' OR region = @region) AND (@segment = 'All' OR segment = @segment)
    AND (@vendor = 'All' OR vendor_name = @vendor) AND (@return_reason = 'All' OR return_reason = @return_reason)
    AND (@return_status = 'All' OR return_status = @return_status)
),
cur AS (
  SELECT f.return_reason AS return_reason, SUM(f.refund_amount) AS refunded, SUM(IF(p.comparable, f.refund_amount, 0)) AS refunded_cmp, COUNT(*) AS returns
  FROM f JOIN p ON f.month = p.month
  WHERE f.year = @target_year
  GROUP BY 1
),
pri AS (
  SELECT f.return_reason AS return_reason, SUM(f.refund_amount) AS refunded_prior
  FROM f JOIN p ON f.month = p.month AND p.comparable
  WHERE f.year = @target_year - 1
  GROUP BY 1
)
SELECT
  cur.return_reason,
  ROUND(cur.refunded, 2) AS refunded,
  ROUND(pri.refunded_prior, 2) AS refunded_prior,
  IF((SELECT COUNTIF(comparable) * 2 >= COUNTIF(has_data) FROM p), ROUND(100 * SAFE_DIVIDE(cur.refunded_cmp - pri.refunded_prior, pri.refunded_prior), 1), NULL) AS yoy_pct,
  cur.returns
FROM cur
LEFT JOIN pri USING (return_reason)
ORDER BY refunded DESC
