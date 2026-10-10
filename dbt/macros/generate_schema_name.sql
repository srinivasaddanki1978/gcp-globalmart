{#- Use the configured +schema as the dataset name as-is (bronze/silver/gold/metrics),
    instead of dbt's default "<target_dataset>_<schema>". -#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {{ (custom_schema_name or target.schema) | trim }}
{%- endmacro %}
