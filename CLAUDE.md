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
Orchestration: Cloud Workflows `globalmart-e2e` runs the loader job, then the dbt job (Cloud Scheduler is optional)
```

- Project `globalmart-gcp-lab`, region `us-central1`. BigQuery datasets: `bronze`, `silver`, `gold`, `metrics`, `ops`.
- Service accounts: `sa-loader` and `sa-dbt` can write to their own datasets. `sa-app` has read-only access to `gold`.
- All infrastructure is defined in Terraform. CI/CD runs on Cloud Build.

## Key design rules (these span several components)

- **Bronze is all STRING.** The source JSON files are JSON *arrays*, so the loader converts them to NDJSON. Regional files use different names for the same column (for example `customer_id`, `CustomerID`, `cust_id`, `customer_identifier`). Staging models harmonise them with `COALESCE` and cast every type explicitly. This is the most likely cause of parity differences.
- **The loader is idempotent.** It skips files already recorded in `ops.ingest_log`, so a second run must load nothing. It adds `_source_file` (the full GCS path, which the Region 4 city/state fix relies on) and `_load_timestamp`.
- **Each Silver rule is written once** in `dbt/macros/rules/`, as a list of name, field, issue type and `fail_if` condition. The same macros generate both `silver.clean_<entity>` and `silver.rejected_records`. Wrap every condition in `coalesce(..., false)`. The invariant *Bronze = Silver + rejected* is tested through `pipeline_audit_log.reconciliation_diff = 0`.
- **Surrogate keys** come from a `FARM_FINGERPRINT(business_key)` macro. Every dimension has an Unknown member row (`-1`). Parity checks compare business keys, never hash keys.
- **Gold tables use enforced dbt contracts** with `primary_key`/`foreign_key` constraints, grain tests and `relationships` tests. Turn on `persist_docs` so the data agent can read the descriptions. Customers use SCD Type 1 for parity, plus SCD Type 2 (a backfill model and a dbt snapshot).
- **GenAI runs in SQL inside dbt models** (`AI.GENERATE`, `ML.GENERATE_EMBEDDING`, `VECTOR_SEARCH` through a Vertex AI connection), tagged `genai`. To control cost, only send aggregates or flagged customers to Gemini.
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
../.venv/bin/dbt build --profiles-dir . --select tag:genai       # GenAI layer only
../.venv/bin/dbt build --profiles-dir . --target prod            # full build (Cloud Run job)

# Re-upload source files (idempotent)
gcloud storage rsync -r source_data gs://globalmart-gcp-lab-globalmart-raw/source_data

# Refresh the Databricks answer key (read-only; Free Edition serverless warehouse)
python3.12 parity/run_databricks_baseline.py --profile free --warehouse-id 244af7e3ec6e128d
```

Later phases add `gcloud workflows run globalmart-e2e` (end to end) and `dbt build --select state:modified+` (CI).

## Parity answer key

`parity/baseline_results/*.csv` holds the Databricks results, one file for each `-- qNN_name:` block in `parity/databricks_baseline.sql`; `bigquery_parity.sql` should run the same queries. Key numbers: 205 files; Bronze customers 1,180, orders 53,750, transactions 101,624, returns 8,506, products 1,774, vendors 7. Rejected rows: orders 2,539, returns 638, transactions 2,789. Only 5 rules have any failures. `dim_customers` 590, `fact_sales` 94,153, `fact_returns` 7,868. The fraud flag rate is 22.52% (109 of 484). Allocated refunds in the bridge table exceed actual refunds by $0.32 because each line is rounded.

## Cost guardrails

This is a personal lab with a US$10/month budget. Don't add Cloud Composer or any other always-on service. BigQuery stays on-demand, and the app runs with minimum 0 instances. If Dataflow is used (Phase 9), cap the workers, and always drain and cancel the job after a demo.

GCP and dbt product names change often. Check the current names (for example the Gemini Flash model ID and the Conversational Analytics features) before using them.
