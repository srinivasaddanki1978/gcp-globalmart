-- @param min_anomaly INT64
-- Return-abuse candidates per region. This table has no year column, so it
-- spans all history and is not affected by the dashboard's year selector.
-- Source: gold.flagged_return_customers
SELECT
  region,
  COUNT(*)                 AS flagged_customers,
  SUM(total_refund_value)  AS total_refund_value,
  AVG(anomaly_score)       AS avg_anomaly_score
FROM gold.flagged_return_customers
WHERE anomaly_score >= @min_anomaly
GROUP BY region
ORDER BY flagged_customers DESC
