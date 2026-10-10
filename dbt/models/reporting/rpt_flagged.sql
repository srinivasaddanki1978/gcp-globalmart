-- "Returns & Fraud" page: flagged customers with AI briefs.
select customer_name, customer_id, region, segment, total_returns, total_refund_value,
       anomaly_score, rules_violated, investigation_brief
from {{ ref('flagged_return_customers') }}
