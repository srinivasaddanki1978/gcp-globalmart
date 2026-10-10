with harmonised as (
    select
        trim(vendor_id) as vendor_id,
        trim(vendor_name) as vendor_name,
        _source_file,
        _load_timestamp
    from {{ source('bronze', 'raw_vendors') }}
)

select
    *,
    {{ rule_columns('vendors') }}
from harmonised
