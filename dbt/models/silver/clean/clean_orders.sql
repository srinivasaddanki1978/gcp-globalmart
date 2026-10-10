-- Rows of stg_orders that pass every rule (see macros/rules/silver_rules.sql).
-- Duplicates are kept; Gold deduplicates.
select
    order_id, customer_id, vendor_id, ship_mode, order_status, order_purchase_date, _raw_order_date,
    _source_file,
    _load_timestamp,
    {{ fail_column_names('orders') }}
from {{ ref('stg_orders') }}
where not _has_any_failure
