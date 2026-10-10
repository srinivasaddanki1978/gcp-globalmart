-- Vendor x product x region performance with returns (Inventory Blindspot).
-- Returns are aggregated per vendor x product (no region) and
-- repeated on each region's row; don't sum return columns across regions.
with sales_agg as (
    select
        s.vendor_id,
        v.vendor_name,
        s.product_id,
        p.product_name,
        p.brand,
        c.region,
        count(distinct s.order_id) as order_count,
        {{ round_half_up(exact_sum('s.sales'), 2) }} as total_sales,
        sum(s.quantity) as total_quantity,
        {{ round_half_up(exact_sum('s.profit'), 2) }} as total_profit
    from {{ ref('fact_sales') }} as s
    inner join {{ ref('dim_customers') }} as c on s.customer_sk = c.customer_sk and c.customer_sk != -1
    inner join {{ ref('dim_products') }} as p on s.product_sk = p.product_sk
    inner join {{ ref('dim_vendors') }} as v on s.vendor_sk = v.vendor_sk
    group by s.vendor_id, v.vendor_name, s.product_id, p.product_name, p.brand, c.region
),

return_agg as (
    select
        o.vendor_id,
        b.product_id,
        count(*) as return_count,
        {{ round_half_up(exact_sum('b.allocated_refund'), 2) }} as total_allocated_refund
    from {{ ref('bridge_return_products') }} as b
    inner join (select distinct order_id, vendor_id from {{ ref('fact_sales') }}) as o on b.order_id = o.order_id
    group by o.vendor_id, b.product_id
)

select
    s.*,
    coalesce(r.return_count, 0) as return_count,
    coalesce(r.total_allocated_refund, 0.0) as total_allocated_refund
from sales_agg as s
left join return_agg as r on s.vendor_id = r.vendor_id and s.product_id = r.product_id
