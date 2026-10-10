-- Trim text fields and repair UPCs exported in scientific notation (6.79E+11).
with harmonised as (
    select
        product_id,
        trim(product_name) as product_name,
        trim(brand) as brand,
        trim(categories) as category,
        cast({{ truncate_to_int(try_cast('upc', 'float64')) }} as string) as upc,
        _source_file,
        _load_timestamp
    from {{ source('bronze', 'raw_products') }}
)

select
    *,
    {{ rule_columns('products') }}
from harmonised
