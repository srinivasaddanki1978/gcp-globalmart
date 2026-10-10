{#- Use the configured +schema as the dataset name as-is (bronze/silver/gold/metrics),
    instead of dbt's default "<target_dataset>_<schema>". The ci target appends
    "_ci" (silver_ci, gold_ci, ...) so CI builds never touch production tables. -#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- set name = (custom_schema_name or target.schema) | trim -%}
    {{ name ~ '_ci' if target.name == 'ci' else name }}
{%- endmacro %}
