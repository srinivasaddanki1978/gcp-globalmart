-- Return reasons by region (Returns Fraud).
select
    r.return_reason,
    c.region,
    count(*) as return_count,
    {{ round_half_up(exact_sum('r.refund_amount'), 2) }} as total_refunded,
    {{ round_half_up(exact_avg('r.refund_amount'), 2) }} as avg_refund,
    count(distinct r.customer_id) as unique_customers,
    countif(r.return_status = 'Approved') as approved_count,
    countif(r.return_status = 'Rejected') as rejected_count
from {{ ref('fact_returns') }} as r
inner join {{ ref('dim_customers') }} as c on r.customer_sk = c.customer_sk and c.customer_sk != -1
group by r.return_reason, c.region
