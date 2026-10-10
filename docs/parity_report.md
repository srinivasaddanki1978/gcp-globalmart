# One warehouse design, two platforms: GlobalMart on Databricks vs Google Cloud

Outline and evidence for the follow-up article. The same 205 source files and the same
Bronze → Silver → Gold → Metrics → GenAI design, built on Databricks (DLT, notebooks, Genie,
AppKit) and on Google Cloud (Cloud Run, dbt on BigQuery, Gemini, Conversational Analytics).
Every number below comes from the comparison scripts in `parity/`, run against both platforms on
10 Oct 2026.

## 1. Do the numbers match?

| # | Parity target | Databricks | Google Cloud | Result |
|---|---|---|---|---|
| 1 | All files loaded, each once | 205 | 205; a second run loads 0 | ✅ |
| 2 | Bronze = Silver + rejected, 6 entities | diff 0 | diff 0 | ✅ |
| 3 | `dim_customers` | 590 | 590 current rows (+ Unknown member) | ✅ |
| 4 | Revenue by year × region | baseline | 53/53 rows within $0.01 | ✅ |
| 5 | Bridge allocated refund | $2,478,124.40 | $2,478,124.40 | ✅ |
| 6 | Fraud flag rate | 22.52% (109/484) | 22.52%, same 109 customers, scores and rules | ✅ |
| 7 | Data agent, 10 test questions | (Genie) | 10/10 vs golden SQL | ✅ |
| 8 | One command, under budget | Workflow job | `gcloud workflows run globalmart-e2e`, ~8 min | ✅ |

**Row-level parity, layer by layer**

- **Bronze:** every column of all 6 tables has identical non-null counts, distinct counts and total text length (`compare_bronze.py`).
- **Silver:** the audit log is identical, and all **6,027 rejected rows match field for field**, including the `record_data` JSON text (`compare_silver.py`).
- **Gold:** every dimension and fact is identical on business columns, and so are the Unknown-key counts (371 returns without a customer = Databricks' NULL keys) (`compare_gold.py`).
- **Metrics and views:** identical except **198 aggregate rows that differ by exactly one cent** (see 2.1).
- **GenAI:** UC1 counts, UC2 scores and UC4 KPIs match (`compare_genai.py`). The AI-written text differs by design.

## 2. Where the platforms differ, and why

### 2.1 The one-cent differences are Databricks rounding float sums
Spark adds `DOUBLE`s in whatever order the tasks deliver them. When a true total sits on a half cent
(for example 45,732.015), the float lands just above or below and `ROUND(…, 2)` goes either way. It
can even change between Databricks runs. The GCP build adds money exactly (`exact_sum`: BIGNUMERIC
over each value's decimal text) and rounds half-up as Spark does (`spark_round`). The GCP figure is
the true one, and it is the same on every run.

### 2.2 Matching meant copying Spark's behaviour, not BigQuery's defaults
- Failed casts and date parses return NULL in Spark (non-ANSI): `try_cast`, `try_parse_timestamp`.
- A double-to-long cast truncates in Spark and rounds in BigQuery, which matters for UPCs in scientific notation: `truncate_to_int`.
- `ROUND(2.675, 2)` is 2.68 in Spark and 2.67 in BigQuery: `spark_round`.
- Spark writes `100.0` and `2018-11-17 00:00:00` where BigQuery writes `100` and `…+00`: `spark_string`.
- Databricks file paths are URL-encoded (`Region%201/`), and GCS keeps the space.

All of these live behind `adapter.dispatch` in `dbt/macros/dialect.sql`, which is the groundwork
for running the same dbt project on Databricks (Phase 10).

### 2.3 Facts the rebuild surfaced about the data
- Databricks Bronze was also all STRING (Auto Loader doesn't infer types for these formats), so type risk sits only in Silver casts.
- Only 5 of the 23 rules ever fail on this data.
- Every customer appears exactly twice (regional file + Region 6, same year). Survivorship ties on load time and is settled by "prefer a row with an email". The file year can't produce SCD Type 2 history.
- Transactions repeat `(order_id, product_id)` 63 times, so `fact_sales` needs a line number in its key.

## 3. What the GCP build does better (the "before production" list)

| Area | Databricks | Google Cloud |
|---|---|---|
| Quality rules | Each rule written twice (clean notebook + quarantine flow) | Written once (`silver_rules.sql`); clean and rejected tables are generated from it |
| Surrogate keys | `monotonically_increasing_id()`: change on every rebuild | `FARM_FINGERPRINT(business key)`: stable |
| Missing dimension values | NULL keys in facts | Unknown member (-1) |
| Schema safety | Informational PK/FK | Enforced dbt contracts plus PK/FK constraints; the app's query check fails CI on a breaking change |
| Customer history | SCD Type 1 | SCD Type 2 (dbt snapshot); facts use the version in effect at the time |
| Money arithmetic | Float sums (non-deterministic cents) | Exact decimal sums |
| `profit` type | STRING | FLOAT64 |
| Genie bridge join | `order_id` only (multiplies rows) | `sales_sk` (one row per line) |
| RAG | FAISS + local MiniLM, re-embedded every run | VECTOR_SEARCH + Vertex embeddings, incremental |
| Deploy safety | — | CI: tests and dbt CI build (`*_ci` datasets) before any image is published |

## 4. Where Databricks was easier

- **One platform, one UI:** notebooks, pipeline, dashboard, Genie and the app live in one workspace. GCP needs 8–9 services (Cloud Run, BigQuery, Workflows, Vertex AI, Conversational Analytics, Looker Studio, Artifact Registry, Cloud Build, IAM) wired together by Terraform.
- **Governance built in:** Unity Catalog column masks and row filters came with the platform. On GCP that would need policy tags, authorised views or row access policies. Not ported.
- **Dashboard as code:** the AI/BI dashboard is a JSON file in the bundle. Looker Studio has no page-building API, so the report is built by hand (`docs/looker_studio.md`).
- **App identity:** an AppKit app calls Genie as the user out of the box. On a personal GCP project, per-user identity needs IAP or an OAuth client (consent-screen setup), so the app uses a service account and authenticated Cloud Run.
- **Streaming ingestion** (Auto Loader) is one option; the GCP loader is custom Python (~250 lines).

## 5. Where Google Cloud was easier

- **GenAI is SQL:** `AI.GENERATE`, `AI.EMBED` and `VECTOR_SEARCH` run inside dbt models. No notebooks, `%pip`, model-serving endpoints or reasoning-token parsing.
- **dbt replaces a lot of custom code:** DAG ordering, tests, contracts, snapshots, docs, lineage (exposures) and `state:modified` CI, versus a hand-run DQ scorecard and DLT expectations that always report 0 failures in Silver.
- **The data agent is code:** created, updated and tested through a GA API (`agent/data_agent.py`). The Genie Instructions and Joins tabs had to be pasted by hand.
- **Scale to zero:** nothing runs between pipeline runs.
- **Portability:** the transformation layer is dbt, so the same project can target Databricks next.

## 6. Cost (personal lab, 10 Oct 2026)

| Item | Usage | Cost |
|---|---|---|
| BigQuery queries | 0.014 TiB billed over 1,318 jobs, including all parity checks | Free tier (1 TiB/month) |
| BigQuery storage | ~294 MiB (most of it the RAG embeddings) | Free tier (10 GiB) |
| Cloud Run jobs + app | ~8 min per pipeline run; app scales to zero | Free-tier range |
| Gemini + embeddings | ~120 Gemini calls per full run; ~16.6k embeddings once | Cents |
| Cloud Build | A few builds/day, 8-vCPU machine | Free tier (2,500 build-min/month) to cents |

Budget alert: ₹900/month (≈ US$10). Check the actual spend in the Billing console after the first
full week (plan, Cost guardrails).

## 7. Effort

The core build (plan Phases 0–8) was done in one long working session on 10 Oct 2026, against an
estimate of 14–16 three-hour sessions. Most of the time went into the parity work, not the platform
plumbing: matching Spark's type and rounding behaviour, then explaining every remaining difference.

## 8. Open items

- Looker Studio report pages: built by hand per `docs/looker_studio.md`.
- Per-user identity for the app (IAP / OAuth) instead of `sa-app`.
- Governance (masks, row filters) and the DQ scorecard history page.
- Phase 9 (Pub/Sub + Dataflow streaming) and Phase 10 (the same dbt project on Databricks).
