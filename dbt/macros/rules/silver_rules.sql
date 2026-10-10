{#-
  The Silver quality rules: the ONLY place they are defined. Each stg_<entity>
  view turns them into _fail_<name> columns, clean_<entity> keeps rows where
  none fail, and rejected_records writes one row per failure.

  23 rules. `fail_if` is evaluated on the harmonised stg_ columns and
  wrapped in coalesce(..., false), so a NULL result never drops a row silently.

  record_data lists the fields serialised into rejected_records.record_data,
  in order; the type controls how each value is written as text (decimal_text).
-#}
{% macro silver_rules() %}
{{ return({
    'customers': {
        'record_key': 'customer_id',
        'rules': [
            {'name': 'customer_id_null',   'field': 'customer_id',   'issue_type': 'missing_value', 'fail_if': 'customer_id is null'},
            {'name': 'customer_name_null', 'field': 'customer_name', 'issue_type': 'missing_value', 'fail_if': 'customer_name is null'},
            {'name': 'invalid_segment',    'field': 'segment',       'issue_type': 'invalid_value', 'fail_if': "segment is null or segment not in ('Consumer', 'Corporate', 'Home Office')"},
            {'name': 'invalid_region',     'field': 'region',        'issue_type': 'invalid_value', 'fail_if': "region is null or region not in ('East', 'West', 'South', 'Central', 'North')"},
        ],
        'record_data': [
            ('customer_id', 'string'), ('customer_name', 'string'), ('customer_email', 'string'),
            ('segment', 'string'), ('region', 'string'), ('_raw_segment', 'string'), ('_raw_region', 'string'),
        ],
    },
    'orders': {
        'record_key': 'order_id',
        'rules': [
            {'name': 'order_id_null',        'field': 'order_id',            'issue_type': 'missing_value', 'fail_if': 'order_id is null'},
            {'name': 'customer_id_null',     'field': 'customer_id',         'issue_type': 'missing_value', 'fail_if': 'customer_id is null'},
            {'name': 'invalid_ship_mode',    'field': 'ship_mode',           'issue_type': 'invalid_value', 'fail_if': "ship_mode is null or ship_mode not in ('First Class', 'Second Class', 'Standard Class', 'Same Day')"},
            {'name': 'invalid_order_status', 'field': 'order_status',        'issue_type': 'invalid_value', 'fail_if': "order_status is null or order_status not in ('canceled', 'created', 'delivered', 'invoiced', 'processing', 'shipped', 'unavailable')"},
            {'name': 'unparseable_date',     'field': 'order_purchase_date', 'issue_type': 'parse_failure', 'fail_if': 'order_purchase_date is null'},
        ],
        'record_data': [
            ('order_id', 'string'), ('customer_id', 'string'), ('vendor_id', 'string'),
            ('ship_mode', 'string'), ('order_status', 'string'),
            ('_raw_ship_mode', 'string'), ('_raw_order_status', 'string'), ('_raw_order_date', 'string'),
        ],
    },
    'transactions': {
        'record_key': 'order_id',
        'rules': [
            {'name': 'order_id_null',           'field': 'order_id',   'issue_type': 'missing_value', 'fail_if': 'order_id is null'},
            {'name': 'product_id_null',         'field': 'product_id', 'issue_type': 'missing_value', 'fail_if': 'product_id is null'},
            {'name': 'negative_sales',          'field': 'sales',      'issue_type': 'out_of_range',  'fail_if': 'sales is null or sales < 0'},
            {'name': 'non_positive_quantity',   'field': 'quantity',   'issue_type': 'out_of_range',  'fail_if': 'quantity is null or quantity <= 0'},
            {'name': 'discount_out_of_range',   'field': 'discount',   'issue_type': 'out_of_range',  'fail_if': 'discount is null or discount < 0 or discount > 1'},
        ],
        'record_data': [
            ('order_id', 'string'), ('product_id', 'string'), ('sales', 'float64'),
            ('quantity', 'int64'), ('discount', 'float64'),
            ('_raw_sales', 'string'), ('_raw_quantity', 'string'), ('_raw_discount', 'string'),
        ],
    },
    'returns': {
        'record_key': 'order_id',
        'rules': [
            {'name': 'order_id_null',               'field': 'order_id',      'issue_type': 'missing_value', 'fail_if': 'order_id is null'},
            {'name': 'negative_refund',             'field': 'refund_amount', 'issue_type': 'out_of_range',  'fail_if': 'refund_amount is null or refund_amount < 0'},
            {'name': 'invalid_return_status',       'field': 'return_status', 'issue_type': 'invalid_value', 'fail_if': "return_status is null or return_status not in ('Approved', 'Pending', 'Rejected')"},
            {'name': 'invalid_return_reason',       'field': 'return_reason', 'issue_type': 'invalid_value', 'fail_if': "return_reason is null or return_reason = 'Unknown'"},
            {'name': 'unparseable_return_date',     'field': 'return_date',   'issue_type': 'parse_failure', 'fail_if': 'return_date is null'},
        ],
        'record_data': [
            ('order_id', 'string'), ('return_reason', 'string'), ('return_status', 'string'),
            ('refund_amount', 'float64'), ('return_date', 'timestamp'),
            ('_raw_return_reason', 'string'), ('_raw_return_status', 'string'),
            ('_raw_refund_amount', 'string'), ('_raw_return_date', 'string'),
        ],
    },
    'products': {
        'record_key': 'product_id',
        'rules': [
            {'name': 'product_id_null',   'field': 'product_id',   'issue_type': 'missing_value', 'fail_if': 'product_id is null'},
            {'name': 'product_name_null', 'field': 'product_name', 'issue_type': 'missing_value', 'fail_if': 'product_name is null'},
        ],
        'record_data': [('product_id', 'string'), ('product_name', 'string')],
    },
    'vendors': {
        'record_key': 'vendor_id',
        'rules': [
            {'name': 'vendor_id_null',   'field': 'vendor_id',   'issue_type': 'missing_value', 'fail_if': 'vendor_id is null'},
            {'name': 'vendor_name_null', 'field': 'vendor_name', 'issue_type': 'missing_value', 'fail_if': 'vendor_name is null'},
        ],
        'record_data': [('vendor_id', 'string'), ('vendor_name', 'string')],
    },
}) }}
{% endmacro %}


{#- _fail_<rule> columns, _has_any_failure and record_data for a stg_ view. -#}
{% macro rule_columns(entity) %}
    {%- set spec = silver_rules()[entity] -%}
    {%- for rule in spec['rules'] %}
    coalesce({{ rule['fail_if'] }}, false) as _fail_{{ rule['name'] }},
    {%- endfor %}
    (
        {%- for rule in spec['rules'] %}
        coalesce({{ rule['fail_if'] }}, false){{ " or" if not loop.last }}
        {%- endfor %}
    ) as _has_any_failure,
    -- Every field is wrapped in coalesce(..., 'NULL') so missing values stay visible in the JSON.
    {%- set pairs = [] %}
    {%- for field, type in spec['record_data'] %}
    {%- do pairs.append(("coalesce(" ~ decimal_text(field, type) ~ ", 'NULL')", field)) %}
    {%- endfor %}
    {{ json_object(pairs) }} as record_data
{%- endmacro %}


{#- The _fail_ column names for an entity, for selecting them downstream. -#}
{% macro fail_column_names(entity) -%}
    {%- for rule in silver_rules()[entity]['rules'] -%}
    _fail_{{ rule['name'] }}{{ ", " if not loop.last }}
    {%- endfor -%}
{%- endmacro %}
