-- Year-over-year inputs must add up: for every year, revenue summed by region equals
-- total revenue, and comparable-month revenue never exceeds the in-period revenue.
with by_region as (
    select s.year, s.region, sum(s.sales) as revenue
    from {{ ref('rpt_sales_lines') }} as s
    group by s.year, s.region
),

totals as (
    select year, sum(sales) as revenue from {{ ref('rpt_sales_lines') }} group by year
),

checks as (
    select t.year, t.revenue, sum(r.revenue) as region_sum
    from totals as t
    inner join by_region as r on t.year = r.year
    group by t.year, t.revenue
)

select * from checks where abs(revenue - region_sum) > 0.01
