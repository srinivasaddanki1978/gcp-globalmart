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
