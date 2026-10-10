-- @param min_anomaly INT64
-- Highest-scoring return-abuse candidates with their AI investigation briefs.
-- Scores cover each customer's last 12 months of returns (see uc2_fraud_investigator).
-- customer_name and customer_email are PII (no column masking on the GCP build yet).
-- Source: gold.flagged_return_customers + dim_customers (email)
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
FROM gold.flagged_return_customers f
LEFT JOIN gold.dim_customers d ON d.customer_id = f.customer_id AND d.is_current  -- SCD2: current version only
WHERE f.anomaly_score >= @min_anomaly
ORDER BY f.anomaly_score DESC, f.total_refund_value DESC
LIMIT 25
