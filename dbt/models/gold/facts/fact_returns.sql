-- One row per return. LEFT JOIN keeps returns whose order was rejected in Silver
-- (~4.7%); they point at the Unknown customer and vendor (-1).
select
    {{ hash_key(['r.order_id']) }} as return_sk,
    r.order_id,
    coalesce(c.customer_sk, -1) as customer_sk,
    o.customer_id,
    coalesce(v.vendor_sk, -1) as vendor_sk,
    o.vendor_id,
    coalesce(d.date_sk, -1) as return_date_sk,
    date(r.return_date) as return_date_key,
    r.refund_amount,
    r.return_reason,
    r.return_status,
    r.return_date
from {{ ref('clean_returns') }} as r
left join {{ ref('clean_orders') }} as o on r.order_id = o.order_id
left join {{ ref('dim_customers') }} as c  -- version in effect on the return date (SCD2)
    on o.customer_id = c.customer_id and c.customer_sk != -1
    and r.return_date >= c.valid_from and r.return_date < c.valid_to
left join {{ ref('dim_vendors') }} as v on o.vendor_id = v.vendor_id and v.vendor_sk != -1
left join {{ ref('dim_dates') }} as d on date(r.return_date) = d.date_key
