-- UC4 executive intel: three executive summaries (revenue, vendor returns,
-- slow-moving inventory). All KPIs, rankings and "highlights" are pre-computed in
-- SQL and passed to Gemini as JSON, so the model never derives or ranks figures.
{%- set system_prompt %}You are a senior business analyst writing executive summaries for GlobalMart's leadership.
Rules:
- Use only the KPI figures provided. Never invent numbers, periods, or causes the data does not show.
- Quote dollar amounts and percentages exactly as given (rounding to whole dollars is fine).
- Write 4-6 sentences of flowing prose with no headings or bullet points.{% endset %}

with
-- 1. Revenue performance -------------------------------------------------------
rev as (select * from {{ ref('mv_monthly_revenue_by_region') }}),

by_region as (
    select
        region,
        {{ round_half_up(exact_sum('total_revenue'), 2) }} as revenue,
        {{ round_half_up(exact_sum('total_profit'), 2) }} as profit
    from rev
    group by region
),

by_segment as (
    select
        segment,
        {{ round_half_up(exact_sum('total_revenue'), 2) }} as revenue,
        {{ round_half_up(exact_sum('total_profit'), 2) }} as profit,
        -- revenue-weighted margin, not the average of per-region margins
        {{ round_half_up(safe_divide(exact_sum('total_profit'), exact_sum('total_revenue')) ~ ' * 100', 2) }} as margin_pct
    from {{ ref('mv_segment_profitability') }}
    group by segment
),

revenue_kpis as (
    select to_json_string(struct(
        (select format('%d-%02d to %d-%02d', div(min(year * 100 + month), 100), mod(min(year * 100 + month), 100),
                       div(max(year * 100 + month), 100), mod(max(year * 100 + month), 100)) from rev) as period,
        (select {{ round_half_up(exact_sum('total_revenue'), 2) }} from rev) as grand_total_revenue,
        (select {{ round_half_up(exact_sum('total_profit'), 2) }} from rev) as grand_total_profit,
        (select sum(total_quantity) from rev) as grand_total_units,
        (select sum(order_count) from rev) as grand_total_orders,
        (select array_agg(struct(region, revenue, profit, {{ round_half_up('profit / revenue * 100', 2) }} as margin_pct)
                          order by revenue desc) from by_region) as by_region,
        (select array_agg(struct(segment, revenue, profit, margin_pct) order by margin_pct desc) from by_segment) as by_segment,
        struct(
            (select region from by_region order by revenue desc limit 1) as highest_revenue_region,
            (select region from by_region order by revenue asc limit 1) as lowest_revenue_region,
            (select region from by_region order by profit / revenue desc limit 1) as highest_margin_region,
            (select region from by_region order by profit / revenue asc limit 1) as lowest_margin_region,
            (select segment from by_segment order by margin_pct desc limit 1) as highest_margin_segment,
            (select segment from by_segment order by margin_pct asc limit 1) as lowest_margin_segment
        ) as highlights
    ), true) as kpi_data
),

-- 2. Vendor return rates ---------------------------------------------------------
vendors as (
    select * from {{ ref('mv_return_rate_by_vendor') }}
),

vendor_kpis as (
    select to_json_string(struct(
        'orders with at least one return / total orders' as return_rate_definition,
        (select array_agg(struct(
            vendor_name as vendor, total_orders, total_sales, return_order_count as orders_with_returns,
            return_rate_pct, total_refunded) order by return_rate_pct desc) from vendors) as vendors,
        (select {{ round_half_up(exact_sum('total_refunded'), 2) }} from vendors) as total_refunded_all_vendors,
        struct(
            (select vendor_name from vendors order by return_rate_pct desc limit 1) as highest_return_rate_vendor,
            (select vendor_name from vendors order by total_refunded desc limit 1) as largest_refunded_vendor
        ) as highlights
    ), true) as kpi_data
),

-- 3. Slow-moving inventory -------------------------------------------------------
impact as (select * from {{ ref('mv_product_return_impact') }}),

slow_stats as (
    select
        s.is_slow_moving,
        count(*) as product_regions,
        countif(i.total_return_cost > 0) as with_returns,
        {{ round_half_up(exact_sum('i.total_return_cost'), 2) }} as return_cost
    from {{ ref('mv_slow_moving_products') }} as s
    left join impact as i on s.product_id = i.product_id and s.region = i.region
    group by s.is_slow_moving
),

inventory_kpis as (
    select to_json_string(struct(
        (select count(*) from impact) as total_product_region_combos,
        (select {{ round_half_up(exact_sum('total_return_cost'), 2) }} from impact) as total_return_cost,
        (select {{ round_half_up(exact_avg('avg_return_cost'), 2) }} from impact) as avg_return_cost,
        (select array_agg(struct(product_name as product, region, total_return_cost as return_cost,
                                 return_line_count as return_lines) order by total_return_cost desc limit 5)
         from impact) as top_5_return_cost_products,
        (select struct(product_regions, {{ round_half_up(safe_divide('with_returns', 'product_regions') ~ ' * 100', 2) }} as share_with_returns_pct,
                       coalesce(return_cost, 0.0) as return_cost)
         from slow_stats where is_slow_moving) as slow_moving_product_regions,
        (select struct(product_regions, {{ round_half_up(safe_divide('with_returns', 'product_regions') ~ ' * 100', 2) }} as share_with_returns_pct,
                       coalesce(return_cost, 0.0) as return_cost)
         from slow_stats where not is_slow_moving) as other_product_regions
    ), true) as kpi_data
),

prompts as (
    select 'revenue_performance' as insight_type, kpi_data, concat(
        "Here are GlobalMart's revenue performance KPIs:\n", kpi_data, "\n\n",
        'Write a 4-6 sentence executive summary that:\n',
        '1. States the total revenue and profit figures\n',
        '2. Names the highest- and lowest-revenue regions exactly as given in "highlights", and notes the margin leader if different\n',
        '3. Compares segment profitability (Consumer vs Corporate vs Home Office) using margin_pct\n',
        '4. Highlights one actionable insight for the leadership team\n',
        '5. States the reporting period') as prompt
    from revenue_kpis
    union all
    select 'vendor_return_rate', kpi_data, concat(
        "This summary is for GlobalMart's procurement team. Here are the vendor return KPIs\n",
        '(vendors are sorted by return_rate_pct, highest first):\n', kpi_data, '\n\n',
        'Write a 4-6 sentence executive summary that:\n',
        '1. Names the vendor with the highest return rate and the one with the largest refunded dollars (these may differ)\n',
        '2. Compares return rates across vendors\n',
        '3. Quantifies the total refunded across all vendors\n',
        '4. Recommends which vendor relationships to renegotiate')
    from vendor_kpis
    union all
    select 'slow_moving_inventory', kpi_data, concat(
        "This summary is for GlobalMart's operations team. Here are the product return and\n",
        'slow-moving inventory KPIs (a "product-region" is one product sold in one region;\n',
        'slow-moving means the bottom 25% by units sold within its region):\n', kpi_data, '\n\n',
        'Write a 4-6 sentence executive summary that:\n',
        '1. States the total return cost across all products\n',
        '2. Identifies the products with the highest return costs by region\n',
        '3. Compares slow-moving and other product-regions using the share_with_returns_pct and return_cost figures\n',
        '4. Recommends inventory reallocation actions')
    from inventory_kpis
)

select
    insight_type,
    _ai.result as executive_summary,
    kpi_data,
    nullif(_ai.status, '') as ai_status,
    current_timestamp() as generated_at
from (select *, {{ gemini('prompt', system=system_prompt) }} as _ai from prompts)
