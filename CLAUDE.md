# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Current state

The repo is at the planning stage: it only contains `GLOBALMART_GCP_PLAN.md`, the agreed implementation plan (v2). **Read it before starting any phase.** It defines the phases, the checklists, the "done when" criteria and the parity targets. Tick the phase checklists in the plan as work is completed.

Note: the plan's repository layout assumes a `gcp/` folder inside the `databricks-globalmart` repo. This repo (`gcp-globalmart`) is standalone, so place those folders (`terraform/`, `loader/`, `dbt/`, `workflows/`, `parity/`, `dataflow/`, `app/`, plus `source_data/`) at the repo root unless the user says otherwise. The plan lists where to push as an open question.

## Source files

The 205 source files are committed in this repo under `source_data/`, so anyone who clones it gets them. They're a verbatim copy of `databricks-globalmart/globalmart/bronze/volumes/source_data`, where `scripts/generate_source_data.py` (seed 2026) generates the synthetic files; don't hand-edit them here. Keep only data files in `source_data/`, because it's uploaded verbatim to `gs://<project>-globalmart-raw/source_data/` with `gcloud storage rsync -r`, and the loader maps files to entities by path.

- There are 205 files in total: 157 CSV and 48 JSON. They sit in `Region 1/` to `Region 6/` (the folder names contain spaces, so quote the paths), plus 4 files at the top level: `vendors.csv`, `products.json`, `returns_2.json` and `transactions_3.csv`.
- The loader maps each file to an entity by its filename prefix: `customers_*` (60 files), `orders_*` (48), `transactions_*` (48), `returns_*.json` (47), `products.json` and `vendors.csv`. Files are named either by year (`<entity>_2018` … `_2026`) or by number (`<entity>_<n>`, for example `customers_1.csv`).

## What this project is

A rebuild of the GlobalMart Data Intelligence Platform (originally on Databricks) on native Google Cloud, using the same source files and warehouse design. The end goal is a side-by-side parity comparison (*one warehouse design, two platforms*). Matching the Databricks numbers is the main measure of success. See the parity targets in section 1 of the plan, for example `dim_customers` = 590 rows, a fraud flag rate of about 22% (22.52%), and a reconciliation difference of 0 for all 6 entities.

## Architecture (planned)

```
GCS bucket (source_data/) → Cloud Run job: Python Bronze loader → BigQuery `bronze` (all STRING)
  → Cloud Run job: dbt build → `silver` → `gold` → `metrics` → genai models (in `gold`)
  → Looker Studio / Conversational Analytics data agent / Cloud Run app (React + Express)
Orchestration: Cloud Workflows `globalmart-e2e` (workflows/globalmart_e2e.yaml, rendered by Terraform) runs Cloud Run job `globalmart-loader`, then `globalmart-dbt` (dbt/run_dbt.py: `dbt build --target prod`, uploads run_results.json, exits with dbt's code)
```

- Project `globalmart-gcp-lab`, region `us-central1`. BigQuery datasets: `bronze`, `silver`, `gold`, `metrics`, `ops`.
- Service accounts: `sa-loader` and `sa-dbt` can write to their own datasets. `sa-app` has read-only access to `gold`. `sa-workflows` may only run the two jobs.
- All infrastructure is defined in Terraform. CI/CD runs on Cloud Build.

## Key design rules (these span several components)

- **Bronze loader** (`loader/main.py`) matches Databricks Bronze exactly; `parity/compare_bronze.py` checks this. It lower-cases headers and keys (BigQuery column names are case-insensitive, so `Order_ID`/`Order_id` must merge). Empty CSV fields become NULL, and JSON numbers keep their original text (`parse_float=str`). It runs one load job per entity, and adds new columns with `ALLOW_FIELD_ADDITION`. A file counts as already loaded if it's in `ops.ingest_log` **or** its `_source_file` is already in Bronze; the second case backfills the log after a crash.

- **Bronze is all STRING.** The source JSON files are JSON *arrays*, so the loader converts them to NDJSON. Regional files use different names for the same column (for example `customer_id`, `CustomerID`, `cust_id`, `customer_identifier`). Staging models harmonise them with `COALESCE` and cast every type explicitly. This is the most likely cause of parity differences.
- **The loader is idempotent.** It skips files already recorded in `ops.ingest_log`, so a second run must load nothing. It adds `_source_file` (the full GCS path, which the Region 4 city/state fix relies on) and `_load_timestamp`.
- **Each Silver rule is written once**, in `dbt/macros/rules/silver_rules.sql`. One definition per entity lists its rules (name, field, issue_type, `fail_if`), its record key and its `record_data` fields. `rule_columns(entity)` turns them into the `_fail_*` columns, `_has_any_failure` and `record_data` in each `silver/staging/stg_<entity>` view. `silver/clean/clean_<entity>` keeps rows `where not _has_any_failure`, and `silver/quarantine/rejected_records` loops over the same definitions. To add or change a rule, edit only that macro. `pipeline_audit_log` counts rejected rows as distinct `(record_data, _source_file)`, and the `reconciliation_diff = 0` test enforces *Bronze = Silver + rejected*.
- **Copy Spark's behaviour, not BigQuery's defaults.** The goal is matching Databricks results, so follow Spark's non-ANSI semantics: failed casts and parses return NULL (`try_cast`, `try_parse_timestamp` with a list of formats, first match wins). A double-to-long cast truncates (`truncate_to_int`). In `record_data`, doubles keep a trailing `.0` and timestamps print as `yyyy-MM-dd HH:mm:ss` (`spark_string`). All platform-specific SQL lives in `dbt/macros/dialect.sql` behind `adapter.dispatch`. Databricks `_source_file` is URL-encoded (`Region%201/...`) and GCS paths keep the space; `is_region_4()` accepts both.
- **Surrogate keys** come from `hash_key()` (FARM_FINGERPRINT of the business key). `dim_dates.date_sk` is the integer yyyymmdd. Every dimension has an Unknown member (`-1`, added by `unknown_member()`), and facts use `coalesce(sk, -1)`, never NULL. Parity checks compare business columns and exclude `-1` rows; BigQuery's `-1` count must equal Databricks' NULL-key count.
- **`dim_customers` is the only customer dimension, and it's SCD Type 2.** It's built on the dbt snapshot `silver.customers_snapshot`, which also deduplicates: every customer arrives twice (regional file + Region 6), the latest load wins, preferring a row with an email. **That snapshot is the only copy of customer history: never drop or full-refresh it.** `customer_sk` is a version key. Facts join on `customer_id` and the event date between `valid_from` and `valid_to`, so `mv_*` views join on `customer_sk` (region as of the order). Use `is_current` for today's attributes. Unit tests with mock rows (in `dim_customers.yml` and `fact_sales.yml`) cover the version logic.
- **Gold tables use enforced dbt contracts**, with PK/FK constraints marked `warn_unenforced: false`; BigQuery records them but doesn't enforce them, and the `unique`/`relationships` tests do. Data types must match exactly (int64, float64, string, date, timestamp, bool). `fact_sales` grain is `(order_id, product_id, line_seq)`, because the source repeats order/product pairs; the bridge grain is `(return_sk, sales_sk)`. Money totals use `exact_sum()` (BIGNUMERIC, order-independent) and `spark_round()` (half-up on decimal text, as in Spark), which is why some `mv_*` rows differ from Databricks by one cent: Databricks rounds inexact float sums.
- **One YAML file per model,** next to its `.sql`, holding descriptions, contract, tests and any unit tests. Descriptions are persisted to BigQuery for the data agent.
- **GenAI runs in SQL inside dbt models** (`models/genai`, tag `genai`, written to `gold`). Every call goes through `macros/genai.sql`: `gemini(prompt, system=...)` wraps `AI.GENERATE`, with the fixed rules in the system instruction and the row data in the prompt. `embed()` wraps `AI.EMBED`. Model, connection and embedding endpoint are dbt vars in `dbt_project.yml`; confirm the names at each phase. Ranking and KPIs are computed in SQL and only passed to the model. Gemini is called only for bounded rows (UC2: flagged customers only). Each AI model keeps an `ai_status` column, and NULL AI text is a dbt *warning*. UC3: `rag_documents` → `rag_document_embeddings` (**incremental**, keyed by the hash of the embedded text; `--full-refresh` it after changing the embedding endpoint) → `rag_index` (VECTOR_SEARCH needs a plain table, not a join) → `rag_query_history` (questions come from `seeds/rag_test_questions.csv`).
- **Keep dialect-specific SQL in a few `adapter.dispatch` macros** from the start, so the same dbt project can target Databricks later (Phase 10).
- **App queries** are files on an allowlist of `.sql` files and use BigQuery named parameters (`@param`). CI dry-runs every app query, so a breaking change in Gold fails the build.

## Commands

Tools are installed per user, not through Homebrew (`/opt/homebrew` belongs to another macOS user): the Google Cloud CLI in `~/google-cloud-sdk/bin`, Terraform in `~/.local/bin`, and dbt in the repo's `.venv`. Non-interactive shells don't load `~/.zshrc`, so begin each command with `export PATH="$HOME/google-cloud-sdk/bin:$HOME/.local/bin:$PATH"`.

The project is `globalmart-gcp-lab` with account `asrinivasbe@gmail.com`. Login uses user OAuth and application default credentials (ADC), with the ADC quota project set to `globalmart-gcp-lab`.

```bash
# Infrastructure (local state in terraform/; terraform.tfvars is gitignored)
cd terraform && terraform plan && terraform apply

# dbt: run from dbt/; profiles.yml lives in the project, so pass --profiles-dir .
cd dbt
../.venv/bin/dbt debug --profiles-dir .
../.venv/bin/dbt build --profiles-dir . --select <model>         # build and test one model
../.venv/bin/dbt build --profiles-dir . --select source:bronze+   # everything downstream of Bronze
../.venv/bin/dbt build --profiles-dir . --select tag:genai       # GenAI layer only
../.venv/bin/dbt test --profiles-dir . --select test_type:unit   # unit tests (mock-data logic checks)
../.venv/bin/dbt build --profiles-dir . --target prod            # full build (Cloud Run job)

# Bronze loader (loader/main.py): tests, local run, image build, Cloud Run job
cd loader && ../.venv/bin/python -m pytest -q                        # single test: -k <name>
GOOGLE_CLOUD_PROJECT=globalmart-gcp-lab ../.venv/bin/python main.py [--dry-run]
gcloud builds submit loader --region=us-central1 \
  --tag us-central1-docker.pkg.dev/globalmart-gcp-lab/globalmart/loader:latest   # no local Docker
gcloud run jobs execute globalmart-loader --region=us-central1 --wait

# Parity vs Databricks (exit 1 on any difference)
.venv/bin/python parity/compare_bronze.py --warehouse-id 244af7e3ec6e128d   # per-column profile of raw_*
.venv/bin/python parity/compare_silver.py --warehouse-id 244af7e3ec6e128d   # audit log, rejected rows, clean profiles
.venv/bin/python parity/compare_gold.py --warehouse-id 244af7e3ec6e128d     # every Gold + metrics table, row level
.venv/bin/python parity/compare_genai.py --warehouse-id 244af7e3ec6e128d    # GenAI: counts, UC2 scores, UC4 KPI JSON

# Re-upload source files (idempotent)
gcloud storage rsync -r source_data gs://globalmart-gcp-lab-globalmart-raw/source_data

# Refresh the Databricks answer key (read-only; Free Edition serverless warehouse)
python3.12 parity/run_databricks_baseline.py --profile free --warehouse-id 244af7e3ec6e128d
```

```bash
# End to end: Cloud Workflows runs the loader job, then the dbt job (about 7 min)
gcloud workflows run globalmart-e2e --location=us-central1

# dbt image (rebuild after any dbt change, or the Cloud Run job keeps running the old code)
gcloud builds submit dbt --region=us-central1 \
  --tag us-central1-docker.pkg.dev/globalmart-gcp-lab/globalmart/dbt:latest
gcloud run jobs execute globalmart-dbt --region=us-central1 --wait [--args="build,--select,metrics"]
gcloud storage ls gs://globalmart-gcp-lab-globalmart-raw/dbt_runs/     # run history (run_results.json per run)
```

Phase 8 adds `dbt build --select state:modified+` (CI).

## Parity answer key

`parity/baseline_results/*.csv` holds the Databricks results, one file for each `-- qNN_name:` block in `parity/databricks_baseline.sql`; `bigquery_parity.sql` should run the same queries. Key numbers: 205 files; Bronze customers 1,180, orders 53,750, transactions 101,624, returns 8,506, products 1,774, vendors 7. Rejected rows: orders 2,539, returns 638, transactions 2,789. Only 5 rules have any failures. `dim_customers` 590, `fact_sales` 94,153, `fact_returns` 7,868. The fraud flag rate is 22.52% (109 of 484). Allocated refunds in the bridge table exceed actual refunds by $0.32 because each line is rounded.

## Cost guardrails

This is a personal lab with a US$10/month budget. Don't add Cloud Composer or any other always-on service. BigQuery stays on-demand, and the app runs with minimum 0 instances. If Dataflow is used (Phase 9), cap the workers, and always drain and cancel the job after a demo.

GCP and dbt product names change often. Check the current names (for example the Gemini Flash model ID and the Conversational Analytics features) before using them.
