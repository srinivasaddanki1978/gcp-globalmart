-- GlobalMart parity baseline (the answer key).
-- Run in Databricks SQL against catalog `globalmart` after a successful
-- GlobalMart-End-to-End-Intelligence run. Export each result to
-- parity/baseline_results/<query_name>.csv. bigquery_parity.sql runs the same
-- queries against BigQuery; compare on business keys only (surrogate keys differ).

USE CATALOG globalmart;

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

-- q02_rows_per_file: row count per source file (pinpoints loader differences)
SELECT entity,
       regexp_extract(_source_file, 'source_data/(.*)$', 1) AS file_path,
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

-- q05_gold_row_counts: (target: dim_customers = 374)
SELECT 'dim_customers' AS table_name, COUNT(*) AS row_count FROM gold.dim_customers UNION ALL
SELECT 'dim_products',                COUNT(*) FROM gold.dim_products  UNION ALL
SELECT 'dim_vendors',                 COUNT(*) FROM gold.dim_vendors   UNION ALL
SELECT 'dim_dates',                   COUNT(*) FROM gold.dim_dates     UNION ALL
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

-- q08_fraud_flag_rate: flagged / scored customers, 12-month window (target: ~22%)
WITH window_end AS (SELECT MAX(return_date) AS d FROM gold.fact_returns),
scored AS (
  SELECT COUNT(DISTINCT r.customer_id) AS scored_customers
  FROM gold.fact_returns r
  JOIN gold.dim_customers c ON r.customer_sk = c.customer_sk
  CROSS JOIN window_end w
  WHERE r.return_date >= add_months(w.d, -12)
)
SELECT s.scored_customers,
       (SELECT COUNT(*) FROM gold.flagged_return_customers) AS flagged_customers,
       ROUND((SELECT COUNT(*) FROM gold.flagged_return_customers) * 100.0
             / s.scored_customers, 2)                      AS flag_rate_pct
FROM scored s;

-- q09_flagged_customers: business keys + scores for row-level comparison
SELECT customer_id, total_returns, total_refund_value, anomaly_score, rules_violated
FROM gold.flagged_return_customers
ORDER BY customer_id;

-- q10_metrics_row_counts: row count per metrics table
SELECT 'mv_monthly_revenue_by_region' AS table_name, COUNT(*) AS row_count FROM metrics.mv_monthly_revenue_by_region UNION ALL
SELECT 'mv_segment_profitability',       COUNT(*) FROM metrics.mv_segment_profitability       UNION ALL
SELECT 'mv_return_reason_analysis',      COUNT(*) FROM metrics.mv_return_reason_analysis      UNION ALL
SELECT 'mv_customer_return_history',     COUNT(*) FROM metrics.mv_customer_return_history     UNION ALL
SELECT 'mv_product_return_impact',       COUNT(*) FROM metrics.mv_product_return_impact       UNION ALL
SELECT 'mv_vendor_product_performance',  COUNT(*) FROM metrics.mv_vendor_product_performance
ORDER BY table_name;
