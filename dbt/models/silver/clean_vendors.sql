-- Rows of stg_vendors that pass every rule (see macros/rules/silver_rules.sql).
-- Duplicates are kept; Gold deduplicates.
select
    vendor_id, vendor_name,
    _source_file,
    _load_timestamp,
    {{ fail_column_names('vendors') }}
from {{ ref('stg_vendors') }}
where not _has_any_failure
