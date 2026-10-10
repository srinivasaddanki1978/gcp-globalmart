-- Rows of stg_customers that pass every rule (see macros/rules/silver_rules.sql).
-- Duplicates are kept; Gold deduplicates.
select
    customer_id, customer_name, customer_email, segment, city, state, region,
    _source_file,
    _load_timestamp,
    {{ fail_column_names('customers') }}
from {{ ref('stg_customers') }}
where not _has_any_failure
