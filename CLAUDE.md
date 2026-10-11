# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

The GlobalMart Data Intelligence Platform on Google Cloud: 205 regional retail source files go through
Bronze → Silver → Gold → Metrics → GenAI in BigQuery (Python loader + dbt), with a Conversational Analytics
data agent, a Cloud Run web app, Looker Studio dashboards and Cloud Build CI/CD. The build is complete and
deployed (project `globalmart-gcp-lab`, region `us-central1`).

Known-good results live in `tests/expected_results/` (checked by `tests/check_expected_results.py`): all 205
files loaded once; reconciliation difference 0 for all 6 entities; `dim_customers` = 590 current rows;
revenue by year × region; bridge allocated refunds $2,478,124.40; fraud flag rate 22.52 % (109 of 484); the
data agent answers ≥ 9/10 test questions. Any change that moves these numbers needs a reason.

**Docs:** `docs/MANUAL_SETUP_GUIDE.md` is the learning guide that rebuilds everything by hand (console + CLI,
module by module). It mirrors `terraform/` resource for resource and IAM binding for IAM binding, so **when
you change infrastructure, update the guide's modules and appendix too.** `README.md` has the Terraform
overview; `docs/AUTOMATED_DEPLOYMENT.md` documents `scripts/deploy.sh` (one idempotent script: project,
billing, budget, Terraform bootstrap, images, data, pipeline, checks, data agent, optional GitHub CI/CD) and
`scripts/teardown.sh`; `docs/looker_studio.md` the dashboard build. Keep `deploy.sh` re-runnable: each step
must check before it creates.

**Open items:** Looker Studio pages are built by hand (then put the report URL in `dbt/models/exposures.yml`).
The Cloud Build trigger `globalmart-main` waits on the `globalmart-github` connection (us-central1) finishing
the user's GitHub OAuth; then link the repo and create the trigger with `sa-cloudbuild`. The app's Ask page
runs as `sa-app` (per-user identity would need IAP or an OAuth client). Possible extension: streaming orders
via Pub/Sub + Dataflow (cap workers at 1–2 and drain/cancel after use; no free tier).

**Don't mention other data platforms in this repo** (code, comments, docs): describe what the code does.

## Source files

`source_data/` holds the 205 input files (157 CSV, 48 JSON) and is uploaded verbatim to
`gs://<project>-globalmart-raw/source_data/` with `gcloud storage rsync -r`. Don't hand-edit them, and keep
only data files there: the loader maps files to entities by path.

- Folders `Region 1/` … `Region 6/` (names contain spaces, so quote paths) plus 4 top-level files:
  `vendors.csv`, `products.json`, `returns_2.json`, `transactions_3.csv`.
- Entity = filename prefix: `customers_*` (60), `orders_*` (48), `transactions_*` (48), `returns_*.json` (47),
  `products.json`, `vendors.csv`. Files are named by year (`_2018` … `_2026`) or number (`customers_1.csv`).
- Regional files use different column names for the same field (customer ID appears as `customer_id`,
  `customerid`, `cust_id`, `customer_identifier`). Region 4 files have city and state swapped (fixed in
  Silver by folder name). JSON files are arrays, not NDJSON.

## Architecture

```
GCS (source_data/) → Cloud Run job globalmart-loader (loader/) → BigQuery bronze (all STRING) + ops.ingest_log
  → Cloud Run job globalmart-dbt (dbt/run_dbt.py: dbt build --target prod) → silver → gold → metrics → genai (in gold)
  → Looker Studio (gold.rpt_* views) / data agent (agent/) / Cloud Run service globalmart-app (app/)
Orchestration: Cloud Workflows globalmart-e2e (workflows/globalmart_e2e.yaml, rendered by Terraform): loader, then dbt
CI/CD: cloudbuild.yaml (trigger on push to main, sa-cloudbuild): tests ‖ dbt CI → images (commit SHA) → deploy
```

- Datasets: `bronze`, `silver`, `gold`, `metrics`, `ops`, plus `silver_ci`/`gold_ci`/`metrics_ci` (3-day expiry).
- Service accounts, least privilege: `sa-loader` (write bronze/ops), `sa-dbt` (write silver/gold/metrics,
  Gemini connection), `sa-app` (read gold/metrics, data agent), `sa-workflows` (run the two jobs only),
  `sa-cloudbuild` (read prod, write `*_ci`, push, deploy).
- All infrastructure is in Terraform (`terraform/`, local state). Cloud Run images are set by CI, so Terraform
  ignores the image fields.

## Key design rules (these span several components)

- **Bronze loader** (`loader/main.py`): lower-cases headers and keys (BigQuery column names are
  case-insensitive, so `Order_ID`/`Order_id` must merge). Empty CSV fields become NULL, JSON numbers keep their
  original text (`parse_float=str`), JSON arrays become NDJSON. One load job per entity; new columns via
  `ALLOW_FIELD_ADDITION`. Idempotent: a file is already loaded if it's in `ops.ingest_log` **or** its
  `_source_file` is in Bronze (the second case backfills the log after a crash). `_source_file` is the full
  GCS path, which the Region 4 fix relies on.
- **Each Silver rule is written once**, in `dbt/macros/rules/silver_rules.sql`: per entity, its rules (name,
  field, issue_type, `fail_if`), record key and `record_data` fields. `rule_columns(entity)` generates the
  `_fail_*` columns, `_has_any_failure` and `record_data` in each `silver/staging/stg_<entity>` view;
  `silver/clean/clean_<entity>` keeps rows `where not _has_any_failure`; `silver/quarantine/rejected_records`
  loops over the same definitions. To add or change a rule, edit only that macro. `pipeline_audit_log`
  counts rejected rows as distinct `(record_data, _source_file)`; the `reconciliation_diff = 0` test enforces
  *Bronze = Silver + rejected*.
- **SQL conventions** (`dbt/macros/dialect.sql`, all behind `adapter.dispatch`): failed casts and date parses
  return NULL (`try_cast`, `try_parse_timestamp` with a format list, first match wins), so bad values are
  caught by rules, not query errors. `truncate_to_int` truncates (BigQuery's cast rounds; matters for UPCs in
  scientific notation). Money: `exact_sum()`/`exact_avg()` (BIGNUMERIC over decimal text, order-independent)
  and `round_half_up()` (2.675 → 2.68; BigQuery's float ROUND gives 2.67). `decimal_text()` writes values in
  `record_data` (doubles keep `.0`, timestamps `yyyy-MM-dd HH:mm:ss`). `is_region_4()` matches plain,
  URL-encoded and space-less folder names.
- **Keys:** `hash_key()` (FARM_FINGERPRINT of the business key); `dim_dates.date_sk` = yyyymmdd. Every
  dimension has an Unknown member (`-1`, via `unknown_member()`); facts use `coalesce(sk, -1)`, never NULL.
  Exclude `-1` when counting dimension members.
- **`dim_customers` is the only customer dimension, SCD Type 2**, built on the dbt snapshot
  `silver.customers_snapshot`, which also deduplicates (every customer arrives twice: regional file + Region 6;
  latest load wins, preferring a row with an email). **That snapshot is the only copy of customer history:
  never drop or full-refresh it.** `customer_sk` is a version key; facts join on `customer_id` and the event
  date between `valid_from`/`valid_to`, so `mv_*` views join on `customer_sk` (region as of the order). Use
  `is_current` for today's attributes. Unit tests (in `dim_customers.yml`, `fact_sales.yml`) cover it.
- **PII is masked at the Gold boundary** (`dbt/macros/pii.sql`). Silver keeps real customer names and emails
  (`clean_customers`, `customers_snapshot`, `silver.customer_pii` for authorised lookups); the app, dashboards and data
  agent have no access to the `silver` dataset. `gold.dim_customers` masks them (`BrenXXXXX`, `XXXXX@gmail.com`), so
  everything downstream inherits masked values; model-level tests on `dim_customers` and `flagged_return_customers`
  fail the build if a real name or email reaches Gold. `rejected_records.record_data` carries no emails, data-quality
  samples copied to Gold have names masked, and the fraud-brief prompt uses the customer ID, never the name. (BigQuery's
  built-in dynamic masking needs the project in an organization, which this one isn't.)
- **Gold contracts:** every Gold table has an enforced dbt contract with PK/FK constraints
  (`warn_unenforced: false`: BigQuery records but doesn't enforce them; `unique`/`relationships` tests do).
  Types must match exactly. `fact_sales` grain is `(order_id, product_id, line_seq)` (the source repeats
  order/product pairs); the bridge grain is `(return_sk, sales_sk)`. `profit` is FLOAT64 in Gold (STRING in
  the source).
- **GenAI runs in SQL inside dbt** (`models/genai`, tag `genai`, written to `gold`) via `macros/genai.sql`:
  `gemini(prompt, system=...)` wraps `AI.GENERATE` (fixed rules in the system instruction, row data in the
  prompt); `embed()` wraps `AI.EMBED`. Model, connection and embedding endpoint are vars in `dbt_project.yml`;
  model names change, so confirm them. Rankings and KPIs are computed in SQL and only passed to the model;
  Gemini runs only on bounded rows (UC2: flagged customers only). Each AI model has an `ai_status` column; NULL
  AI text is a dbt *warning*. UC3: `rag_documents` → `rag_document_embeddings` (**incremental**, keyed by the
  hash of the embedded text; `--full-refresh` it after changing the embedding endpoint) → `rag_index`
  (VECTOR_SEARCH needs a plain table, not a join) → `rag_query_history` (questions in `seeds/rag_test_questions.csv`).
- **dbt targets:** `dev`/`prod` write the real datasets; `ci` appends `_ci` (`generate_schema_name`) and is only
  for `state:modified+ --defer` builds. The prod manifest (`gs://…-raw/dbt_state/prod/manifest.json`) is saved by
  the dbt job after each successful `--target prod` build.
- **One YAML file per model**, next to its `.sql`: descriptions, contract, tests, unit tests. Descriptions are
  persisted to BigQuery for the data agent.
- **Consumers:** the data agent (`agent/agent_context.yaml`) reads 20 gold/metrics tables using BigQuery column
  descriptions plus its instructions; keep its join rules in sync with Gold and rerun its `test`. Looker Studio
  charts each read one `gold.rpt_*` view (`models/reporting/`). Both, and the app, are in `dbt/models/exposures.yml`.
- **Filters and YoY (app + dashboards):** `gold.rpt_sales_lines`, `rpt_return_lines` and `rpt_return_product_lines`
  are wide views carrying every filterable attribute; `gold.rpt_period_months` encodes the like-for-like rule once
  (per year × period FY/Q1–Q4/YTD × month: `in_period`, `has_data`, `comparable` = data in this and the prior
  year). Every YoY query sums current values over in-period months, compares only `comparable` months, and returns
  NULL YoY when fewer than half the months compare (2017 vs 2016 overlaps in October only; 2026 runs Jan–Sep). The
  test `tests/assert_yoy_regions_add_up.sql` checks regional revenue sums to the total.
- **App (`app/`):** the server runs only `app/queries/*.sql` (allowlist). Each declares `-- @param name INT64` (or
  `-- @param period STRING FY|Q1|Q2|Q3|Q4|YTD` for an enumeration) and uses BigQuery `@name` parameters. Filters
  use `'All'` for no filter. The client sends one filter object (kept in the URL by `client/src/lib/filters.ts`)
  to every query; the server ignores filter names a query doesn't declare (`FILTER_PARAMS`) and rejects any other
  unknown or mistyped parameter (400); 1 GiB cap per query; 5-minute
  cache. Pages render `components/FilterBar` (global filters + page filters) and
  `Kpi` cards with `yoyDelta()`; comparison charts pass `labels`/`dashed` so the prior year is grey. Pages import
  from `client/src/lib/components.ts` (data hook `useAnalyticsQuery`, Recharts charts with
  `queryKey`/`xKey`/`yKey` props, Tailwind UI); extend that layer rather than editing every page. Chart
  animations are off (headless screenshots need it). Cloud Run requires authentication; queries and the Ask page
  run as `sa-app`; the caller's email comes from the signature-stripped ID token (`server/identity.ts`). After
  changing Gold columns run `npm run check:queries`. When joining `dim_customers` on `customer_id`, add
  `AND is_current`.

## Commands

Local tools are installed per user (`/opt/homebrew` belongs to another macOS user): Google Cloud CLI in
`~/google-cloud-sdk/bin`, Terraform in `~/.local/bin`, Python tools in the repo's `.venv`. Non-interactive shells
don't load `~/.zshrc`, so begin commands with `export PATH="$HOME/google-cloud-sdk/bin:$HOME/.local/bin:$PATH"`.
Sign-in is user OAuth + ADC (quota project `globalmart-gcp-lab`). Local tools read `GCP_PROJECT`
(default `globalmart-gcp-lab`).

```bash
# Infrastructure
cd terraform && terraform plan && terraform apply

# dbt (run from dbt/; profiles.yml is in the project, so pass --profiles-dir .)
cd dbt
../.venv/bin/dbt build --profiles-dir . --select <model>         # build and test one model
../.venv/bin/dbt build --profiles-dir . --select source:bronze+   # everything downstream of Bronze
../.venv/bin/dbt build --profiles-dir . --select tag:genai       # GenAI layer only
../.venv/bin/dbt test --profiles-dir . --select test_type:unit   # unit tests
../.venv/bin/dbt build --profiles-dir . --target prod            # full build (what the Cloud Run job runs)
# dbt CI locally: changed models + downstream into *_ci, unchanged upstream read from prod
gcloud storage cp gs://globalmart-gcp-lab-globalmart-raw/dbt_state/prod/manifest.json /tmp/prod-state/
../.venv/bin/dbt build --profiles-dir . --target ci --select state:modified+ --defer --state /tmp/prod-state

# Loader
cd loader && ../.venv/bin/python -m pytest -q                    # single test: -k <name>
GOOGLE_CLOUD_PROJECT=globalmart-gcp-lab ../.venv/bin/python main.py [--dry-run]

# Pipeline
gcloud workflows run globalmart-e2e --location=us-central1      # loader → dbt (~8 min)
gcloud run jobs execute globalmart-dbt --region=us-central1 --wait [--args="build,--target,prod,--select,metrics"]
gcloud storage ls gs://globalmart-gcp-lab-globalmart-raw/dbt_runs/   # run history
gcloud storage rsync -r source_data gs://globalmart-gcp-lab-globalmart-raw/source_data

# Expected results (after a full run; exit 1 on any difference)
.venv/bin/python tests/check_expected_results.py [--only q06_revenue_by_year_region]

# Data agent (Conversational Analytics API, location global)
.venv/bin/python agent/data_agent.py deploy | ask "question" | test [--only q03_...] | delete

# App
cd app && npm ci
npm run dev              # server :8080 (tsx watch) + Vite :5173 with /api proxy; uses your ADC
npm test && npm run typecheck && npm run build
npm run check:queries    # dry-run all 27 queries (CI contract check)
gcloud run services proxy globalmart-app --region=us-central1 --port=8080   # open the deployed app
```

**CI/CD:** push to `main` → `cloudbuild.yaml` (tests in parallel: loader pytest; app vitest, typecheck and
check:queries; dbt CI → images tagged with the commit SHA → deploy app + point both jobs at the new images). Don't
hand-build `:latest` for production; push to main. Manual run:
`gcloud builds submit --config=cloudbuild.yaml --region=us-central1 --service-account=projects/globalmart-gcp-lab/serviceAccounts/sa-cloudbuild@globalmart-gcp-lab.iam.gserviceaccount.com`.

## Cost guardrails

Personal lab with a ~US$10/month budget alert. No always-on services (no Composer); BigQuery on-demand; the app
scales to zero; Gemini only on bounded rows; RAG embeddings incremental.
