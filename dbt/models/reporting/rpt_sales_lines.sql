-- One row per sales line with every attribute the app and dashboards filter or group on.
-- Region and segment are the customer's as of the order (SCD Type 2 version on the fact).
select
    s.sales_sk,
    s.order_id,
    d.year,
    d.quarter,
    d.month,
    d.month_name,
    c.customer_id,
    c.customer_name,
    c.region,
    c.segment,
    c.state,
    v.vendor_name,
    p.product_id,
    p.product_name,
    p.brand,
    s.ship_mode,
    coalesce(nullif(s.payment_type, '?'), 'unknown') as payment_type,
    s.sales,
    s.quantity,
    s.discount,
    s.profit,
    r.order_id is not null as order_has_return
from {{ ref('fact_sales') }} as s
inner join {{ ref('dim_dates') }} as d on s.order_date_sk = d.date_sk
inner join {{ ref('dim_customers') }} as c on s.customer_sk = c.customer_sk
inner join {{ ref('dim_vendors') }} as v on s.vendor_sk = v.vendor_sk
inner join {{ ref('dim_products') }} as p on s.product_sk = p.product_sk
left join (select distinct order_id from {{ ref('fact_returns') }}) as r on s.order_id = r.order_id
