-- Rows of stg_products that pass every rule (see macros/rules/silver_rules.sql).
-- Duplicates are kept; Gold deduplicates.
select
    product_id, product_name, brand, category, upc,
    _source_file,
    _load_timestamp,
    {{ fail_column_names('products') }}
from {{ ref('stg_products') }}
where not _has_any_failure
