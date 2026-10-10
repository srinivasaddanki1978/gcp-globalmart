{#-
  Platform-specific SQL lives here, behind adapter.dispatch, so models stay
  portable (Phase 10 adds databricks__ versions). Semantics follow Spark's
  non-ANSI behaviour, because that is what the Databricks pipeline produced:
  failed casts and parses return NULL.
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


{#- Spark's double -> long cast truncates; BigQuery's float64 -> int64 rounds. -#}
{% macro truncate_to_int(expr) -%}
    {{ return(adapter.dispatch('truncate_to_int', 'globalmart')(expr)) }}
{%- endmacro %}

{% macro bigquery__truncate_to_int(expr) -%}
    safe_cast(trunc({{ expr }}) as int64)
{%- endmacro %}


{#- Text form of a value inside record_data, matching Spark's cast(... as string):
    doubles keep a trailing ".0" and timestamps print as "yyyy-MM-dd HH:mm:ss". -#}
{% macro spark_string(expr, type='string') -%}
    {{ return(adapter.dispatch('spark_string', 'globalmart')(expr, type)) }}
{%- endmacro %}

{% macro bigquery__spark_string(expr, type) -%}
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
    (same variants the Databricks notebook checks). -#}
{% macro is_region_4(path) -%}
    (strpos({{ path }}, 'Region 4') > 0 or strpos({{ path }}, 'Region%204') > 0 or strpos({{ path }}, 'Region4') > 0)
{%- endmacro %}


{#- Stable surrogate key from business key columns (improvement over Databricks'
    monotonically_increasing_id, which changes on every rebuild). -#}
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


{#- Spark's round(double, n): HALF_UP on the double's shortest decimal text
    (2.675 -> 2.68). BigQuery's ROUND on FLOAT64 works on the binary value. -#}
{% macro spark_round(expr, n) -%}
    {{ return(adapter.dispatch('spark_round', 'globalmart')(expr, n)) }}
{%- endmacro %}

{% macro bigquery__spark_round(expr, n) -%}
    cast(round(cast(cast({{ expr }} as string) as bignumeric), {{ n }}) as float64)
{%- endmacro %}


{#- Spark's x / y on doubles returns NULL for y = 0; BigQuery raises an error. -#}
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
    total doesn't depend on row order (Spark's double sums do). Use for money. -#}
{% macro exact_sum(expr) -%}
    {{ return(adapter.dispatch('exact_sum', 'globalmart')(expr)) }}
{%- endmacro %}

{% macro bigquery__exact_sum(expr) -%}
    cast(sum(cast(cast({{ expr }} as string) as bignumeric)) as float64)
{%- endmacro %}
