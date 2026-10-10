-- Rows of stg_transactions that pass every rule (see macros/rules/silver_rules.sql).
-- Duplicates are kept; Gold deduplicates.
select
    order_id, product_id, sales, quantity, discount, profit, payment_type, _raw_sales, _raw_quantity, _raw_discount,
    _source_file,
    _load_timestamp,
    {{ fail_column_names('transactions') }}
from {{ ref('stg_transactions') }}
where not _has_any_failure
