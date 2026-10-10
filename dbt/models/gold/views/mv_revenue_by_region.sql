-- Monthly revenue by customer region (Revenue Audit).
select
    d.year,
    d.month,
    d.month_name,
    c.region,
    count(distinct s.order_id) as order_count,
    {{ spark_round(exact_sum('s.sales'), 2) }} as total_sales,
    {{ spark_round(exact_sum('s.profit'), 2) }} as total_profit,
    sum(s.quantity) as total_quantity,
    count(distinct s.customer_id) as unique_customers
from {{ ref('fact_sales') }} as s
inner join {{ ref('dim_customers') }} as c on s.customer_sk = c.customer_sk  -- region as of the order
inner join {{ ref('dim_dates') }} as d on s.order_date_key = d.date_key
group by d.year, d.month, d.month_name, c.region
