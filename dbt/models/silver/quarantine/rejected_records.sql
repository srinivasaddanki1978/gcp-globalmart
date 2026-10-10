-- Quarantine: one row per rule failure, generated from the same rule list as the
-- clean tables, so the two can never drift apart.
{%- set rules = silver_rules() %}
{%- set selects = [] %}
{%- for entity, spec in rules.items() %}
{%- for rule in spec['rules'] %}
{%- set sql %}
select
    'clean_{{ entity }}' as source_table,
    cast({{ spec['record_key'] }} as string) as record_key,
    '{{ rule['field'] }}' as affected_field,
    '{{ rule['issue_type'] }}' as issue_type,
    record_data,
    _source_file,
    current_timestamp() as rejected_at
from {{ ref('stg_' ~ entity) }}
where _fail_{{ rule['name'] }}
{%- endset %}
{%- do selects.append(sql) %}
{%- endfor %}
{%- endfor %}

{{ selects | join('\nunion all\n') }}
