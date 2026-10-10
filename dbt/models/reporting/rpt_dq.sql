-- "Data Quality & AI" page: rejected records per rule with AI explanations.
select entity, affected_field, issue_type, rejected_count, rejection_rate_pct, ai_explanation
from {{ ref('dq_audit_report') }}
