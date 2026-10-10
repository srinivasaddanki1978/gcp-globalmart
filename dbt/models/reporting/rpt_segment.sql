-- "Revenue" page: profit margin by segment (revenue-weighted).
select
    segment,
    {{ spark_round(exact_sum('total_revenue'), 2) }} as revenue,
    {{ spark_round(safe_divide(exact_sum('total_profit'), exact_sum('total_revenue')) ~ ' * 100', 2) }} as margin_pct
from {{ ref('mv_segment_profitability') }}
group by segment
