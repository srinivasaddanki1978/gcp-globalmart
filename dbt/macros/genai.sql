{#-
  GenAI helpers: every Gemini / embedding call goes through these, so the model,
  connection and request settings live in one place (vars in dbt_project.yml).
  BigQuery-specific (AI.GENERATE / AI.EMBED), dispatched per adapter.
-#}

{% macro vertex_connection() -%}
    '{{ target.project }}.{{ var("genai_connection") }}'
{%- endmacro %}


{#- AI.GENERATE call returning STRUCT<result STRING, full_response JSON, status STRING>.
    `system` is the system instruction (fixed rules); `prompt` is a SQL expression
    carrying the row data. Select `.result` for the text and keep `.status` for errors. -#}
{% macro gemini(prompt, system=none) -%}
    ai.generate(
        {{ prompt }},
        connection_id => {{ vertex_connection() }},
        endpoint => '{{ var("genai_endpoint") }}'
        {%- if system %},
        model_params => json r'''{{ {"systemInstruction": {"parts": [{"text": system | trim}]}} | tojson }}'''
        {%- endif %}
    )
{%- endmacro %}


{#- AI.EMBED returning ARRAY<FLOAT64>. task_type: RETRIEVAL_DOCUMENT for stored
    documents, RETRIEVAL_QUERY for questions. -#}
{% macro embed(content, task_type) -%}
    ai.embed(
        {{ content }},
        endpoint => '{{ var("genai_embedding_endpoint") }}',
        task_type => '{{ task_type }}',
        connection_id => {{ vertex_connection() }}
    ).result
{%- endmacro %}


{#- $1,234.56 (thousands separators, 2 decimals). -#}
{% macro money(expr) -%}
    concat('$', format("%'.2f", coalesce(cast({{ expr }} as float64), 0)))
{%- endmacro %}
