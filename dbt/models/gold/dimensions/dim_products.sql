select
    {{ hash_key(['product_id']) }} as product_sk,
    product_id,
    product_name,
    brand,
    category,
    upc
from {{ ref('clean_products') }}

union all

{{ unknown_member('product_sk', {
    'product_id': "'UNKNOWN'", 'product_name': "'Unknown'", 'brand': 'cast(null as string)',
    'category': 'cast(null as string)', 'upc': 'cast(null as string)',
}) }}
