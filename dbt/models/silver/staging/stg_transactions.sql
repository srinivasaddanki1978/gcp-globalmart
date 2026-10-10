-- Harmonise order/product ID casing, strip currency symbols from sales,
-- convert percentage discounts to fractions, then flag rule failures.
with harmonised as (
    select
        order_id,
        product_id,
        regexp_replace(sales, r'[^0-9.\-]', '') as _raw_sales,
        quantity as _raw_quantity,
        discount as _raw_discount,
        profit,
        payment_type,
        _source_file,
        _load_timestamp
    from {{ source('bronze', 'raw_transactions') }}
),

mapped as (
    select
        *,
        case
            when contains_substr(_raw_discount, '%')
                then {{ try_cast("replace(_raw_discount, '%', '')", 'float64') }} / 100.0
            else {{ try_cast('_raw_discount', 'float64') }}
        end as discount,
        {{ try_cast('_raw_sales', 'float64') }} as sales,
        {{ try_cast('_raw_quantity', 'int64') }} as quantity
    from harmonised
)

select
    *,
    {{ rule_columns('transactions') }}
from mapped
