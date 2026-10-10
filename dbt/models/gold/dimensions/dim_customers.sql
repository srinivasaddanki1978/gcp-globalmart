-- Customer dimension, SCD Type 2: one row per customer version, built from the
-- customers_snapshot history. Facts point at the version in effect on the event
-- date; filter is_current for today's attributes (one row per customer_id).
-- The first version of each customer is open from 1900-01-01, so every historical
-- order finds a version even though tracking started with the first snapshot run.
with versions as (
    select
        *,
        row_number() over (partition by customer_id order by dbt_valid_from) as _version_no
    from {{ ref('customers_snapshot') }}
)

select
    {{ hash_key(['customer_id', 'dbt_valid_from']) }} as customer_sk,
    customer_id,
    customer_name,
    customer_email,
    segment,
    city,
    state,
    region,
    if(_version_no = 1, timestamp '1900-01-01', dbt_valid_from) as valid_from,
    coalesce(dbt_valid_to, timestamp '9999-12-31') as valid_to,
    dbt_valid_to is null as is_current
from versions

union all

{{ unknown_member('customer_sk', {
    'customer_id': "'UNKNOWN'", 'customer_name': "'Unknown'", 'customer_email': 'cast(null as string)',
    'segment': "'Unknown'", 'city': 'cast(null as string)', 'state': 'cast(null as string)', 'region': "'Unknown'",
    'valid_from': "timestamp '1900-01-01'", 'valid_to': "timestamp '9999-12-31'", 'is_current': 'true',
}) }}
