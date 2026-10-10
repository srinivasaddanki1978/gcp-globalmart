-- "Inventory" page: slow-moving product counts by region.
select region, countif(is_slow_moving) as slow_moving_products, count(*) as product_regions
from {{ ref('mv_slow_moving_products') }}
group by region
