-- UC1 DQ reporter: one row per failing rule (source_table, field, issue type) with
-- counts, up to 3 sample records, and a Gemini explanation for business data stewards.
-- Samples are the first 3 distinct records in sorted order, so reruns are stable.
{%- set samples_per_issue = 3 %}

with grouped as (
    select
        replace(source_table, 'clean_', '') as entity,
        affected_field,
        issue_type,
        count(*) as rejected_count,
        array_agg(distinct record_data order by record_data limit {{ samples_per_issue }}) as samples
    from {{ ref('rejected_records') }}
    group by source_table, affected_field, issue_type
),

enriched as (
    select
        g.entity,
        g.affected_field,
        g.issue_type,
        g.rejected_count,
        coalesce(a.bronze_count, 0) as total_entity_records,
        if(coalesce(a.bronze_count, 0) > 0, g.rejected_count / a.bronze_count * 100, 0.0) as rejection_rate,
        to_json_string(g.samples) as sample_records
    from grouped as g
    left join {{ ref('pipeline_audit_log') }} as a on g.entity = a.entity
),

explained as (
    select
        *,
        {{ gemini(
            "concat(
                'A data quality check rejected ', cast(rejected_count as string), ' of ', cast(total_entity_records as string),
                ' ', entity, ' records\\n(', format('%.1f', rejection_rate), '%) because the \"', affected_field,
                '\" field had a \"', issue_type, '\" problem.\\n\\n',
                'Sample rejected records (JSON):\\n',
                replace(sample_records, '\\\\\"NULL\\\\\"', '\\\\\"(blank)\\\\\"'), '\\n\\n',
                'Write an explanation that:\\n',
                '1. Describes the problem in plain business language\\n',
                '2. Names the field and quotes example bad values from the samples\\n',
                '3. Identifies which business report or audit figure could be wrong because of this issue\\n',
                '4. Recommends what the data steward should investigate to fix it'
            )",
            system="You are a data quality analyst at GlobalMart, a US retail chain, writing for
business data stewards (not engineers).
Rules:
- Never use technical terms such as NULL, parse, schema, boolean, timestamp, or column.
- In the sample records, \"(blank)\" means the value was missing. Describe it in words, e.g. \"left blank\".
- Only mention values that actually appear in the samples. Do not invent examples.
- Answer in plain prose, 3-4 sentences, with no headings or bullet points."
        ) }} as _ai
    from enriched
)

select
    entity,
    affected_field,
    issue_type,
    rejected_count,
    total_entity_records,
    round(rejection_rate, 2) as rejection_rate_pct,
    sample_records,
    _ai.result as ai_explanation,
    nullif(_ai.status, '') as ai_status,
    current_timestamp() as generated_at
from explained
