-- Real customer names and emails (current version), for authorised lookups only.
-- Lives in silver, which the app, dashboards and data agent can't read; gold holds masked values.
select customer_id, customer_name, customer_email, segment, region
from {{ ref('customers_snapshot') }}
where dbt_valid_to is null
