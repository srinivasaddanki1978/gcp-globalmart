-- Values for the dashboard filter dropdowns.
SELECT 'vendor' AS kind, vendor_name AS value FROM gold.dim_vendors WHERE vendor_sk != -1
UNION ALL SELECT DISTINCT 'brand', brand FROM gold.dim_products WHERE product_sk != -1 AND brand IS NOT NULL
UNION ALL SELECT DISTINCT 'ship_mode', ship_mode FROM gold.rpt_sales_lines
UNION ALL SELECT DISTINCT 'payment_type', payment_type FROM gold.rpt_sales_lines
UNION ALL SELECT DISTINCT 'return_reason', return_reason FROM gold.fact_returns
ORDER BY kind, value
