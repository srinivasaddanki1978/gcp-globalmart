-- One row per day, full calendar years from the earliest to the latest order or
-- return date. date_sk is the readable yyyymmdd integer.
with bounds as (
    select min(d) as min_date, max(d) as max_date
    from (
        select date(order_purchase_date) as d from {{ ref('clean_orders') }}
        union all
        select date(return_date) from {{ ref('clean_returns') }}
    )
),

calendar as (
    select date_key
    from bounds,
        unnest(generate_date_array(
            date(extract(year from min_date), 1, 1),
            date(extract(year from max_date), 12, 31)
        )) as date_key
)

select
    cast(format_date('%Y%m%d', date_key) as int64) as date_sk,
    date_key,
    extract(year from date_key) as year,
    extract(quarter from date_key) as quarter,
    extract(month from date_key) as month,
    format_date('%B', date_key) as month_name,
    extract(day from date_key) as day,
    extract(dayofweek from date_key) as day_of_week, -- 1 = Sunday, as in Spark
    extract(dayofweek from date_key) in (1, 7) as is_weekend
from calendar

union all

{{ unknown_member('date_sk', {
    'date_key': 'cast(null as date)', 'year': 'cast(null as int64)', 'quarter': 'cast(null as int64)',
    'month': 'cast(null as int64)', 'month_name': "'Unknown'", 'day': 'cast(null as int64)',
    'day_of_week': 'cast(null as int64)', 'is_weekend': 'cast(null as bool)',
}) }}
