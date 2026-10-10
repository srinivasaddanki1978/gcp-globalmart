-- @param target_year INT64
-- Top 10 products by refunded value. Refunds are order-level in the source
-- and allocated down to product lines by `allocation_weight`.
-- Source: gold.bridge_return_products x dim_products
SELECT
  SUBSTRING(p.product_name, 1, 38) AS product_name,
  COUNT(*)                         AS return_count,
  SUM(b.allocated_refund)          AS refunded
FROM gold.bridge_return_products b
JOIN gold.dim_products p ON b.product_sk = p.product_sk
WHERE EXTRACT(YEAR FROM b.return_date_key) = @target_year
GROUP BY SUBSTRING(p.product_name, 1, 38)
ORDER BY refunded DESC
LIMIT 10
