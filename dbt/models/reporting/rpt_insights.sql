-- "Data Quality & AI" page: AI executive summaries.
select insight_type, executive_summary, generated_at
from {{ ref('ai_business_insights') }}
