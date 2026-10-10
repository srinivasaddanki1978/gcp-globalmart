-- Vendor return rate = orders with a return / total orders (Returns Fraud).
with vendor_sales as (
    select vendor_id, count(distinct order_id) as total_orders, {{ round_half_up(exact_sum('sales'), 2) }} as total_sales
    from {{ ref('fact_sales') }}
    group by vendor_id
),

vendor_returns as (
    select vendor_id, count(distinct order_id) as return_order_count, {{ round_half_up(exact_sum('refund_amount'), 2) }} as total_refunded
    from {{ ref('fact_returns') }}
    where vendor_id is not null
    group by vendor_id
)

select
    s.vendor_id,
    v.vendor_name,
    s.total_orders,
    s.total_sales,
    coalesce(r.return_order_count, 0) as return_order_count,
    coalesce(r.total_refunded, 0.0) as total_refunded,
    {{ round_half_up(safe_divide('coalesce(r.return_order_count, 0)', 's.total_orders') ~ ' * 100', 2) }} as return_rate_pct
from vendor_sales as s
inner join {{ ref('dim_vendors') }} as v on s.vendor_id = v.vendor_id
left join vendor_returns as r on s.vendor_id = r.vendor_id
