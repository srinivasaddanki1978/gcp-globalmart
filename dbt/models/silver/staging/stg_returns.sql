-- Harmonise the 2 return layouts, expand status abbreviations, map '?' reasons
-- to Unknown, parse refunds ('$', '?') and dates (2 layouts), then flag failures.
with harmonised as (
    select
        coalesce(order_id, orderid) as order_id,
        coalesce(return_reason, reason) as _raw_return_reason,
        coalesce(return_status, status) as _raw_return_status,
        coalesce(refund_amount, amount) as _raw_refund_amount,
        coalesce(return_date, date_of_return) as _raw_return_date,
        _source_file,
        _load_timestamp
    from {{ source('bronze', 'raw_returns') }}
),

mapped as (
    select
        *,
        case
            when upper(trim(_raw_return_status)) = 'APPRVD' then 'Approved'
            when upper(trim(_raw_return_status)) = 'PENDG' then 'Pending'
            when upper(trim(_raw_return_status)) = 'RJCTD' then 'Rejected'
            else trim(_raw_return_status)
        end as return_status,
        case when trim(_raw_return_reason) = '?' then 'Unknown' else trim(_raw_return_reason) end as return_reason,
        case when _raw_refund_amount = '?' then null else {{ to_number('_raw_refund_amount') }} end as refund_amount,
        {{ try_parse_timestamp('_raw_return_date', [
            '%Y-%m-%d',
            '%m-%d-%Y',
            '%m/%d/%Y',
            '%Y-%m-%dT%H:%M:%S',
        ]) }} as return_date
    from harmonised
)

select
    *,
    {{ rule_columns('returns') }}
from mapped
