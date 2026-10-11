{#-
  PII masking at the Gold boundary. Silver keeps real customer names and emails
  (restricted: the app, dashboards and data agent can't read the silver dataset);
  everything in gold and downstream carries masked values:
    email  dbindel@gmail.com -> XXXXX@gmail.com   (domain kept for analysis)
    name   Brendan Sweed     -> BrenXXXXX
  Authorised users look up real values in silver.customer_pii.
-#}
{% macro mask_email(expr) -%}
    regexp_replace({{ expr }}, r'^[^@]*', 'XXXXX')
{%- endmacro %}

{% macro mask_name(expr) -%}
    if({{ expr }} is null, null, concat(substr({{ expr }}, 1, 4), 'XXXXX'))
{%- endmacro %}

{#- Mask "customer_name" values inside a JSON text (e.g. rejected-record samples). -#}
{% macro mask_json_names(expr) -%}
    regexp_replace({{ expr }}, r'("customer_name"\s*:\s*"[^"]{0,4})[^"]*"', r'\1XXXXX"')
{%- endmacro %}
