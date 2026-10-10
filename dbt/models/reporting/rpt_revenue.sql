-- Looker Studio "Revenue" page: monthly revenue by region (Databricks ds_revenue).
select year, month, date(year, month, 1) as month_start, region, total_sales, total_profit, order_count
from {{ ref('mv_revenue_by_region') }}
