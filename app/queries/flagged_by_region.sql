-- @param min_anomaly INT64
-- @param region STRING
-- @param segment STRING
-- Return-abuse candidates per region. Scores cover each customer's last 12 months of
-- returns, so the year and period filters don't apply.
SELECT
  region,
  COUNT(*) AS flagged_customers,
  ROUND(SUM(total_refund_value), 2) AS total_refund_value,
  ROUND(AVG(anomaly_score), 1) AS avg_anomaly_score
FROM gold.flagged_return_customers
WHERE anomaly_score >= @min_anomaly
  AND (@region = 'All' OR region = @region)
  AND (@segment = 'All' OR segment = @segment)
GROUP BY region
ORDER BY flagged_customers DESC
