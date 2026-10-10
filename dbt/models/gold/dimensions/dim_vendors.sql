select
    {{ hash_key(['vendor_id']) }} as vendor_sk,
    vendor_id,
    vendor_name
from {{ ref('clean_vendors') }}

union all

{{ unknown_member('vendor_sk', {'vendor_id': "'UNKNOWN'", 'vendor_name': "'Unknown'"}) }}
