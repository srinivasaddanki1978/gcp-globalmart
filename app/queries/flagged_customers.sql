-- @param min_anomaly INT64
-- @param region STRING
-- @param segment STRING
-- Highest-scoring return-abuse candidates with their AI investigation briefs (last 12 months).
-- customer_name and customer_email are personal data.
SELECT
  f.customer_id,
  f.customer_name,
  d.customer_email,
  f.segment,
  f.region,
  f.total_returns,
  f.total_refund_value,
  f.approval_rate,
  f.anomaly_score,
  f.rules_violated,
  f.investigation_brief
FROM gold.flagged_return_customers AS f
LEFT JOIN gold.dim_customers AS d ON d.customer_id = f.customer_id AND d.is_current  -- SCD2: current version only
WHERE f.anomaly_score >= @min_anomaly
  AND (@region = 'All' OR f.region = @region)
  AND (@segment = 'All' OR f.segment = @segment)
ORDER BY f.anomaly_score DESC, f.total_refund_value DESC
LIMIT 25
