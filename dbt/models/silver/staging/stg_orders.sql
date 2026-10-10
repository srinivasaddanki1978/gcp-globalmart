-- Expand ship-mode abbreviations, lower-case status, parse the purchase date
-- (3 layouts in the files), then flag rule failures.
with harmonised as (
    select
        order_id,
        customer_id,
        vendor_id,
        trim(ship_mode) as _raw_ship_mode,
        lower(trim(order_status)) as _raw_order_status,
        order_purchase_date as _raw_order_date,
        _source_file,
        _load_timestamp
    from {{ source('bronze', 'raw_orders') }}
),

mapped as (
    select
        *,
        case
            when _raw_ship_mode in ('1st Class', '1st') then 'First Class'
            when _raw_ship_mode in ('2nd Class', '2nd') then 'Second Class'
            when _raw_ship_mode in ('Std Class', 'Std') then 'Standard Class'
            else _raw_ship_mode
        end as ship_mode,
        _raw_order_status as order_status,
        {{ try_parse_timestamp('_raw_order_date', [
            '%m/%d/%Y %H:%M',
            '%Y-%m-%d %H:%M',
            '%m/%d/%Y',
            '%Y-%m-%d',
            '%Y-%m-%dT%H:%M:%S',
        ]) }} as order_purchase_date
    from harmonised
)

select
    *,
    {{ rule_columns('orders') }}
from mapped
