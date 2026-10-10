-- "Revenue" page: profit margin by segment (revenue-weighted).
select
    segment,
    {{ round_half_up(exact_sum('total_revenue'), 2) }} as revenue,
    {{ round_half_up(safe_divide(exact_sum('total_profit'), exact_sum('total_revenue')) ~ ' * 100', 2) }} as margin_pct
from {{ ref('mv_segment_profitability') }}
group by segment
