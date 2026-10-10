-- Allocates each return's refund across its order's lines, weighted by line sales.
-- Grain: one row per (return, sales line). Join to fact_sales on sales_sk, or on
-- order_id AND product_sk; order_id alone fans out across lines.
with order_totals as (
    select order_id, {{ exact_sum('sales') }} as total_order_sales
    from {{ ref('fact_sales') }}
    group by order_id
)

select
    r.return_sk,
    s.sales_sk,
    r.order_id,
    s.product_sk,
    s.product_id,
    r.return_date_sk,
    r.return_date_key,
    r.return_reason,
    r.return_status,
    r.refund_amount,
    s.sales as line_sales,
    t.total_order_sales,
    {{ spark_round(safe_divide('s.sales', 't.total_order_sales'), 4) }} as allocation_weight,
    {{ spark_round(safe_divide('r.refund_amount * s.sales', 't.total_order_sales'), 2) }} as allocated_refund
from {{ ref('fact_returns') }} as r
inner join {{ ref('fact_sales') }} as s on r.order_id = s.order_id
inner join order_totals as t on r.order_id = t.order_id
