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
