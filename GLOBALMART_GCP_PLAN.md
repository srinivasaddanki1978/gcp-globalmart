# GlobalMart on Google Cloud: Implementation Plan (v2)

**Status:** Agreed direction, ready to start · **Start:** 10 October 2026 · **Owner:** Srinivas Addanki

**What changed from v1:** dbt Core replaces Dataform for transformations. Cloud Workflows is the single trigger, with no Dataform scheduling. Dataflow is added as an optional streaming phase. A stretch phase runs the same dbt project on Databricks.

## 1. Goal

Rebuild the GlobalMart Data Intelligence Platform on **native Google Cloud services**, with the same source files and warehouse design as the Databricks version. Along the way, implement the "what I would change before production" list from the LinkedIn article. Finish with a side-by-side comparison for a follow-up article: *one warehouse design, two platforms*.

### Final technology decisions

| Layer | Choice | Why | Not chosen, and why |
|---|---|---|---|
| Account | Personal Google Cloud account | Lab, kept within free tiers | Bilvantis account, not needed for a lab |
| File ingestion (Bronze) | **Python loader as a Cloud Run job** | Handles JSON arrays, mixed column names and a "load only new files" log. Costs pennies and starts in seconds | **Dataflow**: works, but its VMs take minutes to start and it has no free tier. Too heavy for about 205 small files |
| Transformations (Silver → Metrics → GenAI) | **dbt Core** (`dbt-bigquery`) as a **Cloud Run job** | Model contracts, built-in snapshots for SCD Type 2, rich tests, and the same project can also target Databricks and Snowflake. It is also a new skill beyond the Dataform used on Worldline | **Dataform**: simpler and BigQuery-only, but no contracts or snapshots and no portability |
| Orchestration | **Cloud Workflows** (+ Cloud Scheduler if we want a daily run) | One trigger: loader → dbt, each step waits for the previous one. Nearly free | **Cloud Composer**: bills all the time even when idle. **Dataform schedule**: can't run the loader first |
| Streaming | **Dataflow** (optional Phase 9) | The right tool when data arrives as events and must be validated or windowed in flight | **Pub/Sub → BigQuery subscription**: fine for plain landing, but no in-flight logic |
| Storage and compute | BigQuery (on-demand) + Cloud Storage | Free tier covers this data size | — |
| AI | Gemini on Vertex AI, called from SQL (`AI.GENERATE`, `ML.GENERATE_EMBEDDING`, `VECTOR_SEARCH`) | Keeps all AI steps inside dbt models | Separate notebooks: not needed |
| Data quality monitoring | dbt tests + Dataplex data quality scans | dbt blocks bad builds; Dataplex monitors over time | — |
| BI | Looker Studio | Free | Looker: a paid licence |
| Natural-language Q&A | Conversational Analytics data agent | GCP equivalent of Genie | — |
| App | Cloud Run service (React + Express) + Conversational Analytics API | GCP equivalent of the AppKit app | — |
| Infrastructure as code | Terraform + Cloud Build | Standard on GCP | — |

### How we will know it worked (parity targets)

1. All 205 source files are loaded, and each file is loaded only once.
2. All 23 quality rules are ported, and *Bronze = Silver + rejected* holds for all 6 entities (reconciliation difference = 0). Only 5 rules have failures in the current data; their counts are in `parity/baseline_results/q04_failures_per_rule.csv`.
3. `dim_customers` has **590** rows (from 1,180 raw). The earlier 374 (from 748) predates the synthetic 2018–2026 files.
4. Revenue by year × region matches the Databricks baseline, within rounding.
5. Bridge `allocated_refund` totals match refunds, within cents.
6. The fraud flag rate is about **22%** (12-month window, P85 thresholds, score ≥ 40).
7. The data agent answers at least 9 of 10 test questions correctly, with the SQL checked.
8. One command runs the whole pipeline, and the monthly cost stays under the budget alert.

## 2. Target architecture

```
Source files ──► Cloud Storage bucket
                     │
                     ▼
        Cloud Run job: Bronze loader (Python)        ◄── "Auto Loader" equivalent
        (JSON array → NDJSON, all STRING, ops.ingest_log)
                     │
                     ▼
        Cloud Run job: dbt build                      ◄── "Lakeflow Declarative Pipelines" equivalent
        silver → gold → metrics → genai (+ tests, snapshots)
                     │
        ┌────────────┼──────────────────┬───────────────────────┐
        ▼            ▼                  ▼                       ▼
  Looker Studio   Data agent       Cloud Run app          Dataplex DQ scans
                (Conv. Analytics)  (React + Express)

  Cloud Scheduler (optional) ─► Cloud Workflows: run loader ─► run dbt ─► report status

  Optional Phase 9: event replayer ─► Pub/Sub ─► Dataflow (streaming) ─► bronze.raw_orders_stream
```

| Databricks component | GCP replacement |
|---|---|
| Volume `source_data` | Cloud Storage bucket (`us-central1`) |
| Auto Loader | Python loader as a Cloud Run job + `ops.ingest_log` |
| Catalog `globalmart` + schemas | Project + BigQuery datasets `bronze`, `silver`, `gold`, `metrics`, `ops` |
| Lakeflow Declarative Pipelines | dbt models, with dependencies from `ref()` |
| Expectations | dbt tests + the `_fail_*` rule columns + Dataplex scans |
| `monotonically_increasing_id()` | `FARM_FINGERPRINT(business_key)` macro: stable keys **(improvement)** |
| SCD Type 1 customers | SCD Type 1 for parity + SCD Type 2 (backfill model + dbt snapshot) **(improvement)** |
| Informational PK/FK | dbt contracts with `primary_key` / `foreign_key` constraints (not enforced in BigQuery) **(improvement)** |
| Lakeflow Jobs | Cloud Workflows calling two Cloud Run jobs |
| `ai_query()`, Model Serving | `AI.GENERATE` with Gemini |
| FAISS + MiniLM | `ML.GENERATE_EMBEDDING` + `VECTOR_SEARCH` |
| AI/BI dashboard | Looker Studio |
| Genie space | Conversational Analytics data agent |
| AppKit app | Cloud Run service + Conversational Analytics API |
| Bundle | Terraform + Cloud Build |

### What we found in the source files

- **The JSON files are JSON arrays**, not newline-delimited JSON, so BigQuery can't load them directly. The loader converts them first.
- The regional files use **different column names for the same field**. Customer ID, for example, appears as `customer_id`, `CustomerID`, `cust_id` and `customer_identifier`. Bronze keeps every column as `STRING`, and Silver harmonises them with `COALESCE`.
- Databricks used `inferSchema`, but BigQuery Bronze is all STRING, so Silver must cast every type explicitly. This is the most likely source of parity differences.
- Region 4's city/state swap is fixed by folder name, so `_source_file` keeps the full GCS path.

## 3. Repository layout

```
databricks-globalmart/
└── gcp/
    ├── GLOBALMART_GCP_PLAN.md
    ├── parity/
    │   ├── databricks_baseline.sql        ← run in Databricks first
    │   └── bigquery_parity.sql
    ├── terraform/                         ← APIs, bucket, datasets, SAs, IAM, Vertex connection,
    │                                         Artifact Registry, Cloud Run jobs, Workflows, budget
    ├── loader/                            ← Bronze loader (Python) + Dockerfile
    ├── dbt/
    │   ├── dbt_project.yml
    │   ├── profiles.yml                   ← method: oauth (local login / Cloud Run service account)
    │   ├── Dockerfile
    │   ├── macros/rules/                  ← each Silver rule written ONCE
    │   ├── models/{staging,silver,gold,metrics,genai}/
    │   ├── snapshots/customers_snapshot.yml
    │   └── models/exposures.yml           ← Looker Studio report + Cloud Run app
    ├── workflows/globalmart_e2e.yaml
    ├── dataflow/                          ← optional Phase 9 (Apache Beam, Python)
    └── app/                               ← Cloud Run app
```

## 4. Phases

Each session is about 3 hours. The core build (Phases 0–8) is about **14–16 sessions**. Phase 9 adds 2 and Phase 10 adds 2–3.

### Phase 0: Foundations (session 1)

- [x] Create the project `globalmart-gcp-lab` and link billing.
- [x] Set a **US$10/month budget alert** (50%, 90% and 100%). The billing account is in INR, so it's ₹900, scoped to this project (budget `globalmart-gcp-lab monthly`).
- [x] Terraform: APIs, bucket, the 5 datasets (`us-central1`), Artifact Registry, and service accounts. `sa-loader` and `sa-dbt` get write access to their datasets plus Job User and the Vertex connection. `sa-app` gets read-only access to `gold`.
- [x] Create the BigQuery Cloud resource connection for Vertex AI (`us-central1.vertex-ai`, in Terraform; its service account already has Vertex AI User).
- [x] Upload all source files to `gs://<project>-globalmart-raw/source_data/`.
- [x] Locally: `pip install dbt-bigquery`, `dbt init`, then `dbt debug` to check the connection.
- [x] Run `parity/databricks_baseline.sql` in Databricks and save the results. This is the answer key. (Done with `parity/run_databricks_baseline.py`, results in `parity/baseline_results/`.)

**Done when:** 205 files are in the bucket, the datasets exist, `dbt debug` passes, and the baseline is saved.

### Phase 1: Bronze loader (sessions 1–2)

- [ ] Python loader: list the bucket and skip files already in `ops.ingest_log`. Map each file to its entity by name pattern.
- [ ] CSV: all columns as STRING, header names in lower case, new columns allowed.
- [ ] JSON array: convert to NDJSON, then load the same way.
- [ ] Add `_source_file` and `_load_timestamp`, and log each file.
- [ ] Package it as a Cloud Run job and run it twice: the second run must load nothing.
- [ ] Declare the 6 Bronze tables as **dbt sources**, with a freshness check on `_load_timestamp`.

**Done when:** Bronze counts match `pipeline_audit_log.bronze_count` from Databricks.

### Phase 2: Silver quality layer (sessions 3–4)

- [ ] Port the 23 rules from `silver/clean/*.py` into `macros/rules/` as lists of name, field, issue type and `fail_if` condition.
- [ ] `staging` models: harmonise column variants, parse dates in several formats (`SAFE.PARSE_TIMESTAMP`), and clean `$`, `%`, `'NULL'` values and abbreviations.
- [ ] `silver.clean_<entity>`: rows where no rule fails. Wrap each condition in `coalesce(..., false)` so a NULL result doesn't drop a row silently.
- [ ] `silver.rejected_records`: one row per failure, generated from the same macros. Same columns as Databricks.
- [ ] `silver.pipeline_audit_log`: reconciliation per entity.
- [ ] Tests: `not_null` and `accepted_values` on the clean tables, plus a test that `reconciliation_diff = 0`.

**Done when:** the reconciliation difference is 0 for all entities, and failures per rule match the baseline.

### Phase 3: Gold dimensional model (sessions 5–6)

- [ ] Dimensions with `FARM_FINGERPRINT` keys (in a macro) and an **Unknown member** row (`-1`) in each.
- [ ] `dim_customers` (survivorship: latest record, prefer one with email), `dim_products`, `dim_vendors`, and `dim_dates` (`GENERATE_DATE_ARRAY`, full calendar years).
- [ ] `fact_sales`, `fact_returns`, `bridge_return_products`, and the 3 Gold view tables.
- [ ] **Contracts** (`contract: enforced: true`) on every Gold table, with `primary_key` and `foreign_key` constraints.
- [ ] Grain tests (`unique` or `dbt_utils.unique_combination_of_columns`) and `relationships` tests from each fact to its dimensions.
- [ ] `persist_docs` so table and column descriptions appear in BigQuery for the data agent.
- [ ] SCD Type 2: a one-time **backfill model** built with window functions, using the year in the file name as the version date, plus a **dbt snapshot** for changes from here on.

**Done when:** `dim_customers` = 590, all contracts and tests pass, and revenue matches the baseline.

### Phase 4: Metrics and orchestration (session 7)

- [ ] The 6 metrics models.
- [ ] dbt Cloud Run job (`globalmart-dbt`): the image runs `dbt build --target prod`.
- [ ] Cloud Workflows `globalmart-e2e`: run the loader job, then the dbt job, then report the result. A failing dbt test fails the job and stops the workflow.
- [ ] Optional: a Cloud Scheduler daily trigger. For the lab we'll usually run it by hand.
- [ ] Save `target/run_results.json` to the bucket after each run, to keep a run history.

**Done when:** `gcloud workflows run globalmart-e2e` runs Bronze to Metrics with no manual steps.

### Phase 5: GenAI layer (sessions 8–9)

- [ ] Grant Vertex AI User to the connection's service account, and confirm the current Gemini Flash model name.
- [ ] **UC1 DQ reporter:** aggregate the rejected records and explain each issue with `AI.GENERATE` → `gold.dq_audit_report`.
- [ ] **UC2 fraud investigator:** 5 weighted rules in SQL (`APPROX_QUANTILES` for P85, 12-month window), flag at ≥ 40, write briefs **only for flagged customers** → `gold.flagged_return_customers`.
- [ ] **UC3 product RAG:** pre-ranked and detail documents in two embedding tables, `VECTOR_SEARCH` with a region filter, then a Gemini answer → `gold.rag_query_history`.
- [ ] **UC4 executive intel:** pre-computed KPIs go to Gemini → `gold.ai_business_insights`.
- [ ] Tag all four models `genai`, so `dbt build --select tag:genai` can rerun just this layer.

**Done when:** all 4 tables are populated and the flag rate is about 22%.

### Phase 6: BI and conversational analytics (session 10)

- [ ] Looker Studio report with 4 pages and a year filter.
- [ ] Conversational Analytics data agent over the 20 tables. Instructions are adapted from `setup_genie.py`, and the join guidance includes both date roles and the corrected bridge join (`order_id` **and** `product_sk`).
- [ ] 10 test questions, checking the SQL each time.
- [ ] dbt **exposures** for the report and the app, so the lineage shows who uses each table.

**Done when:** at least 9 of 10 questions are answered correctly.

### Phase 7: Cloud Run app (sessions 11–13)

- [ ] Express server with an allowlist of `.sql` files and BigQuery named parameters (`@min_orders`).
- [ ] Reuse the 27 query files (adjusting table names and parameter syntax), and port the 10 React pages to Recharts and shadcn/ui.
- [ ] Ask page using the Conversational Analytics API as the **signed-in user**.
- [ ] `sa-app` has read-only access to `gold`. Sign-in through IAP (see the fallback in Risk 4).
- [ ] CI check: dry-run every app query, so a breaking Gold change fails the build. Together with the dbt contracts, this protects the app from both directions.

**Done when:** the app is deployed, all pages work, and a renamed column fails CI.

### Phase 8: CI/CD, documentation and comparison (sessions 14–16)

- [ ] Cloud Build on every push:
  - `dbt build --select state:modified+` (build and test only what changed);
  - query contract check;
  - build and deploy the app.
- [ ] `dbt docs generate`, with the docs site published as a static site.
- [ ] `gcp/README.md`, including a **teardown** section.
- [ ] Parity report: numbers, effort, cost, and what was easier or harder on each platform. This is the outline for article 2.

### Phase 9 (optional): Real-time orders with Pub/Sub and Dataflow (sessions 17–18)

This shows streaming skills, the GCP equivalent of Auto Loader running continuously.

- [ ] A small replayer publishes 2026 orders as events to the Pub/Sub topic `orders-events`, a few per second.
- [ ] A Dataflow streaming pipeline (Apache Beam, Python) that:
  - parses and validates each event using the same rules as Silver;
  - sends bad events to a **dead-letter** table (`bronze.orders_stream_rejected`), the quarantine pattern in streaming form;
  - writes good events to `bronze.raw_orders_stream`;
  - computes 1-minute revenue per region in windows → `metrics.live_revenue_by_region`.
- [ ] A dbt incremental model merges the stream into Silver on the next build.
- [ ] Cost control: at most 1–2 workers, run only during a demo, and **drain and cancel** the job afterwards.

**Done when:** events flow end to end, bad events land in the dead-letter table, and the live revenue table updates every minute.

### Phase 10 (stretch): The same dbt project on Databricks (sessions 19–21)

- [ ] Add a `databricks` target with `dbt-databricks`.
- [ ] Move dialect differences into `adapter.dispatch` macros, for example `SAFE.PARSE_TIMESTAMP` vs `try_to_timestamp`, and `FARM_FINGERPRINT` vs `xxhash64`.
- [ ] Run `dbt build --target databricks` against the Databricks workspace, and compare results with the BigQuery run.

**Done when:** one dbt codebase produces matching Gold numbers on both platforms. That's the headline for article 2.

## 5. Today (Session 1) step by step

1. **Tools:** check that `gcloud`, `bq`, `terraform`, `docker` and Python 3.12 are installed, then sign in with the personal Gmail:
   ```bash
   gcloud auth login
   gcloud auth application-default login
   pip install dbt-bigquery
   ```
2. **Answer key first:** run `gcp/parity/databricks_baseline.sql` in Databricks and export the results to `gcp/parity/baseline_results/`.
3. **Project and billing:**
   ```bash
   gcloud projects create globalmart-gcp-lab --name="GlobalMart GCP Lab"
   gcloud billing projects link globalmart-gcp-lab --billing-account=<BILLING_ACCOUNT_ID>
   gcloud config set project globalmart-gcp-lab
   ```
4. **Budget alert:** set US$10/month in the Billing console.
5. **Terraform foundations:** we write `gcp/terraform/` together and run `terraform apply`.
6. **Upload the source files:**
   ```bash
   gcloud storage rsync -r source_data \
     "gs://globalmart-gcp-lab-globalmart-raw/source_data"   # source_data/ is committed in this repo
   ```
7. **dbt:** `cd gcp/dbt && dbt init` (or we scaffold the project by hand), then `dbt debug`.
8. **Start the Bronze loader** with `vendors.csv` and the customer files.

## 6. Cost guardrails

- **Budget alert** at US$10/month from Day 1.
- **No Cloud Composer.** It bills all the time.
- **Cloud Run jobs** bill only while running, and the app service runs with minimum 0 instances.
- **BigQuery on-demand.** The monthly free tier (1 TiB of queries, 10 GiB of storage) should cover this data size. Add a custom daily query quota as a safety net.
- **Gemini** calls are bounded: UC2 writes briefs only for flagged customers, and UC1 works on aggregates.
- **Dataflow has no free tier.** Phase 9 runs only during a demo, with `max_num_workers` capped and the job drained and cancelled afterwards.
- **Week 1 check:** read the billing report after the first full run.

## 7. Risks

| # | Risk | Mitigation |
|---|---|---|
| 1 | Bronze is all STRING, while Databricks inferred types | Explicit casts in staging models; parity checks per rule |
| 2 | Conversational Analytics features or pricing on a personal project | Check at the start of Phase 6; test in the BigQuery Studio UI first |
| 3 | AI output is not deterministic | Compare structure and counts, not wording |
| 4 | IAP on a personal project (no organisation) needs extra OAuth setup | Fallback: an authenticated Cloud Run service reached through `gcloud run services proxy` |
| 5 | Hash keys differ from Databricks keys | Parity checks compare on business keys only |
| 6 | GCP and dbt product names and features change | Confirm current names at the start of each phase |
| 7 | A Dataflow job left running costs money | Cap workers, set a reminder, and always drain and cancel |
| 8 | SQL dialect differences between BigQuery and Databricks (Phase 10) | Keep platform-specific SQL in a few dispatch macros from Phase 2 onwards |

## 8. Open questions to settle today

1. **Project ID:** is `globalmart-gcp-lab` OK? IDs are global, so we may need a suffix.
2. **Ask-My-Lakehouse:** should this become your Ask-My-Lakehouse lab? If yes, connect the `gcp-demo` folder so we can align the two plans.
3. **SCD Type 2 version date:** use the year in the customer file name?
4. **GitHub:** push `gcp/` to the same remote as the Databricks repo?
5. **Phases 9 and 10:** include both, or decide after Phase 8?
6. **Genie join fix:** correct the bridge join in `setup_genie.py` so both versions match?
