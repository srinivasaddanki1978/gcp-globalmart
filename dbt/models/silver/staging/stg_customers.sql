-- Harmonise the 4 regional customer layouts, fix Region 4's city/state swap,
-- expand segment/region abbreviations, then flag rule failures.
with harmonised as (
    select
        coalesce(customer_id, customerid, cust_id, customer_identifier) as customer_id,
        coalesce(customer_name, full_name) as customer_name,
        coalesce(customer_email, email_address) as customer_email,
        coalesce(segment, customer_segment) as _raw_segment,
        city as _raw_city,
        state as _raw_state,
        region as _raw_region,
        _source_file,
        _load_timestamp
    from {{ source('bronze', 'raw_customers') }}
),

mapped as (
    select
        *,
        -- Region 4 ships city and state in each other's columns; fixed by folder name.
        case when {{ is_region_4('_source_file') }} then _raw_state else _raw_city end as city,
        case when {{ is_region_4('_source_file') }} then _raw_city else _raw_state end as state,
        case
            when upper(trim(_raw_segment)) = 'CONS' then 'Consumer'
            when upper(trim(_raw_segment)) = 'CORP' then 'Corporate'
            when upper(trim(_raw_segment)) = 'HO' then 'Home Office'
            when lower(trim(_raw_segment)) = 'cosumer' then 'Consumer'
            else trim(_raw_segment)
        end as segment,
        case
            when upper(trim(_raw_region)) = 'W' then 'West'
            when upper(trim(_raw_region)) = 'S' then 'South'
            else trim(_raw_region)
        end as region
    from harmonised
)

select
    *,
    {{ rule_columns('customers') }}
from mapped
