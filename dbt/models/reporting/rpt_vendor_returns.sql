-- "Returns & Fraud" page: vendor return rates.
select vendor_name, return_rate_pct, total_orders, return_order_count, total_refunded
from {{ ref('mv_return_rate_by_vendor') }}
