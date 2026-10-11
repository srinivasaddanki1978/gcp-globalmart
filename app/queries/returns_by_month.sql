-- @param target_year INT64
-- @param period STRING FY|Q1|Q2|Q3|Q4|YTD
-- @param region STRING
-- @param segment STRING
-- @param vendor STRING
-- @param return_reason STRING
-- @param return_status STRING
-- Monthly refunds and return counts (by return date) next to the same months of the prior year.
WITH p AS (  -- months of the selected period; `comparable` = data in this and the prior year (like-for-like)
  SELECT month, has_data, comparable FROM gold.rpt_period_months
  WHERE year = @target_year AND period = @period AND in_period
),
f AS (
  SELECT * FROM gold.rpt_return_lines
  WHERE ((@region = 'All' OR region = @region) AND (@segment = 'All' OR segment = @segment)
    AND (@vendor = 'All' OR vendor_name = @vendor) AND (@return_reason = 'All' OR return_reason = @return_reason)
    AND (@return_status = 'All' OR return_status = @return_status))
    AND year IN (@target_year, @target_year - 1)
)
SELECT
  p.month,
  FORMAT_DATE('%b', DATE(2000, p.month, 1)) AS month_name,
  ROUND(NULLIF(SUM(IF(f.year = @target_year, f.refund_amount, 0)), 0), 2) AS refunded,
  ROUND(NULLIF(SUM(IF(f.year = @target_year - 1, f.refund_amount, 0)), 0), 2) AS refunded_prior,
  NULLIF(COUNTIF(f.year = @target_year), 0) AS returns,
  NULLIF(COUNTIF(f.year = @target_year - 1), 0) AS returns_prior
FROM p
LEFT JOIN f ON f.month = p.month
GROUP BY p.month
ORDER BY p.month
