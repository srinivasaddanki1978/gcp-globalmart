{#-
  SCD Type 2 history of customers: the engine behind gold.dim_customers.
  Each run compares the current, deduplicated customers with the latest version
  and opens a new version when a tracked attribute changes. This table is the
  only copy of customer history: never drop or full-refresh it.

  Survivorship: every customer arrives twice
  (regional file + Region 6); the latest load wins, preferring a row with an email.
-#}
{% snapshot customers_snapshot %}
{{ config(
    unique_key='customer_id',
    strategy='check',
    check_cols=['customer_name', 'customer_email', 'segment', 'city', 'state', 'region'],
    hard_deletes='invalidate',
) }}

select customer_id, customer_name, customer_email, segment, city, state, region
from {{ ref('clean_customers') }}
qualify row_number() over (
    partition by customer_id
    order by _load_timestamp desc, if(customer_email is not null, 0, 1), _source_file
) = 1

{% endsnapshot %}
