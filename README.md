# GlobalMart Data Intelligence Platform on Google Cloud

An end-to-end retail data platform on native Google Cloud services. 205 source files from six
regional systems go through a medallion pipeline (Bronze → Silver → Gold → Metrics) in BigQuery, with
Gemini-powered analysis, a natural-language data agent, a web app, dashboards and CI/CD.

**New here? Build it yourself:** [`docs/MANUAL_SETUP_GUIDE.md`](docs/MANUAL_SETUP_GUIDE.md) walks
you through creating every Google Cloud resource by hand, explaining each service as you go.

```
source_data/ ──► GCS ──► Cloud Run job: Bronze loader (Python) ──► BigQuery bronze (all STRING)
                              │
                              ▼
               Cloud Run job: dbt build ──► silver ──► gold ──► metrics ──► GenAI (Gemini in SQL)
                              │
      ┌───────────────┬───────┴────────────┬─────────────────────────┐
      ▼               ▼                    ▼                         ▼
 Looker Studio   Data agent         Cloud Run app             dbt docs (/dbt-docs)
 (rpt_* views)   (Conv. Analytics)  (React + Express)

 Cloud Workflows globalmart-e2e: loader → dbt      Cloud Build: tests → dbt CI → images → deploy
```

| Layer | Service |
|---|---|
| Ingestion (Bronze) | Python loader, Cloud Run job `globalmart-loader`, `ops.ingest_log` (each file loaded once) |
| Transformations | dbt Core (`dbt-bigquery`), Cloud Run job `globalmart-dbt`: 23 quality rules defined once, enforced Gold contracts, SCD Type 2 via snapshot |
| Orchestration | Cloud Workflows `globalmart-e2e` |
| GenAI | `AI.GENERATE` (Gemini) and `AI.EMBED` + `VECTOR_SEARCH`, inside dbt models |
| BI / Q&A / App | Looker Studio, Conversational Analytics data agent, Cloud Run app `globalmart-app` |
| Infrastructure / CI | Terraform, Cloud Build |

## Repository layout

| Path | What |
|---|---|
| `source_data/` | The 205 input files (CSV + JSON arrays), uploaded verbatim to GCS |
| `terraform/` | Everything in GCP: APIs, bucket, datasets, service accounts/IAM, Vertex connection, Artifact Registry, Cloud Run jobs + service, Workflows, CI |
| `loader/` | Bronze loader + tests + Dockerfile |
| `dbt/` | dbt project: `models/{bronze,silver,gold,metrics,genai,reporting}`, `macros/` (rules, dialect, GenAI), `snapshots/` |
| `workflows/` | Cloud Workflows definition (rendered by Terraform) |
| `agent/` | Data agent definition, deploy/ask/test script, 10 golden test questions |
| `app/` | React + Express app, 27 allowlisted queries, query contract check |
| `tests/` | Known-good results and the check that compares a pipeline run against them |
| `docs/` | Manual setup guide (learning path), Looker Studio build guide |

## Set up

Two ways, same result:

| | Guide | For |
|---|---|---|
| **Automated** | [`docs/AUTOMATED_DEPLOYMENT.md`](docs/AUTOMATED_DEPLOYMENT.md) | Clone, sign in, run one script: infrastructure, images, data, pipeline, data agent and optional CI/CD (~25 min) |
| **By hand** | [`docs/MANUAL_SETUP_GUIDE.md`](docs/MANUAL_SETUP_GUIDE.md) | Learning Google Cloud: build every resource yourself, with each service explained (console + CLI) |

The automated path in short (needs `gcloud`, `terraform` ≥ 1.6 and Python 3.12):

```bash
gcloud auth login && gcloud auth application-default login
git clone https://github.com/srinivasaddanki1978/gcp-globalmart.git && cd gcp-globalmart
PROJECT_ID=<new-unique-id> BILLING_ACCOUNT=<XXXXXX-XXXXXX-XXXXXX> BUDGET=10USD scripts/deploy.sh
```

## Daily use

```bash
gcloud workflows run globalmart-e2e --location=us-central1               # refresh everything
gcloud run services proxy globalmart-app --region=us-central1 --port=8080 # app at http://localhost:8080 (dbt docs at /dbt-docs)
.venv/bin/python agent/data_agent.py ask "Which vendor has the highest return rate?"
```

Local development: `CLAUDE.md` lists the commands for each component (dbt, loader, app, expected-results check).

## CI/CD

Each push to `main` runs `cloudbuild.yaml` as `sa-cloudbuild`:

1. **Tests, in parallel:** loader `pytest`; app `vitest`, typecheck and `check:queries` (dry-runs all 27 app queries, so a Gold change that breaks the app fails the build); **dbt CI**: `dbt build --target ci --select state:modified+ --defer` builds only changed models and their downstream models into `silver_ci`/`gold_ci`/`metrics_ci` (tables expire after 3 days) with tests and contracts, against the last production manifest. Production tables are never touched.
2. **Images**, only if every test passed: loader, dbt and app, tagged with the commit SHA.
3. **Deploy:** new app revision; both Cloud Run jobs point at the new images. The production data refresh stays with the workflow.

`dbt docs generate` runs in CI and the static site is served by the app at `/dbt-docs` (signed-in users only).

## Cost guardrails

Budget alert (₹900 ≈ US$10/month, 50/90/100%) · no always-on services (Cloud Run scales to zero, jobs bill
only while running, no Composer) · BigQuery on-demand within the free tier · app queries capped at 1 GiB
each · Gemini called only for bounded rows (~120 calls per full run) · RAG embeddings incremental.

## Teardown

**Scripted:** `PROJECT_ID=<id> scripts/teardown.sh` removes every GlobalMart resource and its data
(keeps the project); `DELETE_PROJECT=1` deletes the project instead. **By hand**, the same steps:
steps 1–4 keep the project; step 5 deletes it entirely, which on its own also covers steps 1–4.

```bash
# 1. Data agent (Conversational Analytics; not managed by Terraform)
.venv/bin/python agent/data_agent.py delete

# 2. Cloud Build GitHub connection and trigger (created outside Terraform)
gcloud builds triggers delete globalmart-main --region=us-central1 --quiet
gcloud builds connections delete globalmart-github --region=us-central1 --quiet

# 3. All Terraform-managed resources: datasets (with tables), bucket (with files), Cloud Run jobs
#    and service, workflow, Artifact Registry (with images), service accounts, IAM, connection
cd terraform && terraform destroy

# 4. Budget (billing account level) and the Looker Studio report (in Looker Studio: Remove)
gcloud billing budgets list --billing-account=<BILLING_ACCOUNT_ID>
gcloud billing budgets delete <BUDGET_ID> --billing-account=<BILLING_ACCOUNT_ID>

# 5. Or delete the whole project (30-day recovery window)
gcloud projects delete <PROJECT_ID>
```

`silver.customers_snapshot` holds the only copy of SCD Type 2 customer history; export it first if
you want to keep that history.
