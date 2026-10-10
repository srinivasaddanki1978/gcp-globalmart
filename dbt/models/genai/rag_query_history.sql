-- UC3 product RAG: answer each test question (seeds/rag_test_questions.csv) from
-- retrieved documents. Retrieval: top 5 summary/ranked docs plus top
-- 5 detail docs by cosine similarity; when the question names a region, only that
-- region's docs and region-neutral docs are eligible (search 250 deep, then filter).
{%- set k = 5 %}

with questions as (
    select
        question,
        regexp_extract(question, r'\b(East|West|South|Central|North)\b') as region,
        {{ embed('question', 'RETRIEVAL_QUERY') }} as q_embedding
    from {{ ref('rag_test_questions') }}
),

hits as (
    {%- for pool in ['summary', 'detail'] %}
    select
        query.question,
        query.region,
        '{{ pool }}' as pool,
        base.doc_text,
        base.doc_region,
        1 - distance as similarity
    from vector_search(
        (select * from {{ ref('rag_index') }} where pool = '{{ pool }}'),
        'embedding',
        (select question, region, q_embedding from questions),
        'q_embedding',
        top_k => {{ k * 50 }},
        distance_type => 'COSINE'
    )
    {{ "union all" if not loop.last }}
    {%- endfor %}
),

top_hits as (
    select *
    from hits
    where region is null or doc_region is null or doc_region = region
    qualify row_number() over (partition by question, pool order by similarity desc) <= {{ k }}
),

contexts as (
    select
        question,
        array_agg(doc_text order by if(pool = 'summary', 0, 1), similarity desc) as docs,
        max(similarity) as top_similarity
    from top_hits
    group by question
),

answered as (
    select
        c.*,
        {{ gemini(
            "concat('Retrieved documents:\\n',
                array_to_string(array(select concat('Document ', cast(i + 1 as string), ': ', d)
                                      from unnest(c.docs) as d with offset as i order by i), '\\n\\n'),
                '\\n\\nQuestion: ', c.question)",
            system="You are a product intelligence assistant for GlobalMart, a US retail chain.
Rules:
- Answer using ONLY the retrieved documents. If they do not contain the answer, reply exactly:
  \"This information is not available in the current data.\"
- Cite the actual numbers from the documents.
- A vendor is a supplier (e.g. \"Seaborne Ltd.\"); a brand is a product label. Never treat a brand as a vendor.
- For \"top / highest / lowest\" questions, use the pre-ranked documents (titles start with \"Top\", \"ranked\", etc.).
  Never build a ranking yourself from individual Product or Product-Region documents; they are only a sample.
  If no matching ranked document was retrieved, say the information is not available.
- Keep the answer short; a small markdown table is fine for lists."
        ) }} as _ai
    from contexts as c
)

select
    question,
    _ai.result as answer,
    to_json_string(docs) as retrieved_documents,
    array_length(docs) as retrieved_count,
    round(top_similarity, 4) as top_similarity,
    nullif(_ai.status, '') as ai_status,
    current_timestamp() as generated_at
from answered
