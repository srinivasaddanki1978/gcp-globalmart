{#-
  Platform-specific SQL lives here, behind adapter.dispatch, so models stay
  portable across warehouses. Conventions: failed casts and date parses return
  NULL (bad values are caught by the Silver rules, never by query errors), and
  money is summed exactly and rounded half-up on its decimal value.
-#}

{#- First format that parses wins. `formats` are strftime-style (BigQuery). -#}
{% macro try_parse_timestamp(expr, formats) -%}
    {{ return(adapter.dispatch('try_parse_timestamp', 'globalmart')(expr, formats)) }}
{%- endmacro %}

{% macro bigquery__try_parse_timestamp(expr, formats) -%}
    coalesce(
        {%- for fmt in formats %}
        safe.parse_timestamp('{{ fmt }}', {{ expr }}){{ "," if not loop.last }}
        {%- endfor %}
    )
{%- endmacro %}


{% macro try_cast(expr, type) -%}
    {{ return(adapter.dispatch('try_cast', 'globalmart')(expr, type)) }}
{%- endmacro %}

{% macro bigquery__try_cast(expr, type) -%}
    safe_cast({{ expr }} as {{ type }})
{%- endmacro %}


{#- Keep digits, '.' and '-' only (strips '$', ',' and other symbols), then cast. -#}
{% macro to_number(expr) -%}
    {{ try_cast("regexp_replace(" ~ expr ~ ", r'[^0-9.\\-]', '')", 'float64') }}
{%- endmacro %}


{#- Double -> integer that truncates (BigQuery's float64 -> int64 cast rounds). -#}
{% macro truncate_to_int(expr) -%}
    {{ return(adapter.dispatch('truncate_to_int', 'globalmart')(expr)) }}
{%- endmacro %}

{% macro bigquery__truncate_to_int(expr) -%}
    safe_cast(trunc({{ expr }}) as int64)
{%- endmacro %}


{#- Text form of a value inside record_data: doubles keep a trailing ".0" and
    timestamps print as "yyyy-MM-dd HH:mm:ss". -#}
{% macro decimal_text(expr, type='string') -%}
    {{ return(adapter.dispatch('decimal_text', 'globalmart')(expr, type)) }}
{%- endmacro %}

{% macro bigquery__decimal_text(expr, type) -%}
    {%- if type == 'float64' -%}
    case
        when {{ expr }} = trunc({{ expr }}) and abs({{ expr }}) < 1e7 then format('%.1f', {{ expr }})
        else cast({{ expr }} as string)
    end
    {%- elif type == 'timestamp' -%}
    format_timestamp('%Y-%m-%d %H:%M:%S', {{ expr }})
    {%- else -%}
    cast({{ expr }} as string)
    {%- endif -%}
{%- endmacro %}


{#- Compact JSON object from (expression, key) pairs, keys in the given order. -#}
{% macro json_object(pairs) -%}
    {{ return(adapter.dispatch('json_object', 'globalmart')(pairs)) }}
{%- endmacro %}

{% macro bigquery__json_object(pairs) -%}
    to_json_string(struct(
        {%- for expr, key in pairs %}
        {{ expr }} as {{ key }}{{ "," if not loop.last }}
        {%- endfor %}
    ))
{%- endmacro %}


{#- Region 4 files have city and state swapped; matched on the folder in the path
    (plain, URL-encoded and space-less forms). -#}
{% macro is_region_4(path) -%}
    (strpos({{ path }}, 'Region 4') > 0 or strpos({{ path }}, 'Region%204') > 0 or strpos({{ path }}, 'Region4') > 0)
{%- endmacro %}


{#- Stable surrogate key from business key columns: the same key on every rebuild. -#}
{% macro hash_key(columns) -%}
    {{ return(adapter.dispatch('hash_key', 'globalmart')(columns)) }}
{%- endmacro %}

{% macro bigquery__hash_key(columns) -%}
    farm_fingerprint(concat(
        {%- for c in columns %}
        coalesce(cast({{ c }} as string), '<null>'){{ ", '|'," if not loop.last }}
        {%- endfor %}
    ))
{%- endmacro %}


{#- Round half-up on the double's shortest decimal text (2.675 -> 2.68).
    BigQuery's ROUND on FLOAT64 works on the binary value (2.675 -> 2.67). -#}
{% macro round_half_up(expr, n) -%}
    {{ return(adapter.dispatch('round_half_up', 'globalmart')(expr, n)) }}
{%- endmacro %}

{% macro bigquery__round_half_up(expr, n) -%}
    cast(round(cast(cast({{ expr }} as string) as bignumeric), {{ n }}) as float64)
{%- endmacro %}


{#- x / y that returns NULL for y = 0 instead of raising an error. -#}
{% macro safe_divide(x, y) -%}
    {{ return(adapter.dispatch('safe_divide', 'globalmart')(x, y)) }}
{%- endmacro %}

{% macro bigquery__safe_divide(x, y) -%}
    safe_divide({{ x }}, {{ y }})
{%- endmacro %}


{#- The Unknown member row (-1) every dimension carries, so facts never hold NULL
    keys. `columns` maps column name -> SQL literal, in the dimension's column order. -#}
{% macro unknown_member(key_column, columns) -%}
select
    -1 as {{ key_column }},
    {%- for name, value in columns.items() %}
    {{ value }} as {{ name }}{{ "," if not loop.last }}
    {%- endfor %}
{%- endmacro %}


{#- Exact decimal sum of doubles: adds each value's decimal text as BIGNUMERIC, so the
    total doesn't depend on row order (float sums can differ in the last cent). Use for money. -#}
{% macro exact_sum(expr) -%}
    {{ return(adapter.dispatch('exact_sum', 'globalmart')(expr)) }}
{%- endmacro %}

{% macro bigquery__exact_sum(expr) -%}
    cast(sum(cast(cast({{ expr }} as string) as bignumeric)) as float64)
{%- endmacro %}


{#- Exact decimal average of doubles (see exact_sum). -#}
{% macro exact_avg(expr) -%}
    {{ return(adapter.dispatch('exact_avg', 'globalmart')(expr)) }}
{%- endmacro %}

{% macro bigquery__exact_avg(expr) -%}
    cast(avg(cast(cast({{ expr }} as string) as bignumeric)) as float64)
{%- endmacro %}


{#- Distinct values joined with ', ', sorted so the result is deterministic
    (an unordered set would vary between runs). -#}
{% macro sorted_distinct_list(expr) -%}
    {{ return(adapter.dispatch('sorted_distinct_list', 'globalmart')(expr)) }}
{%- endmacro %}

{% macro bigquery__sorted_distinct_list(expr) -%}
    string_agg(distinct {{ expr }}, ', ' order by {{ expr }})
{%- endmacro %}
