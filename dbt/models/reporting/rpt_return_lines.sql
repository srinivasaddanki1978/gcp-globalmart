-- One row per return, dated by the return date. Returns whose order was rejected in
-- Silver have the Unknown customer and vendor (region 'Unknown').
select
    r.return_sk,
    r.order_id,
    d.year,
    d.quarter,
    d.month,
    d.month_name,
    c.customer_id,
    c.customer_name,
    c.region,
    c.segment,
    v.vendor_name,
    r.return_reason,
    r.return_status,
    r.refund_amount
from {{ ref('fact_returns') }} as r
inner join {{ ref('dim_dates') }} as d on r.return_date_sk = d.date_sk
inner join {{ ref('dim_customers') }} as c on r.customer_sk = c.customer_sk
inner join {{ ref('dim_vendors') }} as v on r.vendor_sk = v.vendor_sk
