-- "Inventory" page: top 20 product-regions by allocated return cost.
select product_name, brand, region, total_return_cost, return_line_count
from {{ ref('mv_product_return_impact') }}
order by total_return_cost desc
limit 20
