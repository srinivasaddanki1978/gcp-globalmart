-- Rows of stg_returns that pass every rule (see macros/rules/silver_rules.sql).
-- Duplicates are kept; Gold deduplicates.
select
    order_id, return_reason, return_status, refund_amount, return_date, _raw_return_reason, _raw_return_status, _raw_refund_amount, _raw_return_date,
    _source_file,
    _load_timestamp,
    {{ fail_column_names('returns') }}
from {{ ref('stg_returns') }}
where not _has_any_failure
