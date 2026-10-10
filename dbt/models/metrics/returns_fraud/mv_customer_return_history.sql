-- Customer return profiles (Returns Fraud). Returns without a known customer
-- (customer_sk = -1) are excluded.
select
    r.customer_id,
    c.customer_name,
    c.segment,
    c.region,
    count(*) as total_returns,
    {{ round_half_up(exact_sum('r.refund_amount'), 2) }} as total_refund_value,
    {{ round_half_up(exact_avg('r.refund_amount'), 2) }} as avg_refund_per_return,
    count(distinct r.return_reason) as distinct_reason_count,
    {{ sorted_distinct_list('r.return_reason') }} as return_reasons,
    countif(r.return_status = 'Approved') as approved_count,
    {{ round_half_up(safe_divide("countif(r.return_status = 'Approved')", 'count(*)') ~ ' * 100', 2) }} as approval_rate_pct,
    min(r.return_date) as first_return_date,
    max(r.return_date) as last_return_date
from {{ ref('fact_returns') }} as r
inner join {{ ref('dim_customers') }} as c on r.customer_sk = c.customer_sk and c.customer_sk != -1
group by r.customer_id, c.customer_name, c.segment, c.region
