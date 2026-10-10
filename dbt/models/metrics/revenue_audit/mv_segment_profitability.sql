-- Segment profitability by region (Revenue Audit).
select
    c.segment,
    c.region,
    count(distinct s.order_id) as order_count,
    count(distinct s.customer_id) as customer_count,
    {{ round_half_up(exact_sum('s.sales'), 2) }} as total_revenue,
    {{ round_half_up(exact_sum('s.profit'), 2) }} as total_profit,
    {{ round_half_up(safe_divide(exact_sum('s.profit'), exact_sum('s.sales')) ~ ' * 100', 2) }} as profit_margin_pct,
    {{ round_half_up(exact_avg('s.discount'), 4) }} as avg_discount
from {{ ref('fact_sales') }} as s
inner join {{ ref('dim_customers') }} as c on s.customer_sk = c.customer_sk and c.customer_sk != -1
group by c.segment, c.region
