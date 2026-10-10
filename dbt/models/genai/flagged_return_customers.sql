-- UC2 fraud investigator: score each customer's last 12 months of returns with 5
-- weighted rules (thresholds = P85 across customers), flag score >= 40, and write a
-- Gemini investigation brief only for flagged customers (bounded cost).
-- Ported from databricks-globalmart/globalmart/gold/genai/uc2_fraud_investigator.py.
{%- set lookback_months = 12 %}
{%- set threshold_pct = 0.85 %}

with window_end as (
    select max(return_date) as end_ts from {{ ref('fact_returns') }}
),

returns as (
    select r.*
    from {{ ref('fact_returns') }} as r, window_end as w
    where r.return_date >= timestamp(date_sub(date(w.end_ts), interval {{ lookback_months }} month))
),

profiles as (
    select
        r.customer_id,
        c.customer_name,
        c.segment,
        c.region,
        count(*) as total_returns,
        {{ spark_round(exact_sum('r.refund_amount'), 2) }} as total_refund_value,
        {{ spark_round(exact_avg('r.refund_amount'), 2) }} as avg_refund_per_return,
        countif(r.return_status = 'Approved') as approved_count,
        count(distinct r.return_reason) as distinct_reason_count,
        {{ sorted_distinct_list('r.return_reason') }} as return_reasons
    from returns as r
    inner join {{ ref('dim_customers') }} as c on r.customer_sk = c.customer_sk and c.customer_sk != -1
    group by r.customer_id, c.customer_name, c.segment, c.region
),

-- P85 thresholds; PERCENTILE_DISC equals Spark's percentile_approx at this size.
thresholds as (
    select distinct
        greatest(percentile_disc(total_returns, {{ threshold_pct }}) over (), 3) as th_returns,
        percentile_disc(total_refund_value, {{ threshold_pct }}) over () as th_refund,
        percentile_disc(avg_refund_per_return, {{ threshold_pct }}) over () as th_avg_refund,
        greatest(percentile_disc(distinct_reason_count, {{ threshold_pct }}) over (), 3) as th_reasons
    from profiles
),

scored as (
    select
        p.*,
        {{ spark_round(safe_divide('p.approved_count', 'p.total_returns') ~ ' * 100', 2) }} as approval_rate,
        if(p.total_returns > t.th_returns, 20, 0) as score_high_return_count,
        if(p.total_refund_value > t.th_refund, 25, 0) as score_high_total_refund,
        if(p.avg_refund_per_return > t.th_avg_refund, 20, 0) as score_high_avg_refund,
        if(p.distinct_reason_count >= t.th_reasons, 20, 0) as score_multiple_reasons
    from profiles as p
    cross join thresholds as t
),

flagged as (
    select
        *,
        score_high_return_count + score_high_total_refund + score_high_avg_refund
            + score_high_approval_rate + score_multiple_reasons as anomaly_score,
        array_to_string([
            if(score_high_return_count > 0, 'high_return_count (20)', null),
            if(score_high_total_refund > 0, 'high_total_refund (25)', null),
            if(score_high_avg_refund > 0, 'high_avg_refund (20)', null),
            if(score_high_approval_rate > 0, 'high_approval_rate (15)', null),
            if(score_multiple_reasons > 0, 'multiple_reasons (20)', null)
        ], ', ') as rules_violated
    from (
        select *, if(approval_rate > 90 and total_returns >= 2, 15, 0) as score_high_approval_rate
        from scored
    )
),

briefs as (
    select
        *,
        {{ gemini(
            "concat(
                'Customer: ', customer_name, ' (ID: ', customer_id, ')\\n',
                'Segment: ', segment, ', Region: ', region, '\\n',
                '(All figures cover the last " ~ lookback_months ~ " months of returns.)\\n\\n',
                'Total Returns: ', cast(total_returns as string), '\\n',
                'Total Refund Value: $', format('%.2f', total_refund_value), '\\n',
                'Average Refund per Return: $', format('%.2f', avg_refund_per_return), '\\n',
                'Approval Rate: ', format('%.1f', approval_rate), '%\\n',
                'Distinct Return Reasons: ', cast(distinct_reason_count as string), ' (', return_reasons, ')\\n',
                'Anomaly Score: ', cast(anomaly_score as string), '/100\\n',
                'Rules Violated: ', rules_violated, '\\n\\n',
                'Write an investigation brief that:\\n',
                '1. Cites the actual numbers above (not generic statements)\\n',
                '2. Acknowledges at least one innocent explanation for the pattern\\n',
                '3. Identifies the single strongest fraud signal from the data\\n',
                '4. Recommends exactly 2 specific next actions for the investigator'
            )",
            system="You are a returns-fraud analyst at GlobalMart writing briefs for the fraud review board.
Rules:
- Use only the figures provided. Never invent transactions, dates, or amounts.
- Be balanced: an anomaly score is a reason to review, not proof of fraud.
- Answer in plain prose, 4-5 sentences, with no headings or bullet points."
        ) }} as _ai
    from flagged
    where anomaly_score >= 40
)

select
    customer_id,
    customer_name,
    segment,
    region,
    total_returns,
    total_refund_value,
    avg_refund_per_return,
    approval_rate,
    distinct_reason_count,
    return_reasons,
    anomaly_score,
    rules_violated,
    _ai.result as investigation_brief,
    nullif(_ai.status, '') as ai_status,
    current_timestamp() as generated_at
from briefs
