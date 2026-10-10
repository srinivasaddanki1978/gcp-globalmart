-- One row per order line (orders x transactions). Transactions repeat
-- (order_id, product_id) 63 times, so line_seq numbers lines within that pair
-- in a fixed order to give a stable, unique sales_sk.
-- Unmatched dimension lookups point at the Unknown member (-1), not NULL.
with lines as (
    select
        o.order_id,
        o.customer_id,
        t.product_id,
        o.vendor_id,
        date(o.order_purchase_date) as order_date_key,
        t.sales,
        t.quantity,
        t.discount,
        {{ try_cast('t.profit', 'float64') }} as profit,
        o.ship_mode,
        o.order_status,
        o.order_purchase_date,
        t.payment_type,
        row_number() over (
            partition by o.order_id, t.product_id
            order by t.sales, t.quantity, t.discount, t.profit, t.payment_type, t._source_file
        ) as line_seq
    from {{ ref('clean_orders') }} as o
    inner join {{ ref('clean_transactions') }} as t
        on o.order_id = t.order_id
)

select
    {{ hash_key(['l.order_id', 'l.product_id', 'l.line_seq']) }} as sales_sk,
    l.order_id,
    l.line_seq,
    coalesce(c.customer_sk, -1) as customer_sk,
    l.customer_id,
    coalesce(p.product_sk, -1) as product_sk,
    l.product_id,
    coalesce(v.vendor_sk, -1) as vendor_sk,
    l.vendor_id,
    coalesce(d.date_sk, -1) as order_date_sk,
    l.order_date_key,
    l.sales,
    l.quantity,
    l.discount,
    l.profit,
    l.ship_mode,
    l.order_status,
    l.order_purchase_date,
    l.payment_type
from lines as l
left join {{ ref('dim_customers') }} as c  -- version in effect on the order date (SCD2)
    on l.customer_id = c.customer_id and c.customer_sk != -1
    and l.order_purchase_date >= c.valid_from and l.order_purchase_date < c.valid_to
left join {{ ref('dim_products') }} as p on l.product_id = p.product_id and p.product_sk != -1
left join {{ ref('dim_vendors') }} as v on l.vendor_id = v.vendor_id and v.vendor_sk != -1
left join {{ ref('dim_dates') }} as d on l.order_date_key = d.date_key
