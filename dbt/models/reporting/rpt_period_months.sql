{{ config(materialized='table') }}
-- The like-for-like rule for year-over-year comparisons, defined once.
-- For each year and period (FY, Q1-Q4, YTD) and month:
--   in_period  : the month belongs to the period (YTD = January up to the year's last month with data)
--   has_data   : the year has sales in that month
--   comparable : the month has data in both this year and the previous year
-- Current values sum in_period months; YoY % compares only comparable months, so a
-- partial year (the data starts Oct 2016 and ends Sep 2026) is never compared with a full one.
with data_months as (
    select distinct year, month from {{ ref('rpt_sales_lines') }}
),

last_month as (
    select year, max(month) as max_month from data_months group by year
),

grid as (
    select l.year, l.max_month, period, month
    from last_month as l,
        unnest(['FY', 'Q1', 'Q2', 'Q3', 'Q4', 'YTD']) as period,
        unnest(generate_array(1, 12)) as month
)

select
    g.year,
    g.period,
    g.month,
    case g.period
        when 'FY' then true
        when 'YTD' then g.month <= g.max_month
        when 'Q1' then g.month between 1 and 3
        when 'Q2' then g.month between 4 and 6
        when 'Q3' then g.month between 7 and 9
        when 'Q4' then g.month between 10 and 12
    end as in_period,
    cur.month is not null as has_data,
    cur.month is not null and prev.month is not null as comparable
from grid as g
left join data_months as cur on g.year = cur.year and g.month = cur.month
left join data_months as prev on g.year - 1 = prev.year and g.month = prev.month
