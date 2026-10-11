-- Product-level returns: each return's refund allocated to the order's lines (bridge),
-- dated by the return date, with the sale's product, brand, region, segment and vendor.
select
    b.return_sk,
    b.sales_sk,
    d.year,
    d.quarter,
    d.month,
    s.region,
    s.segment,
    s.vendor_name,
    s.product_id,
    s.product_name,
    s.brand,
    s.ship_mode,
    s.payment_type,
    b.return_reason,
    b.return_status,
    b.allocated_refund,
    b.allocation_weight
from {{ ref('bridge_return_products') }} as b
inner join {{ ref('dim_dates') }} as d on b.return_date_sk = d.date_sk
inner join {{ ref('rpt_sales_lines') }} as s on b.sales_sk = s.sales_sk
