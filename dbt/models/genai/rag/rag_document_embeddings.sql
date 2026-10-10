-- Embeddings for rag_documents, keyed by the hash of the embedded text. Incremental:
-- each build embeds only texts not embedded before, so the ~16.6k documents aren't
-- re-embedded every run. Failed embeddings are not stored and are retried next build.
-- Full refresh (dbt build --full-refresh -s rag_document_embeddings) after changing
-- the embedding endpoint.
{{ config(materialized='incremental', unique_key='embed_key', on_schema_change='fail') }}

with pending as (
    select embed_key, any_value(embed_text) as embed_text
    from {{ ref('rag_documents') }}
    {%- if is_incremental() %}
    where embed_key not in (select embed_key from {{ this }})
    {%- endif %}
    group by embed_key
),

embedded as (
    select embed_key, {{ embed('embed_text', 'RETRIEVAL_DOCUMENT') }} as embedding
    from pending
)

select
    embed_key,
    embedding,
    '{{ var("genai_embedding_endpoint") }}' as embedding_endpoint,
    current_timestamp() as embedded_at
from embedded
where array_length(embedding) > 0
