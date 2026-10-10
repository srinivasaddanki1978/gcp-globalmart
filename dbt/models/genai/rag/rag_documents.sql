-- UC3 retrieval corpus, the same documents as the Databricks notebook (uc3_product_rag.py):
--   detail  : one per product, product x region, product x region return cost, vendor x region
--   summary : vendor summaries + pre-ranked top-N lists, so "top / highest / lowest"
--             questions retrieve one ranked document instead of a sample of details
-- doc_region drives region filtering ("in the <Region> region"; NULL = region-neutral).
-- embed_text is what gets embedded: ranked lists by their title only.
{%- set top_n = 10 %}

with slow as (
    select * from {{ ref('mv_slow_moving_products') }}
),

impact as (
    select * from {{ ref('mv_product_return_impact') }}
),

vendors as (
    select * from {{ ref('mv_return_rate_by_vendor') }}
),

vendor_region as (
    select
        vendor_id,
        vendor_name,
        region,
        {{ spark_round(exact_sum('total_sales'), 2) }} as total_sales,
        sum(order_count) as order_count,
        count(distinct product_id) as product_count,
        sum(return_count) as return_lines,
        {{ spark_round(exact_sum('total_allocated_refund'), 2) }} as refunded
    from {{ ref('mv_vendor_product_performance') }}
    group by vendor_id, vendor_name, region
),

product_metrics as (
    select
        product_id,
        {{ exact_sum('total_sales') }} as total_sales,
        sum(total_quantity) as total_quantity,
        sum(order_count) as order_count,
        {{ exact_sum('total_profit') }} as total_profit,
        string_agg(region, ', ' order by region) as regions,
        string_agg(if(is_slow_moving, region, null), ', ' order by region) as slow_regions
    from slow
    group by product_id
),

detail as (
    select concat(
        'Product: ', p.product_name, ' (ID: ', p.product_id, '). Brand: ', coalesce(p.brand, 'None'),
        '. Category: ', coalesce(p.category, 'None'), '. ',
        'Total sales: ', {{ money('m.total_sales') }}, '. Quantity sold: ', cast(coalesce(m.total_quantity, 0) as string), '. ',
        'Profit: ', {{ money('m.total_profit') }}, '. Orders: ', cast(coalesce(m.order_count, 0) as string), '. ',
        'Sold in regions: ', coalesce(m.regions, 'none'), '. Slow-moving in regions: ', coalesce(m.slow_regions, 'none'), '.'
    ) as doc_text
    from {{ ref('dim_products') }} as p
    left join product_metrics as m on p.product_id = m.product_id
    where p.product_sk != -1

    union all
    select concat(
        'Product-Region: ', product_name, ' in the ', region, ' region. Brand: ', coalesce(brand, 'None'), '. ',
        'Sales: ', {{ money('total_sales') }}, '. Quantity: ', cast(coalesce(total_quantity, 0) as string), '. ',
        'Orders: ', cast(coalesce(order_count, 0) as string), '. Profit: ', {{ money('total_profit') }}, '. ',
        'Slow-moving in this region: ', if(is_slow_moving, 'YES', 'No'), '.'
    )
    from slow

    union all
    select concat(
        'Product return cost: ', product_name, ' in the ', region, ' region. Brand: ', coalesce(brand, 'None'), '. ',
        'Return cost (refunds allocated to this product): ', {{ money('total_return_cost') }},
        ' across ', cast(return_line_count as string), ' returned order lines (average ', {{ money('avg_return_cost') }}, ').'
    )
    from impact

    union all
    select concat(
        'Vendor-Region: vendor (supplier) ', vendor_name, ' is active in the ', region, ' region ',
        'with sales of ', {{ money('total_sales') }}, ' across ', cast(order_count as string), ' orders and ',
        cast(product_count as string), ' products; ', cast(return_lines as string), ' returned lines, ',
        {{ money('refunded') }}, ' refunded.'
    )
    from vendor_region
),

-- Ranked lists: rank within the list, then "Title: 1. a; 2. b; ...".
ranked as (
    select 'top_sellers' as list, region, product_id as id,
           concat(product_name, ' (', coalesce(brand, 'None'), ') ', {{ money('total_sales') }}) as item,
           row_number() over (partition by region order by total_sales desc, product_id) as rn
    from slow
    union all
    select 'slowest', region, product_id,
           concat(product_name, ' (', coalesce(brand, 'None'), ') ', {{ money('total_sales') }}, ', ',
                  cast(total_quantity as string), ' units'),
           row_number() over (partition by region order by total_sales asc, product_id)
    from slow
    where is_slow_moving
    union all
    select 'top_return_cost_overall', cast(null as string), concat(product_id, region),
           concat(product_name, ' in ', region, ' ', {{ money('total_return_cost') }}),
           row_number() over (order by total_return_cost desc, product_id, region)
    from impact
    union all
    select 'top_return_cost', region, product_id,
           concat(product_name, ' ', {{ money('total_return_cost') }}),
           row_number() over (partition by region order by total_return_cost desc, product_id)
    from impact
),

lists as (
    select
        list,
        region,
        count(*) as n,
        string_agg(concat(cast(rn as string), '. ', item), '; ' order by rn) as items
    from ranked
    where rn <= {{ top_n }}
    group by list, region
),

summary as (
    select concat(
        'Vendor (supplier): ', vendor_name, ' (ID: ', vendor_id, '). ',
        'Total orders: ', cast(coalesce(total_orders, 0) as string), '. Total sales: ', {{ money('total_sales') }}, '. ',
        'Orders with a return: ', cast(coalesce(return_order_count, 0) as string), '. Total refunded: ', {{ money('total_refunded') }}, '. ',
        'Return rate: ', format('%.2f', coalesce(return_rate_pct, 0)), '% of orders.'
    ) as doc_text
    from vendors

    union all
    select concat(
        case list
            when 'top_sellers' then concat('Top ', cast(n as string), ' top-selling (best-selling, highest sales) products in the ', region, ' region, ranked by sales')
            when 'slowest' then concat('Slow-moving (lowest sales, worst-selling) products in the ', region, ' region, ranked from lowest sales')
            when 'top_return_cost_overall' then concat('Top ', cast(n as string), ' products with the highest return cost (most refunded) overall, all regions')
            when 'top_return_cost' then concat('Products with the highest return cost (most refunded) in the ', region, ' region, ranked')
        end,
        ': ', items, '.'
    )
    from lists

    union all
    select concat(
        'Vendors (suppliers) ranked by return rate, highest first: ',
        string_agg(concat(cast(rn as string), '. ', vendor_name, ' ', format('%.2f', coalesce(return_rate_pct, 0)), '% (',
                          cast(return_order_count as string), ' of ', cast(total_orders as string), ' orders)'), '; ' order by rn),
        '.'
    )
    from (select *, row_number() over (order by return_rate_pct desc, vendor_id) as rn from vendors)

    union all
    select concat(
        'All vendors (suppliers) active in the ', region, ' region, by sales: ',
        string_agg(concat(cast(rn as string), '. ', vendor_name, ' ', {{ money('total_sales') }},
                          ' (', cast(order_count as string), ' orders)'), '; ' order by rn),
        '.'
    )
    from (select *, row_number() over (partition by region order by total_sales desc, vendor_id) as rn from vendor_region)
    group by region
),

docs as (
    select distinct 'detail' as pool, doc_text, doc_text as embed_text from detail
    union all
    select distinct 'summary', doc_text, if(strpos(doc_text, ': 1. ') > 0, split(doc_text, ': 1. ')[offset(0)], doc_text)
    from summary
)

select
    {{ hash_key(['pool', 'doc_text']) }} as doc_id,
    pool,
    regexp_extract(doc_text, r'in the (\w+) region') as doc_region,
    doc_text,
    embed_text,
    {{ hash_key(['embed_text']) }} as embed_key
from docs
