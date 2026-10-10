-- Search table for VECTOR_SEARCH: current documents with their embeddings.
-- VECTOR_SEARCH needs a plain table (optionally filtered) as its base, not a join.
select d.doc_id, d.pool, d.doc_region, d.doc_text, e.embedding
from {{ ref('rag_documents') }} as d
inner join {{ ref('rag_document_embeddings') }} as e on d.embed_key = e.embed_key
