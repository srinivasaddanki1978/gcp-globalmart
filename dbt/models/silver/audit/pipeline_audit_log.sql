-- Reconciliation per entity: bronze_count = silver_count + rejected_count.
-- rejected_records has one row per failed rule, so rejected rows are counted as
-- distinct (record_data, _source_file); record_key alone isn't unique.
{%- set entities = silver_rules().keys() | list %}

with
{%- for entity in entities %}
{{ entity }}_counts as (
    select
        '{{ entity }}' as entity,
        (select count(*) from {{ source('bronze', 'raw_' ~ entity) }}) as bronze_count,
        (select count(*) from {{ ref('clean_' ~ entity) }}) as silver_count,
        (
            select count(distinct concat(record_data, '||', _source_file))
            from {{ ref('rejected_records') }}
            where source_table = 'clean_{{ entity }}'
        ) as rejected_count
){{ "," if not loop.last }}
{%- endfor %}

select
    entity,
    bronze_count,
    silver_count,
    rejected_count,
    bronze_count - silver_count - rejected_count as reconciliation_diff,
    current_timestamp() as audit_timestamp
from (
    {%- for entity in entities %}
    select * from {{ entity }}_counts{{ " union all" if not loop.last }}
    {%- endfor %}
)
