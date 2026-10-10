-- "Returns & Fraud" page: returns by reason and region.
select return_reason, region, return_count, total_refunded
from {{ ref('mv_return_reason_analysis') }}
