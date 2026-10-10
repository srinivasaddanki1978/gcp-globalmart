-- Product x region performance; slow-moving = bottom 25% by quantity within the
-- region (Inventory Blindspot), using the exact PERCENTILE_DISC.
with agg as (
    select
        s.product_id,
        p.product_name,
        p.brand,
        c.region,
        {{ round_half_up(exact_sum('s.sales'), 2) }} as total_sales,
        sum(s.quantity) as total_quantity,
        count(distinct s.order_id) as order_count,
        {{ round_half_up(exact_sum('s.profit'), 2) }} as total_profit
    from {{ ref('fact_sales') }} as s
    inner join {{ ref('dim_products') }} as p on s.product_id = p.product_id
    inner join {{ ref('dim_customers') }} as c on s.customer_sk = c.customer_sk  -- region as of the order
    group by s.product_id, p.product_name, p.brand, c.region
)

select
    * except (_p25_qty),
    total_quantity <= _p25_qty as is_slow_moving
from (
    select *, percentile_disc(total_quantity, 0.25) over (partition by region) as _p25_qty
    from agg
)
