-- GlobalMart parity queries on BigQuery: the same `-- qNN_name:` blocks as
-- databricks_baseline.sql, so results line up with parity/baseline_results/.
-- Gold/metrics queries (q05+) are added as those layers are built.
-- Note: Databricks _source_file is URL-encoded (Region%201); GCS keeps spaces.
-- Full row-level checks: parity/compare_bronze.py, parity/compare_silver.py.

-- q01_bronze_files: files per entity (target: 205 total, each loaded once)
SELECT entity, COUNT(DISTINCT _source_file) AS file_count, COUNT(*) AS row_count
FROM (
  SELECT 'customers'    AS entity, _source_file FROM bronze.raw_customers    UNION ALL
  SELECT 'orders',                 _source_file FROM bronze.raw_orders       UNION ALL
  SELECT 'transactions',           _source_file FROM bronze.raw_transactions UNION ALL
  SELECT 'returns',                _source_file FROM bronze.raw_returns      UNION ALL
  SELECT 'products',               _source_file FROM bronze.raw_products     UNION ALL
  SELECT 'vendors',                _source_file FROM bronze.raw_vendors
)
GROUP BY entity
ORDER BY entity;

-- q02_rows_per_file: row count per source file
SELECT entity,
       REGEXP_EXTRACT(_source_file, r'source_data/(.*)$') AS file_path,
       COUNT(*) AS row_count
FROM (
  SELECT 'customers'    AS entity, _source_file FROM bronze.raw_customers    UNION ALL
  SELECT 'orders',                 _source_file FROM bronze.raw_orders       UNION ALL
  SELECT 'transactions',           _source_file FROM bronze.raw_transactions UNION ALL
  SELECT 'returns',                _source_file FROM bronze.raw_returns      UNION ALL
  SELECT 'products',               _source_file FROM bronze.raw_products     UNION ALL
  SELECT 'vendors',                _source_file FROM bronze.raw_vendors
)
GROUP BY ALL
ORDER BY entity, file_path;

-- q03_reconciliation: bronze = silver + rejected per entity (target: diff = 0)
SELECT entity, bronze_count, silver_count, rejected_count, reconciliation_diff
FROM silver.pipeline_audit_log
ORDER BY entity;

-- q04_failures_per_rule: one rule = (source_table, affected_field, issue_type)
SELECT source_table, affected_field, issue_type, COUNT(*) AS failure_count
FROM silver.rejected_records
GROUP BY ALL
ORDER BY source_table, affected_field, issue_type;

-- q05_gold_row_counts: (target: dim_customers = 590; Unknown members (-1) excluded)
SELECT 'dim_customers' AS table_name, COUNTIF(customer_sk != -1) AS row_count FROM gold.dim_customers UNION ALL
SELECT 'dim_products',                COUNTIF(product_sk != -1) FROM gold.dim_products  UNION ALL
SELECT 'dim_vendors',                 COUNTIF(vendor_sk != -1)  FROM gold.dim_vendors   UNION ALL
SELECT 'dim_dates',                   COUNTIF(date_sk != -1)    FROM gold.dim_dates     UNION ALL
SELECT 'fact_sales',                  COUNT(*) FROM gold.fact_sales    UNION ALL
SELECT 'fact_returns',                COUNT(*) FROM gold.fact_returns  UNION ALL
SELECT 'bridge_return_products',      COUNT(*) FROM gold.bridge_return_products
ORDER BY table_name;

-- q06_revenue_by_year_region: (target: match within rounding)
SELECT d.year, c.region,
       COUNT(DISTINCT s.order_id)  AS order_count,
       ROUND(SUM(s.sales), 2)      AS total_sales,
       ROUND(SUM(s.profit), 2)     AS total_profit,
       SUM(s.quantity)             AS total_quantity
FROM gold.fact_sales s
JOIN gold.dim_customers c ON s.customer_id = c.customer_id
JOIN gold.dim_dates d     ON s.order_date_key = d.date_key
GROUP BY d.year, c.region
ORDER BY d.year, c.region;

-- q07_bridge_vs_refunds: allocated refunds vs refunds (target: diff within cents)
SELECT
  (SELECT ROUND(SUM(refund_amount), 2)
     FROM gold.fact_returns
    WHERE order_id IN (SELECT order_id FROM gold.bridge_return_products)) AS refunds_with_lines,
  (SELECT ROUND(SUM(allocated_refund), 2) FROM gold.bridge_return_products) AS allocated_refund_total,
  (SELECT ROUND(SUM(refund_amount), 2) FROM gold.fact_returns)            AS refunds_total;
