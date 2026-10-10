-- Monthly revenue by region (Revenue Audit). Region is the customer's region at
-- the time of the order (fact_sales.customer_sk is the SCD2 version key).
select
    d.year,
    d.month,
    d.month_name,
    c.region,
    count(distinct s.order_id) as order_count,
    {{ spark_round(exact_sum('s.sales'), 2) }} as total_revenue,
    {{ spark_round(exact_sum('s.profit'), 2) }} as total_profit,
    sum(s.quantity) as total_quantity,
    count(distinct s.customer_id) as unique_customers,
    {{ spark_round(exact_avg('s.sales'), 2) }} as avg_order_value
from {{ ref('fact_sales') }} as s
inner join {{ ref('dim_customers') }} as c on s.customer_sk = c.customer_sk and c.customer_sk != -1
inner join {{ ref('dim_dates') }} as d on s.order_date_sk = d.date_sk and d.date_sk != -1
group by d.year, d.month, d.month_name, c.region
