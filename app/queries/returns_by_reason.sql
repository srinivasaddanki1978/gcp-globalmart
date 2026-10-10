-- @param target_year INT64
-- Why product returns happen, by refunded value.
-- Source: gold.bridge_return_products
SELECT
  return_reason,
  COUNT(*)                AS return_count,
  SUM(allocated_refund)   AS refunded
FROM gold.bridge_return_products
WHERE EXTRACT(YEAR FROM return_date_key) = @target_year
GROUP BY return_reason
ORDER BY refunded DESC
