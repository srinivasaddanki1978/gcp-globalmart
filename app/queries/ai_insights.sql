-- LLM executive summaries, one per business domain.
-- Source: gold.ai_business_insights (written by uc4_executive_intel)
SELECT
  insight_type,
  executive_summary,
  CAST(generated_at AS STRING) AS generated_at
FROM gold.ai_business_insights
ORDER BY insight_type
