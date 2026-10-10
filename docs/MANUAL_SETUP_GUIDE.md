# Build GlobalMart on Google Cloud by hand: a step-by-step learning guide

This guide rebuilds the whole platform in your own Google Cloud project **by hand**, one service at
a time, so you learn what each piece is, why it's there and how the pieces connect. Nothing is
automated until you've built it yourself once.

By the end you'll have built and understood:

```
source_data/ ─► Cloud Storage ─► Cloud Run job (loader) ─► BigQuery bronze
                                                               │
                         Cloud Run job (dbt) ◄─────────────────┘
                         silver ─► gold ─► metrics ─► GenAI (Gemini inside SQL)
                                                               │
        ┌───────────────────┬──────────────────────┬───────────┴──────────┐
        ▼                   ▼                      ▼                      ▼
  Looker Studio        Data agent            Cloud Run app          Cloud Build CI/CD
  (dashboards)    (questions in English)   (web dashboard + chat)  (test + deploy on push)

  Cloud Workflows: runs the loader, then dbt, as one pipeline
```

**How each module works**

> **Learn:** what the service is, the key ideas, and why this project uses it.
>
> **Console:** how to do it in the Google Cloud web console (best for learning).
>
> **CLI:** the same thing as copy-paste commands (best for repeating it later).
>
> **Check:** how to confirm it worked before moving on.

Do each step **either** in the console **or** with the CLI. The names in this guide (bucket,
datasets, jobs…) are the ones the code expects, so use them exactly.

**Time:** about 3 hours the first time. **Cost:** the free tiers cover normal use. Module 1 sets
a budget alert so you're warned before any spend.

| Module | You build | Main GCP service |
|---|---|---|
| 0 | Tools on your computer | — |
| 1 | Billing account and budget | Cloud Billing |
| 2 | Project, CLI sign-in, the repo | Resource Manager, gcloud |
| 3 | Enabled APIs | Service Usage |
| 4 | Bucket with the 205 source files | Cloud Storage |
| 5 | The five data layers | BigQuery datasets |
| 6 | Identities and permissions | IAM, service accounts |
| 7 | BigQuery's link to Gemini | BigQuery connections, Vertex AI |
| 8 | Container images | Artifact Registry, Cloud Build |
| 9 | The Bronze loader, run on its own | Cloud Run jobs |
| 10 | dbt: Silver, Gold, Metrics, GenAI | Cloud Run jobs, BigQuery |
| 11 | The end-to-end pipeline | Cloud Workflows |
| 12 | Try Gemini in SQL yourself | BigQuery AI functions |
| 13 | The data agent | Conversational Analytics API |
| 14 | The web app | Cloud Run services |
| 15 | Dashboards | Looker Studio |
| 16 | CI/CD from GitHub | Cloud Build triggers |
| 17 | Check every number | BigQuery |
| 18 | Operate, troubleshoot, clean up | — |

---

## Module 0: Install the tools

| Tool | Why |
|---|---|
| **Git** | Download this repository |
| **Google Cloud CLI** (`gcloud`, `bq`) | Control Google Cloud from your terminal |
| **Python 3.12** | Run dbt, the loader tests and the data agent script |
| **Node.js 24** *(optional)* | Only to work on the web app locally |

You do **not** need Docker: Google builds the container images for you (Module 8).

**macOS**
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"   # Homebrew, if missing
brew install git python@3.12 node@24
brew install --cask gcloud-cli
```
No Homebrew or no admin rights? Install `gcloud` into your home folder:
```bash
curl -fsSLO https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-darwin-arm.tar.gz   # Intel: ...-darwin-x86_64.tar.gz
tar -xzf google-cloud-cli-darwin-*.tar.gz -C ~ && ~/google-cloud-sdk/install.sh --quiet
echo 'export PATH="$HOME/google-cloud-sdk/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc
```

**Windows:** install Git (<https://git-scm.com/download/win>) and use **Git Bash** for every command
in this guide. Then install Python 3.12 (<https://www.python.org/downloads/>, tick *Add to PATH*),
Node.js 24 (<https://nodejs.org>) and the Google Cloud CLI (<https://cloud.google.com/sdk/docs/install#windows>).

**Linux (Debian/Ubuntu)**
```bash
sudo apt-get update && sudo apt-get install -y git python3.12 python3.12-venv curl gnupg
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list
sudo apt-get update && sudo apt-get install -y google-cloud-cli
```

**Check**
```bash
git --version && gcloud --version | head -1 && bq version && python3.12 --version
```

---

## Module 1: Google account, billing account and budget

> **Learn.** Google Cloud has three levels:
> - your **Google account** (who you are);
> - a **billing account** (who pays: a payment method, a currency, invoices);
> - **projects** (containers for resources, each linked to one billing account).
>
> Even free-tier usage needs a billing account. A **budget** watches a project's spend and emails
> you at thresholds. It *alerts*, it doesn't stop spending.

### 1.1 Google account
1. Create one at <https://accounts.google.com/signup> if needed. A personal Gmail is fine.
2. Open <https://console.cloud.google.com>, sign in, pick your country and accept the terms.

### 1.2 Billing account
1. Console menu (☰) → **Billing** → **Manage billing accounts** → **Create account**.
2. If you're offered the **free trial** (credit for new users), accept it.
3. Fill in a **name** (e.g. `my-billing`), your **country** and **currency** (the currency can't be
   changed later), account type **Individual**, and a **payment card**. It's verified and may get
   a small temporary hold.
4. **Submit and enable billing**.
5. Copy the **Billing account ID** (`XXXXXX-XXXXXX-XXXXXX`) from the account's **Overview** page.

**Check:** **Billing → Manage billing accounts** lists your account as *Active*.

(You'll create the budget in Module 2.3, once the project exists.)

---

## Module 2: Project, CLI sign-in and the repository

> **Learn.** A **project** holds every resource you create here. It has a **project ID** (globally
> unique, chosen by you, used in commands and URLs) and a **project number** (assigned by Google,
> used in some service-account names).
>
> The CLI has **two sign-ins**:
> - `gcloud auth login` is for `gcloud` and `bq` commands.
> - `gcloud auth application-default login` creates **Application Default Credentials (ADC)**,
>   which programs on your computer (dbt, Python, Node) use automatically.
>
> On Google's servers, the same libraries use the attached **service account** instead (Module 6).
> That's why the code never contains a password or key.

### 2.1 Sign in from the terminal
```bash
gcloud auth login                         # browser opens: choose your account, Allow
gcloud auth application-default login     # browser again: Allow
```

### 2.2 Choose names and create the project
Pick a project ID: 6–30 characters, lowercase letters, digits and hyphens, unique worldwide (e.g.
`globalmart-lab-4821`). Set these in **every new terminal**, or add them to `~/.zshrc` / `~/.bashrc`:
```bash
export PROJECT_ID=globalmart-lab-4821             # yours
export REGION=us-central1                         # keep this region (see the note below)
export BILLING_ACCOUNT=XXXXXX-XXXXXX-XXXXXX       # from Module 1.2
export GCP_PROJECT=$PROJECT_ID                    # read by dbt, the loader, the app and the agent script
export BUCKET=$PROJECT_ID-globalmart-raw
export REPO=$REGION-docker.pkg.dev/$PROJECT_ID/globalmart
```
> **Region note:** every regional resource here lives in `us-central1`, and the code assumes it
> (`dbt/profiles.yml`, `dbt/dbt_project.yml`, `cloudbuild.yaml`). Keep it for this guide.

**Console:** project picker (top bar) → **New project** → name `GlobalMart Lab` → click **Edit**
under the ID and type your `PROJECT_ID` → **Create**. Then **Billing → My projects** → your project →
⋮ → **Change billing** → your billing account.

**CLI**
```bash
gcloud projects create $PROJECT_ID --name="GlobalMart Lab"
gcloud billing projects link $PROJECT_ID --billing-account=$BILLING_ACCOUNT
gcloud config set project $PROJECT_ID                         # default project for gcloud/bq
gcloud auth application-default set-quota-project $PROJECT_ID # bill ADC API calls to this project
export PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')
```
**Check:** `gcloud projects describe $PROJECT_ID` shows `lifecycleState: ACTIVE`, and
`gcloud billing projects describe $PROJECT_ID` shows `billingEnabled: true`.

### 2.3 Budget alert
**Console:** **Billing → Budgets & alerts → Create budget**. Set **Name** `globalmart monthly`,
**Projects** your project only, **Amount** e.g. US$10 (or the same in your billing currency), and
thresholds **50 %, 90 %, 100 %** of actual spend. **Finish**.

**CLI** (the amount must be in your billing currency, e.g. `900INR`, `10EUR`):
```bash
gcloud services enable billingbudgets.googleapis.com
gcloud billing budgets create --billing-account=$BILLING_ACCOUNT --display-name="globalmart monthly" \
  --budget-amount=10USD --filter-projects="projects/$PROJECT_NUMBER" --calendar-period=month \
  --threshold-rule=percent=0.5 --threshold-rule=percent=0.9 --threshold-rule=percent=1.0
```

### 2.4 Get the repository
```bash
git clone https://github.com/srinivasaddanki1978/gcp-globalmart.git   # use your fork if you'll do Module 16
cd gcp-globalmart
python3.12 -m venv .venv
.venv/bin/pip install -r loader/requirements.txt -r dbt/requirements.txt pytest
(cd dbt && ../.venv/bin/dbt deps)
```
Look around: `source_data/` holds the 205 input files, `loader/` the ingestion code, `dbt/` all
transformations, `app/` the web app, `agent/` the data agent, `workflows/` the pipeline definition.

---

## Module 3: Enable the APIs

> **Learn.** Every Google Cloud service is an **API** that's off until you enable it in a project.
> Enabling is free; you pay only for usage. This project uses:
>
> | API | For |
> |---|---|
> | BigQuery, BigQuery Connection | the warehouse; its link to Vertex AI |
> | Cloud Storage | the source files |
> | Vertex AI | Gemini and embeddings |
> | Artifact Registry, Cloud Build | storing and building container images |
> | Cloud Run Admin, Workflows | running the jobs and the app; the pipeline |
> | IAM | service accounts |
> | Gemini Data Analytics, Gemini for Google Cloud | the data agent |
> | Secret Manager | storing the GitHub token for CI/CD |

**Console:** **APIs & Services → Library**. Search for each name above → **Enable**.

**CLI**
```bash
gcloud services enable bigquery.googleapis.com bigqueryconnection.googleapis.com storage.googleapis.com \
  aiplatform.googleapis.com artifactregistry.googleapis.com cloudbuild.googleapis.com run.googleapis.com \
  workflows.googleapis.com iam.googleapis.com geminidataanalytics.googleapis.com \
  cloudaicompanion.googleapis.com secretmanager.googleapis.com
```
**Check:** `gcloud services list --enabled` shows them. A newly enabled API can take a minute
before commands using it work.

---

## Module 4: Cloud Storage, the landing zone for source files

> **Learn.** **Cloud Storage** stores files ("objects") in **buckets**. Bucket names are global.
> Key settings:
> - **location:** keep data next to the compute that reads it;
> - **uniform bucket-level access:** permissions only through IAM, no per-file ACLs;
> - **public access prevention:** nobody can accidentally make files public.
>
> The loader reads the source files from here. Uploading is the "files arrive" event the loader
> reacts to.

**Console:** **Cloud Storage → Buckets → Create**. Name: your `$BUCKET` value; location type
**Region**, `us-central1`; storage class **Standard**; access control **Uniform**, with
**Enforce public access prevention** ticked. **Create**. Then open the bucket → **Create folder**
`source_data` → open it → **Upload folder**, choosing the *contents* of the repo's `source_data/`
(the six `Region …` folders and the four top-level files).

**CLI**
```bash
gcloud storage buckets create gs://$BUCKET --location=$REGION \
  --uniform-bucket-level-access --public-access-prevention
gcloud storage rsync -r source_data gs://$BUCKET/source_data      # 205 files, ~16 MB
```
**Check:** 205 objects (157 CSV, 48 JSON):
```bash
gcloud storage ls -r "gs://$BUCKET/source_data/**" | grep -cE '\.(csv|json)$'
```

---

## Module 5: BigQuery datasets, the five data layers

> **Learn.** **BigQuery** is a serverless data warehouse. You don't run servers; you pay per byte
> scanned (1 TiB/month free) and per byte stored (10 GiB free). A **dataset** is a folder of tables
> with a fixed **location**. Here each dataset is one layer of a *medallion* design:
>
> | Dataset | Holds | Written by |
> |---|---|---|
> | `bronze` | raw files, every column text | loader |
> | `silver` | cleaned rows, rejected rows, audit log | dbt |
> | `gold` | dimensional model, AI outputs, report views | dbt |
> | `metrics` | business aggregates | dbt |
> | `ops` | which files were loaded | loader |
> | `silver_ci`, `gold_ci`, `metrics_ci` | temporary CI builds (tables expire after 3 days) | CI |
>
> You create only the datasets. Tables are created by the code when it runs.

**Console:** **BigQuery** → in **Explorer**, ⋮ next to your project → **Create dataset**. Enter the
**Dataset ID**, location type **Region**, `us-central1` → **Create dataset**. Repeat for all eight.
For the three `*_ci` datasets, also tick **Enable table expiration** and set 3 days.

**CLI**
```bash
for ds in bronze silver gold metrics ops; do
  bq --location=$REGION mk --dataset --description "GlobalMart $ds layer" $PROJECT_ID:$ds
done
for ds in silver_ci gold_ci metrics_ci; do
  bq --location=$REGION mk --dataset --default_table_expiration 259200 --description "dbt CI (temporary)" $PROJECT_ID:$ds
done
```
**Check:** `bq ls` lists the eight datasets.

---

## Module 6: Identities and permissions (IAM)

> **Learn.** **IAM** answers "who can do what on which resource".
> - A **principal** is a user (you) or a **service account**: an identity for software.
> - A **role** is a bundle of permissions, e.g. *BigQuery Data Viewer*.
> - A **binding** grants a role to a principal **on a resource**: the whole project, one dataset,
>   one bucket, one job.
>
> This project follows **least privilege**: each program gets its own service account with only
> what it needs. The loader can write `bronze` but not `gold`; the app can only *read* `gold` and
> `metrics`. **Service Account User** ("actAs") lets one identity deploy something that runs as
> another; CI/CD needs it.

### 6.1 Create the service accounts

| Service account | Runs | Allowed to |
|---|---|---|
| `sa-loader` | the loader job | read the bucket, write `bronze` and `ops` |
| `sa-dbt` | the dbt job | read `bronze`/`ops`, write `silver`/`gold`/`metrics`, call Gemini, write run history |
| `sa-app` | the web app | read `gold`/`metrics`, use the data agent |
| `sa-workflows` | the pipeline | start the two jobs |
| `sa-cloudbuild` | CI/CD | read data, write `*_ci`, push images, deploy |

**Console:** **IAM & Admin → Service accounts → Create service account**. Enter the name
(e.g. `sa-loader`) → **Create and continue** → skip the optional steps → **Done**. Repeat for all five.

**CLI**
```bash
for sa in loader dbt app workflows cloudbuild; do
  gcloud iam service-accounts create sa-$sa --display-name="GlobalMart $sa"
done
SA() { echo "sa-$1@$PROJECT_ID.iam.gserviceaccount.com"; }   # helper: SA loader → full email
```

### 6.2 Project-level roles
**Console:** **IAM & Admin → IAM → Grant access**. Paste the service account's email as the principal,
choose the role, **Save**. One row per line:

| Principal | Role | Why |
|---|---|---|
| sa-loader, sa-dbt, sa-app, sa-cloudbuild | BigQuery Job User | run queries and load jobs |
| sa-dbt, sa-cloudbuild | BigQuery Connection User | use the Gemini connection (Module 7) |
| sa-app | Gemini Data Analytics Data Agent User; Gemini for Google Cloud User | the app's chat page |
| sa-workflows | Cloud Run Viewer; Logs Writer | follow job runs, write logs |
| sa-cloudbuild | Cloud Run Developer; Artifact Registry Writer; Logs Writer | deploy, push images, build logs |

**CLI**
```bash
P() { gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$1" --role=$2 --condition=None --quiet >/dev/null && echo "granted $2 to $1"; }
for sa in loader dbt app cloudbuild; do P $(SA $sa) roles/bigquery.jobUser; done
P $(SA dbt)        roles/bigquery.connectionUser
P $(SA cloudbuild) roles/bigquery.connectionUser
P $(SA app)        roles/geminidataanalytics.dataAgentUser
P $(SA app)        roles/cloudaicompanion.user
P $(SA workflows)  roles/run.viewer
P $(SA workflows)  roles/logging.logWriter
P $(SA cloudbuild) roles/run.developer
P $(SA cloudbuild) roles/artifactregistry.writer
P $(SA cloudbuild) roles/logging.logWriter
```

### 6.3 Dataset-level roles
> Granting on a **dataset** instead of the project keeps each identity inside its own layers.

**Console:** **BigQuery → Explorer → dataset → Sharing → Permissions → Add principal**:

| Dataset | Principal | Role |
|---|---|---|
| bronze, ops | sa-loader | BigQuery Data Editor |
| bronze, ops | sa-dbt | BigQuery Data Viewer |
| silver, gold, metrics | sa-dbt | BigQuery Data Editor |
| gold, metrics | sa-app | BigQuery Data Viewer |
| bronze, silver, gold, metrics, ops | sa-cloudbuild | BigQuery Data Viewer |
| silver_ci, gold_ci, metrics_ci | sa-cloudbuild | BigQuery Data Editor |

**CLI** (BigQuery SQL `GRANT` statements):
```bash
G() { bq query --use_legacy_sql=false --location=$REGION --project_id=$PROJECT_ID \
  "GRANT \`$3\` ON SCHEMA \`$PROJECT_ID.$2\` TO 'serviceAccount:$1'" >/dev/null && echo "$2: $3 to $1"; }
G $(SA loader) bronze  roles/bigquery.dataEditor
G $(SA loader) ops     roles/bigquery.dataEditor
G $(SA dbt)    bronze  roles/bigquery.dataViewer
G $(SA dbt)    ops     roles/bigquery.dataViewer
for ds in silver gold metrics; do G $(SA dbt) $ds roles/bigquery.dataEditor; done
G $(SA app)    gold    roles/bigquery.dataViewer
G $(SA app)    metrics roles/bigquery.dataViewer
for ds in bronze silver gold metrics ops; do G $(SA cloudbuild) $ds roles/bigquery.dataViewer; done
for ds in silver_ci gold_ci metrics_ci; do G $(SA cloudbuild) $ds roles/bigquery.dataEditor; done
```

### 6.4 Bucket-level roles
**Console:** **Cloud Storage → your bucket → Permissions → Grant access**:

| Principal | Role | Why |
|---|---|---|
| sa-loader | Storage Object Viewer | read source files |
| sa-dbt | Storage Object Creator | save run history and the build manifest |
| sa-cloudbuild | Storage Object Viewer | read the build manifest in CI |

**CLI**
```bash
B() { gcloud storage buckets add-iam-policy-binding gs://$1 --member="serviceAccount:$2" --role=$3 >/dev/null && echo "$1: $3 to $2"; }
B $BUCKET $(SA loader)     roles/storage.objectViewer
B $BUCKET $(SA dbt)        roles/storage.objectCreator
B $BUCKET $(SA cloudbuild) roles/storage.objectViewer
```

### 6.5 "Act as" for CI/CD
**Console:** **IAM & Admin → Service accounts → sa-loader → Permissions → Grant access**: principal
sa-cloudbuild, role **Service Account User**. Repeat on sa-dbt and sa-app.
```bash
for sa in loader dbt app; do
  gcloud iam service-accounts add-iam-policy-binding $(SA $sa) \
    --member="serviceAccount:$(SA cloudbuild)" --role=roles/iam.serviceAccountUser >/dev/null && echo "actAs $sa"
done
```
**Check:** **IAM & Admin → IAM** (tick *Include Google-provided role grants*) lists the project
roles; each dataset's **Sharing → Permissions** shows its grants.

---

## Module 7: Connect BigQuery to Gemini

> **Learn.** BigQuery can call **Vertex AI** models (Gemini for text, embedding models for vectors)
> straight from SQL with `AI.GENERATE` and `AI.EMBED`. It does so through a **connection**: a
> BigQuery resource with its own Google-managed service account. That account needs the
> **Vertex AI User** role. The AI tables (fraud briefs, data-quality explanations, RAG answers,
> executive summaries) are ordinary dbt models using this connection.

**Console:** **BigQuery → Explorer → + Add → Connections to external data sources**. Connection type
**Vertex AI remote models, remote functions and BigLake (Cloud Resource)**; Connection ID
`vertex-ai`; location **Region** `us-central1` → **Create connection**. Open it (under
*External connections*) and copy the **Service account ID**. Then **IAM & Admin → IAM → Grant
access** to that account with the role **Vertex AI User**.

**CLI**
```bash
bq mk --connection --location=$REGION --project_id=$PROJECT_ID --connection_type=CLOUD_RESOURCE vertex-ai
CONN_SA=$(bq show --format=json --connection $PROJECT_ID.$REGION.vertex-ai | python3 -c 'import json,sys; print(json.load(sys.stdin)["cloudResource"]["serviceAccountId"])')
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$CONN_SA" --role=roles/aiplatform.user --condition=None
```
**Check:** run this in the BigQuery console or with `bq query`. Wait a minute after granting.
```sql
SELECT AI.GENERATE('Reply with: connection ok',
  connection_id => '<PROJECT_ID>.us-central1.vertex-ai', endpoint => 'gemini-3.5-flash').result
```

---

## Module 8: Container images (Artifact Registry + Cloud Build)

> **Learn.** The loader, dbt and the app each run as a **container image**: the code plus everything
> it needs, described by its `Dockerfile` (open `loader/Dockerfile`; it's short).
> - **Artifact Registry** stores images.
> - **Cloud Build** builds them in Google's cloud from your source folder, so you don't need Docker locally.

### 8.1 The registry
**Console:** **Artifact Registry → Create repository**: name `globalmart`, format **Docker**, mode
Standard, location **Region** `us-central1` → **Create**.
```bash
gcloud artifacts repositories create globalmart --repository-format=docker --location=$REGION
```

### 8.2 Build the three images (~5 min)
```bash
for img in loader dbt app; do
  gcloud builds submit $img --region=$REGION --tag $REPO/$img:latest
done
# Manual CI runs (Module 16) stage source in this bucket, created by the first build:
B ${PROJECT_ID}_cloudbuild $(SA cloudbuild) roles/storage.objectViewer
```
**Check:** **Artifact Registry → globalmart** shows `loader`, `dbt` and `app`. **Cloud Build →
History** shows three green builds.

---

## Module 9: The Bronze loader, run on its own

> **Learn.** **Cloud Run jobs** run a container to completion and bill only while it runs. The loader
> lists the bucket, skips files already recorded in `ops.ingest_log`, converts JSON arrays to
> newline-delimited JSON, and appends each file to `bronze.raw_<entity>` with every column as text,
> plus `_source_file` and `_load_timestamp`. **Environment variables** tell it which project and
> bucket to use; the **service account** decides what it may touch.

**Console:** **Cloud Run → Jobs → Deploy container**. Image URL `…/globalmart/loader:latest`
(**Select** browses Artifact Registry); job name `globalmart-loader`; region `us-central1`.
- **Container(s)** tab: memory **1 GiB**, CPU **1**; **Settings**: task timeout **30 min**, max
  retries **1**.
- **Variables & secrets** tab: `GCP_PROJECT` = your project ID, `RAW_BUCKET` = your bucket name,
  `BQ_LOCATION` = `us-central1`.
- **Security** tab: service account **sa-loader**.
- **Create**.

**CLI**
```bash
gcloud run jobs create globalmart-loader --region=$REGION --image=$REPO/loader:latest \
  --service-account=$(SA loader) --tasks=1 --max-retries=1 --task-timeout=1800s --cpu=1 --memory=1Gi \
  --set-env-vars=GCP_PROJECT=$PROJECT_ID,RAW_BUCKET=$BUCKET,BQ_LOCATION=$REGION
```

**Run it:** **Execute** on the job page, or:
```bash
gcloud run jobs execute globalmart-loader --region=$REGION --wait
```
**Check:** open the execution's **Logs**: *"205 new … done: 205 files loaded"*. Then in BigQuery:
```sql
SELECT 'customers' t, COUNT(*) n FROM bronze.raw_customers UNION ALL
SELECT 'orders', COUNT(*) FROM bronze.raw_orders UNION ALL
SELECT 'transactions', COUNT(*) FROM bronze.raw_transactions UNION ALL
SELECT 'returns', COUNT(*) FROM bronze.raw_returns            -- 1,180 / 53,750 / 101,624 / 8,506
```
**Try:** run the job again. The log says *"205 already loaded, 0 new"*: each file is loaded once.
Look at `bronze.raw_customers`: the same customer ID sits in four different columns
(`customer_id`, `customerid`, `cust_id`, `customer_identifier`). Cleaning that up is Silver's job.

---

## Module 10: dbt, from Bronze to GenAI

> **Learn.** **dbt** turns SELECT statements into tables and runs them in dependency order. It also
> tests the results and stops when a test fails. Open `dbt/models/`:
> - `silver/`: `staging/` harmonises and parses; `clean/` keeps rows passing all 23 quality rules
>   (defined once in `dbt/macros/rules/silver_rules.sql`); `quarantine/rejected_records` keeps one row
>   per failure; `audit/pipeline_audit_log` checks *Bronze = Silver + rejected*.
> - `gold/`: dimensions (stable hash keys, an Unknown member `-1`, SCD Type 2 customers), facts, a
>   refund-allocation bridge. **Contracts** lock every column's name and type.
> - `metrics/`: business aggregates. `genai/`: Gemini models. `reporting/`: one view per dashboard chart.
>
> The job runs `dbt build --target prod` (models + tests + snapshot), saves `run_results.json` to
> `gs://<bucket>/dbt_runs/` and exits with dbt's code, so a failed test fails the job.

**Console:** **Cloud Run → Jobs → Deploy container**: image `…/dbt:latest`, name `globalmart-dbt`,
memory **2 GiB**, CPU **2**, task timeout **60 min**, max retries **0** (a failing test must stop,
not retry), variables `GCP_PROJECT` and `RAW_BUCKET`, service account **sa-dbt**. **Create**.

**CLI**
```bash
gcloud run jobs create globalmart-dbt --region=$REGION --image=$REPO/dbt:latest \
  --service-account=$(SA dbt) --tasks=1 --max-retries=0 --task-timeout=3600s --cpu=2 --memory=2Gi \
  --set-env-vars=GCP_PROJECT=$PROJECT_ID,RAW_BUCKET=$BUCKET
gcloud run jobs execute globalmart-dbt --region=$REGION --wait      # ~6 min on the first run
```
**Check:** the logs end with *"Done. PASS=… ERROR=0"*. In BigQuery:
```sql
SELECT entity, bronze_count, silver_count, rejected_count, reconciliation_diff
FROM silver.pipeline_audit_log ORDER BY entity;                          -- every diff = 0
SELECT COUNT(*) FROM gold.dim_customers WHERE is_current AND customer_sk != -1;   -- 590
SELECT customer_name, anomaly_score, investigation_brief
FROM gold.flagged_return_customers ORDER BY anomaly_score DESC LIMIT 3;  -- Gemini-written briefs
```
**Try (optional, locally):** dbt runs from your computer too, using your ADC sign-in:
```bash
cd dbt && ../.venv/bin/dbt build --profiles-dir . --select clean_orders+ && cd ..
```

---

## Module 11: Orchestrate the pipeline with Cloud Workflows

> **Learn.** **Cloud Workflows** runs steps in order, waits for each one, and fails if any step
> fails. `workflows/globalmart_e2e.yaml` has two steps: run the loader job, then run the dbt job.
> The workflow's identity (`sa-workflows`) may start exactly these two jobs.

The file has placeholders (`${project}`…), so fill them in first:
```bash
sed -e "s/\${project}/$PROJECT_ID/g" -e "s/\${region}/$REGION/g" \
    -e "s/\${loader}/globalmart-loader/g" -e "s/\${dbt}/globalmart-dbt/g" -e 's/\$\${/${/g' \
    workflows/globalmart_e2e.yaml > /tmp/globalmart_e2e.yaml
cat /tmp/globalmart_e2e.yaml
```
Allow the workflow to start the jobs. **Console:** **Cloud Run → Jobs → globalmart-loader →
Permissions → Grant access**: sa-workflows, role **Cloud Run Invoker**; repeat for globalmart-dbt.
```bash
for job in globalmart-loader globalmart-dbt; do
  gcloud run jobs add-iam-policy-binding $job --region=$REGION --member="serviceAccount:$(SA workflows)" --role=roles/run.invoker >/dev/null
done
```
Create the workflow. **Console:** **Workflows → Create**: name `globalmart-e2e`, region
`us-central1`, service account **sa-workflows** → **Next** → paste `/tmp/globalmart_e2e.yaml` →
**Deploy**.
```bash
gcloud workflows deploy globalmart-e2e --location=$REGION --source=/tmp/globalmart_e2e.yaml \
  --service-account=$(SA workflows) --call-log-level=log-errors-only
```
**Run it:** **Execute** in the console, or:
```bash
gcloud workflows run globalmart-e2e --location=$REGION        # ~8 min → state: SUCCEEDED
```
**Check:** **Workflows → globalmart-e2e → Executions** shows both steps green. This one command is
now the whole data pipeline. If the first run fails with *IAM permission denied*, the new grant
hasn't propagated yet: wait a minute and run it again.

---

## Module 12: Try Gemini in SQL yourself

> **Learn.** The AI tables you saw are plain SQL calling Gemini. Open
> `dbt/models/genai/flagged_return_customers.sql`: fraud scores are computed in SQL, and Gemini only
> writes the brief for customers already flagged. Retrieval (RAG) uses `AI.EMBED` to turn text
> into vectors and `VECTOR_SEARCH` to find the closest documents.

Run these in the BigQuery console, replacing `<PROJECT_ID>`:
```sql
-- Ask Gemini about a row of your own data
SELECT vendor_name, return_rate_pct,
  AI.GENERATE(CONCAT('In one sentence, is a ', CAST(return_rate_pct AS STRING),
                     '% return rate high for a retailer?'),
              connection_id => '<PROJECT_ID>.us-central1.vertex-ai', endpoint => 'gemini-3.5-flash').result AS opinion
FROM gold.mv_return_rate_by_vendor;

-- Semantic search over the product documents
SELECT base.doc_text, 1 - distance AS similarity
FROM VECTOR_SEARCH(
  (SELECT * FROM gold.rag_index WHERE pool = 'summary'), 'embedding',
  (SELECT AI.EMBED('best selling products in the West', endpoint => 'text-embedding-005',
                   task_type => 'RETRIEVAL_QUERY', connection_id => '<PROJECT_ID>.us-central1.vertex-ai').result AS q),
  'q', top_k => 3, distance_type => 'COSINE');
```

---

## Module 13: The data agent (questions in plain English)

> **Learn.** The **Conversational Analytics API** hosts *data agents*. An agent turns a question into
> SQL over the tables you allow, runs it as the caller, and answers with text and rows.
> `agent/agent_context.yaml` holds its instructions: join rules, measure definitions, example
> queries and a glossary. Good instructions are the difference between right and plausible-but-wrong
> answers.

```bash
.venv/bin/python agent/data_agent.py deploy     # creates "globalmart-agent" over 20 tables
.venv/bin/python agent/data_agent.py ask "Which vendor has the highest return rate?"
.venv/bin/python agent/data_agent.py test       # 10 questions vs known answers: expect 10/10
```
**Console:** you can also chat with it under **BigQuery → Agents** (Conversational Analytics).

**Try:** ask *"What were total sales in 2025?"* and *"What was the refund amount for returns in
2024?"*, then compare the SQL: the first joins dates on the **order** date, the second on the
**return** date. The instructions taught it that.

---

## Module 14: The web app on Cloud Run

> **Learn.** A **Cloud Run service** serves HTTP requests from a container and scales to zero when
> idle. **Require authentication** means only principals with **Cloud Run Invoker** can reach it.
> Everyone else gets 403. The app (React + Express) runs only the 27 SQL files in `app/queries/`
> (an allowlist with typed parameters), and its Ask page talks to the data agent. It runs as
> `sa-app`, which can only read.

**Console:** **Cloud Run → Services → Deploy container**: image `…/app:latest`, name
`globalmart-app`, region `us-central1`, **Authentication: Require authentication**, **CPU is only
allocated during request processing**, minimum instances **0**, maximum **2**, memory **512 MiB**,
variables `GCP_PROJECT` = your project ID and `AGENT_ID` = `globalmart-agent`, service account
**sa-app** → **Create**.

**CLI**
```bash
gcloud run deploy globalmart-app --region=$REGION --image=$REPO/app:latest --service-account=$(SA app) \
  --no-allow-unauthenticated --min-instances=0 --max-instances=2 --cpu=1 --memory=512Mi --cpu-throttling \
  --set-env-vars=GCP_PROJECT=$PROJECT_ID,AGENT_ID=globalmart-agent
```
**Open it** through an authenticated local proxy, then browse to <http://localhost:8080>:
```bash
gcloud run services proxy globalmart-app --region=$REGION --port=8080   # answer Y to install the proxy component
```
**Check:** the dashboard pages load, your email shows in the top-right corner, and the **Ask** page
answers questions. Opening the service URL directly without signing in returns **403**: that's
authentication working. To let a friend in:
```bash
gcloud run services add-iam-policy-binding globalmart-app --region=$REGION --member="user:friend@gmail.com" --role=roles/run.invoker
```

---

## Module 15: Dashboards in Looker Studio

> **Learn.** **Looker Studio** is Google's free dashboard tool. It reads BigQuery directly. Each chart
> here reads one `gold.rpt_*` view, so the chart logic lives in git (dbt), not inside the report.

Follow [`looker_studio.md`](looker_studio.md). In its "create the report" link, replace
`globalmart-gcp-lab` with **your project ID**, or create a blank report and add the nine
`gold.rpt_*` views with **Add data → BigQuery**.

---

## Module 16: CI/CD from GitHub

> **Learn.** **Cloud Build triggers** run a build file (`cloudbuild.yaml`) on every push. This one:
> 1. runs the tests in parallel: loader tests; app tests and a dry run of all 27 app queries;
>    **dbt CI**, which builds only the changed models (and those downstream) into the `*_ci`
>    datasets, comparing against the last production build;
> 2. builds the three images, **only if every test passed**;
> 3. deploys the app and points both jobs at the new images.
>
> Cloud Build stores your GitHub authorization in **Secret Manager**.

1. **Fork** this repository on GitHub (button at the top right of the repo page).
2. Let Cloud Build's service agent manage the token secret, and create the GitHub connection:
   ```bash
   gcloud projects add-iam-policy-binding $PROJECT_ID --condition=None \
     --member="serviceAccount:service-$PROJECT_NUMBER@gcp-sa-cloudbuild.iam.gserviceaccount.com" --role=roles/secretmanager.admin
   gcloud builds connections create github globalmart-github --region=$REGION
   ```
3. Open the link it prints. Sign in to GitHub → **Authorize Google Cloud Build** → **install the
   Cloud Build GitHub App** on your fork. Then check:
   ```bash
   gcloud builds connections describe globalmart-github --region=$REGION --format='value(installationState.stage)'   # COMPLETE
   ```
   Console alternative: **Cloud Build → Repositories (2nd gen) → Create host connection → GitHub**,
   region `us-central1`.
4. Link the repo and create the trigger. **Console:** **Cloud Build → Triggers → Create trigger**:
   name `globalmart-main`, region `us-central1`, event **Push to a branch**, your linked repo, branch
   `^main$`, configuration **Cloud Build configuration file** `cloudbuild.yaml`, service account
   **sa-cloudbuild**.
   ```bash
   gcloud builds repositories create gcp-globalmart --connection=globalmart-github --region=$REGION \
     --remote-uri=https://github.com/<your-github-user>/gcp-globalmart.git
   gcloud builds triggers create github --name=globalmart-main --region=$REGION \
     --repository=projects/$PROJECT_ID/locations/$REGION/connections/globalmart-github/repositories/gcp-globalmart \
     --branch-pattern='^main$' --build-config=cloudbuild.yaml \
     --service-account=projects/$PROJECT_ID/serviceAccounts/sa-cloudbuild@$PROJECT_ID.iam.gserviceaccount.com
   ```
5. Push a commit to `main` and watch **Cloud Build → History**: 6 green steps in ~7 minutes.

**Try:** rename `return_rate_pct` (the `as return_rate_pct` alias) in
`dbt/models/gold/views/mv_return_rate_by_vendor.sql` and push. The `dbt-ci` step fails: the model's
**contract** still promises `return_rate_pct`, so dbt refuses to build it, and nothing is deployed.
(The app's query check guards the other direction: it fails if an app query asks for a column that
production Gold doesn't have.)

---

## Module 17: Check every number

The repo holds the known-good results for the pipeline (`tests/expected_results/`). After a full run:
```bash
.venv/bin/python tests/check_expected_results.py      # 10 checks, expect all OK
```
They cover: 205 files and every Bronze row count; reconciliation 0 for all entities; failures per
quality rule; Gold row counts (590 customers, 94,153 sales lines); revenue by year × region;
allocated refunds ($2,478,124.40); the fraud flag rate (22.52 %, 109 customers); metrics row counts.

---

## Module 18: Operate, troubleshoot, clean up

### Day to day
| Task | How |
|---|---|
| Refresh everything | `gcloud workflows run globalmart-e2e --location=$REGION` |
| New source files | add them to `source_data/`, `gcloud storage rsync -r source_data gs://$BUCKET/source_data`, run the workflow (only new files are loaded) |
| Rerun only the AI models | `gcloud run jobs execute globalmart-dbt --region=$REGION --args="build,--target,prod,--select,tag:genai"` |
| See what dbt did | `gcloud storage ls gs://$BUCKET/dbt_runs/` (one `run_results.json` per run) |
| Spend | Console → **Billing → Reports** |

### Troubleshooting
| Symptom | Fix |
|---|---|
| *Permission denied* or *API not enabled* just after enabling or granting | Propagation delay: wait 1–2 minutes and retry |
| `gcloud builds submit` fails with permission errors | New projects build as the Compute Engine default account. Grant `PROJECT_NUMBER-compute@developer.gserviceaccount.com` *Artifact Registry Writer*, *Storage Object Viewer* and *Logs Writer*, or add `--service-account=projects/$PROJECT_ID/serviceAccounts/sa-cloudbuild@$PROJECT_ID.iam.gserviceaccount.com` |
| Budget creation: `INVALID_ARGUMENT` | Use your billing account's currency (`900INR`, not `10USD`) |
| Loader or dbt job fails | **Cloud Run → Jobs → job → Executions → Logs**; for dbt the failing test's name points at the rule or contract |
| `AI.GENERATE`: unknown endpoint | Model names change: check the current Gemini models in the BigQuery `AI.GENERATE` docs and set `genai_endpoint` in `dbt/dbt_project.yml` |
| App returns 403 | Expected without sign-in: use the proxy, or grant *Cloud Run Invoker* |
| GitHub connection stuck at `PENDING_USER_OAUTH` | Reopen the link from `gcloud builds connections describe globalmart-github --region=$REGION` and finish both screens |
| CI step `dbt-ci` can't find the manifest | Run the pipeline once first; the dbt job saves it |

### Clean up
Delete in reverse order of creation, or delete the whole project (step 9) to remove everything at once.
```bash
.venv/bin/python agent/data_agent.py delete                                   # 1. data agent
gcloud builds triggers delete globalmart-main --region=$REGION --quiet         # 2. CI trigger and connection
gcloud builds connections delete globalmart-github --region=$REGION --quiet
gcloud run services delete globalmart-app --region=$REGION --quiet             # 3. app
gcloud workflows delete globalmart-e2e --location=$REGION --quiet              # 4. workflow
gcloud run jobs delete globalmart-loader --region=$REGION --quiet              # 5. jobs
gcloud run jobs delete globalmart-dbt --region=$REGION --quiet
gcloud artifacts repositories delete globalmart --location=$REGION --quiet     # 6. images
for ds in bronze silver gold metrics ops silver_ci gold_ci metrics_ci; do bq rm -r -f -d $PROJECT_ID:$ds; done   # 7. data
bq rm -f --connection $PROJECT_ID.$REGION.vertex-ai
gcloud storage rm -r gs://$BUCKET
for sa in loader dbt app workflows cloudbuild; do gcloud iam service-accounts delete sa-$sa@$PROJECT_ID.iam.gserviceaccount.com --quiet; done   # 8. identities
gcloud projects delete $PROJECT_ID                                              # 9. or just this: everything, 30-day recovery
```
Delete the budget under **Billing → Budgets & alerts** and the report in Looker Studio.

---

## Next step: the same thing as code

You've now created every resource by hand and know what each one does. The `terraform/` folder
declares exactly these resources as code: open `terraform/main.tf`, `jobs.tf`, `workflows.tf` and
`cicd.tf` and you'll recognise each module of this guide. In a fresh project, the README's
*"Set up with Terraform"* section creates it all in a few commands.

## Appendix: what you built

| Resource | Name | Module |
|---|---|---|
| Billing account, budget | `globalmart monthly` | 1, 2.3 |
| Project | your `PROJECT_ID` | 2 |
| APIs | 12 services | 3 |
| Bucket | `<project>-globalmart-raw` | 4 |
| Datasets | `bronze` `silver` `gold` `metrics` `ops` + `*_ci` | 5 |
| Service accounts | `sa-loader` `sa-dbt` `sa-app` `sa-workflows` `sa-cloudbuild` | 6 |
| BigQuery connection | `us-central1.vertex-ai` | 7 |
| Registry and images | `globalmart`: `loader` `dbt` `app` | 8 |
| Cloud Run jobs | `globalmart-loader`, `globalmart-dbt` | 9, 10 |
| Workflow | `globalmart-e2e` | 11 |
| Data agent | `globalmart-agent` | 13 |
| Cloud Run service | `globalmart-app` | 14 |
| Looker Studio report | GlobalMart Intelligence | 15 |
| Cloud Build connection and trigger | `globalmart-github`, `globalmart-main` | 16 |

Tables are never created by hand: the loader creates `bronze.raw_*` and `ops.ingest_log`, and dbt
creates everything in `silver`, `gold` and `metrics`, including `silver.customers_snapshot`, the
customer history. Never drop that table casually.
