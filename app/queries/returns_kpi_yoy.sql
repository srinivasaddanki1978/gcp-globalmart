-- @param target_year INT64
-- @param period STRING FY|Q1|Q2|Q3|Q4|YTD
-- @param region STRING
-- @param segment STRING
-- @param vendor STRING
-- @param return_reason STRING
-- @param return_status STRING
-- Return KPIs for the period (by return date) with year-over-year changes.
-- YoY % compares only months with data in both years (gold.rpt_period_months).
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
  SELECT COUNT(*) AS returns, SUM(refund_amount) AS refunded, COUNTIF(return_status = 'Approved') AS approved,
         COUNTIF(p.comparable) AS returns_c, SUM(IF(p.comparable, refund_amount, 0)) AS refunded_c
  FROM f JOIN p ON f.month = p.month WHERE f.year = @target_year
),
pri AS (
  SELECT COUNT(*) AS returns, SUM(refund_amount) AS refunded, COUNTIF(return_status = 'Approved') AS approved
  FROM f JOIN p ON f.month = p.month AND p.comparable WHERE f.year = @target_year - 1
),
months AS (
  SELECT COUNTIF(has_data) AS months_with_data, COUNTIF(comparable) AS months_compared,
         STRING_AGG(IF(comparable, FORMAT_DATE('%b', DATE(2000, month, 1)), NULL), ', ' ORDER BY month) AS compared_months
  FROM p
)
SELECT
  @target_year - 1 AS prior_year, m.months_with_data, m.months_compared, m.compared_months,
  cur.returns, pri.returns AS returns_prior, ROUND(100 * SAFE_DIVIDE(cur.returns_c - pri.returns, pri.returns), 1) AS returns_yoy,
  ROUND(cur.refunded, 2) AS refunded, ROUND(pri.refunded, 2) AS refunded_prior, ROUND(100 * SAFE_DIVIDE(cur.refunded_c - pri.refunded, pri.refunded), 1) AS refunded_yoy,
  ROUND(100 * SAFE_DIVIDE(cur.approved, cur.returns), 1) AS approval_rate,
  ROUND(100 * SAFE_DIVIDE(pri.approved, pri.returns), 1) AS approval_rate_prior,
  ROUND(SAFE_DIVIDE(cur.refunded, cur.returns), 2) AS avg_refund
FROM cur, pri, months AS m
