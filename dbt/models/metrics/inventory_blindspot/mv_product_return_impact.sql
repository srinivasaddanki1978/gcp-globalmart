-- Return cost per product and region (Inventory Blindspot). The bridge joins to
-- sales on order_id AND product_sk; order_id alone would fan out across lines.
with sales_region as (
    select distinct s.order_id, s.product_sk, c.region
    from {{ ref('fact_sales') }} as s
    inner join {{ ref('dim_customers') }} as c on s.customer_sk = c.customer_sk and c.customer_sk != -1
)

select
    b.product_id,
    p.product_name,
    p.brand,
    sr.region,
    count(*) as return_line_count,
    {{ round_half_up(exact_sum('b.allocated_refund'), 2) }} as total_return_cost,
    {{ round_half_up(exact_avg('b.allocated_refund'), 2) }} as avg_return_cost,
    {{ round_half_up(exact_sum('b.allocation_weight'), 4) }} as total_allocation_weight
from {{ ref('bridge_return_products') }} as b
inner join sales_region as sr on b.order_id = sr.order_id and b.product_sk = sr.product_sk
inner join {{ ref('dim_products') }} as p on b.product_sk = p.product_sk
group by b.product_id, p.product_name, p.brand, sr.region
