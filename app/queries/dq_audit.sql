-- Silver-layer data quality issues with plain-English AI explanations.
-- Source: gold.dq_audit_report (written by uc1_dq_reporter)
SELECT
  entity,
  affected_field,
  issue_type,
  rejected_count,
  total_entity_records,
  rejection_rate_pct,
  ai_explanation
FROM gold.dq_audit_report
ORDER BY rejected_count DESC
