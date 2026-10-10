# Deployment guide: GlobalMart on Google Cloud, from zero

This guide takes you from "no Google Cloud account" to the whole platform running: the Bronze
loader, dbt (Silver → Gold → Metrics → GenAI), the workflow, the data agent, the web app,
Looker Studio and CI/CD.

There are two ways to create the cloud resources:

- **Path A: Terraform (recommended, ~30 min).** One tool creates every resource exactly as this
  repo expects.
- **Path B: by hand (~2 h).** Every resource created yourself, in the Cloud console or with
  copy-paste `gcloud`/`bq` commands. Use it to learn what each piece is, or if you can't use Terraform.

Parts 1–3 (accounts, tools, project) and Parts 5–10 (run, verify, use, CI/CD) are the same for
both paths.

| Part | What | Path |
|---|---|---|
| 1 | Google account, billing account, budget | both |
| 2 | Install the tools on your computer | both |
| 3 | Sign in, create the project, clone the repo | both |
| 4A | Create all resources with Terraform | A |
| 4B | Create all resources by hand | B |
| 5 | Upload the data and run the pipeline | both |
| 6 | Verify the results | both |
| 7 | Data agent | both |
| 8 | Web app | both |
| 9 | Looker Studio report | both |
| 10 | CI/CD from GitHub (optional) | both |
| 11 | Day-to-day operation, troubleshooting, teardown | both |

**Cost.** Everything fits in the free tiers for normal lab use (BigQuery 1 TiB queries and 10 GiB
storage per month, Cloud Run, Cloud Build 2,500 build-minutes). Gemini calls cost cents per full
run. Part 1 sets a budget alert so you're warned before any real spend.

---

## Part 1: Google account, billing account and budget

### 1.1 Google account
1. If you don't have one, create a Google account at <https://accounts.google.com/signup>. A
   personal Gmail works; this project was built on one.
2. Open <https://console.cloud.google.com>, sign in, choose your country and accept the Terms of
   Service.

### 1.2 Billing account
Google Cloud needs a billing account, even for free-tier use.
1. In the console, open the menu (☰) → **Billing**. Or go to <https://console.cloud.google.com/billing>.
2. Click **Manage billing accounts** → **Create account**. New users are usually offered the
   **free trial** ($300 credit for 90 days); accept it if shown.
3. Fill in:
   - **Name:** e.g. `my-billing`
   - **Country** and **currency.** The currency can't be changed later, and budgets must use it.
   - **Account type:** Individual
   - **Payment method:** a card. It's verified and may get a small temporary hold. You aren't
     charged during the trial unless you upgrade.
4. Click **Submit and enable billing**.
5. Note the **Billing account ID** (format `XXXXXX-XXXXXX-XXXXXX`), shown on the billing
   account's **Overview** page. You'll need it in Part 3.

### 1.3 Budget alert
Do this right after creating the project in Part 3.3; it's listed here so you don't forget.
1. Console → **Billing** → your account → **Budgets & alerts** → **Create budget**.
2. **Name:** `globalmart monthly`. **Projects:** select your project only.
3. **Amount:** a specified amount, e.g. US$10, or the equivalent in your billing currency (₹900, €10…).
4. **Thresholds:** 50 %, 90 %, 100 % of actual spend. Leave email alerts to billing admins on.
5. **Finish.**

A budget only *alerts*; it doesn't stop spending. The cost guardrails in this repo (scale to
zero, query caps, bounded Gemini calls) keep usage low.

---

## Part 2: Install the tools

| Tool | Version | Used for |
|---|---|---|
| Git | any | cloning the repo |
| Google Cloud CLI (`gcloud`, `bq`, `gsutil`) | current | everything in GCP |
| Terraform | ≥ 1.6 | Path A only |
| Python | 3.12 | dbt, loader, data agent script |
| Node.js | 24 | the web app (only to develop it locally; images are built in the cloud) |

You **don't** need Docker: images are built by Cloud Build.

### macOS
```bash
# Homebrew (https://brew.sh) if you don't have it:
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

brew install git python@3.12 node@24
brew install --cask gcloud-cli
brew tap hashicorp/tap && brew install hashicorp/tap/terraform
```
Without Homebrew (or without admin rights), install `gcloud` into your home folder:
```bash
curl -fsSLO https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-darwin-arm.tar.gz  # Intel Mac: ...-darwin-x86_64.tar.gz
tar -xzf google-cloud-cli-darwin-*.tar.gz -C ~ && ~/google-cloud-sdk/install.sh --quiet
echo 'export PATH="$HOME/google-cloud-sdk/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc
```
Terraform without Homebrew: download the zip for your platform from
<https://developer.hashicorp.com/terraform/install>, unzip it, and put `terraform` in a folder on your `PATH`
(e.g. `~/.local/bin`).

### Windows
1. Git: <https://git-scm.com/download/win>, then use **Git Bash** for all commands in this guide.
2. Python 3.12: <https://www.python.org/downloads/> (tick **Add python.exe to PATH**).
3. Node.js 24 LTS: <https://nodejs.org>.
4. Google Cloud CLI: the installer from <https://cloud.google.com/sdk/docs/install#windows>.
5. Terraform: `winget install Hashicorp.Terraform`, or the zip from the HashiCorp site.

### Linux (Debian/Ubuntu)
```bash
sudo apt-get update && sudo apt-get install -y git python3.12 python3.12-venv curl gnupg
# Node 24
curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash - && sudo apt-get install -y nodejs
# Google Cloud CLI
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list
sudo apt-get update && sudo apt-get install -y google-cloud-cli
# Terraform
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update && sudo apt-get install -y terraform
```

### Check
```bash
git --version && gcloud --version | head -1 && bq version && terraform version | head -1 && python3.12 --version && node --version
```

---

## Part 3: Sign in, create the project, clone the repo

### 3.1 Sign in
Two sign-ins are needed. `gcloud` commands use the first; Terraform, dbt and the Python and Node
tools use the second (Application Default Credentials, "ADC").
```bash
gcloud auth login                         # opens a browser: pick your Google account, Allow
gcloud auth application-default login     # browser again: Allow
```

### 3.2 Choose names
Project IDs are **globally unique**, 6–30 characters, lowercase letters, digits and hyphens. If
`globalmart-gcp-lab` is taken, add a suffix such as `globalmart-lab-1234`. Set these variables in
every new terminal (or add them to `~/.zshrc` / `~/.bashrc`):
```bash
export PROJECT_ID=globalmart-lab-1234             # your project ID
export REGION=us-central1                         # keep this; see the note below
export BILLING_ACCOUNT=XXXXXX-XXXXXX-XXXXXX       # from Part 1.2
export GCP_PROJECT=$PROJECT_ID                    # read by dbt, the loader, the app and the agent script
export BUCKET=$PROJECT_ID-globalmart-raw
export REPO=$REGION-docker.pkg.dev/$PROJECT_ID/globalmart
```
**Region:** keep `us-central1`. It's set in `dbt/profiles.yml` (`location`), `dbt/dbt_project.yml`
(`genai_connection`), `cloudbuild.yaml` (`_REGION`) and as a default in the loader, the app and the
scripts. To use another region, change all of those as well as `REGION`.

### 3.3 Create the project and link billing
Console: top bar project picker → **New project** → name `GlobalMart Lab`, edit the **Project ID**
to your `$PROJECT_ID` → **Create**. Then **Billing** → **My projects** → your project → **Change
billing** → choose your billing account.

Or with the CLI:
```bash
gcloud projects create $PROJECT_ID --name="GlobalMart Lab"
gcloud billing projects link $PROJECT_ID --billing-account=$BILLING_ACCOUNT
gcloud config set project $PROJECT_ID
gcloud auth application-default set-quota-project $PROJECT_ID
export PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')
```
Now create the **budget alert** from Part 1.3. CLI equivalent (use your billing currency, e.g. `900INR`):
```bash
gcloud services enable billingbudgets.googleapis.com
gcloud billing budgets create --billing-account=$BILLING_ACCOUNT --display-name="globalmart monthly" \
  --budget-amount=10USD --filter-projects="projects/$PROJECT_NUMBER" --calendar-period=month \
  --threshold-rule=percent=0.5 --threshold-rule=percent=0.9 --threshold-rule=percent=1.0
```

### 3.4 Clone the repo and set up Python
```bash
git clone https://github.com/srinivasaddanki1978/gcp-globalmart.git   # or your fork (needed for CI/CD, Part 10)
cd gcp-globalmart
python3.12 -m venv .venv
.venv/bin/pip install -r loader/requirements.txt -r dbt/requirements.txt pytest
(cd dbt && ../.venv/bin/dbt deps)
```
The 205 source files are already in `source_data/`.

---

## Part 4A: Create all resources with Terraform

Terraform creates every resource in the inventory (Appendix A). The first run happens in three
steps, because the Cloud Run jobs and the app need their container images to exist first.

**Step 1: foundation (APIs + image registry).**
```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
sed -i.bak "s/globalmart-gcp-lab/$PROJECT_ID/" terraform.tfvars   # or edit project_id by hand
terraform init
terraform apply -target=google_artifact_registry_repository.images   # type "yes"; also enables the APIs
cd ..
```
If you get *"Permission … denied … (or it may not exist)"* right after the APIs are enabled, wait a
minute and run the command again. New APIs take a moment to activate.

**Step 2: build the three images** with Cloud Build (~5 min):
```bash
for img in loader dbt app; do
  gcloud builds submit $img --region=$REGION --tag $REPO/$img:latest
done
```

**Step 3: everything else.**
```bash
cd terraform && terraform apply && cd ..      # type "yes"; ~60 resources
```
Now go to **Part 5**.

> Terraform keeps its state in `terraform/terraform.tfstate` on your computer. Keep that file:
> `terraform destroy` needs it. It's ignored by git.

---

## Part 4B: Create all resources by hand

Each step gives the console clicks and the equivalent CLI commands; do one or the other. The
result is identical to Path A. Use the exact names shown: the code and the workflow refer to them.

### B1. Enable the APIs
Console: **APIs & Services → Library**, search for and **Enable** each: BigQuery API, BigQuery
Connection API, Cloud Storage, Vertex AI API, Artifact Registry API, Cloud Run Admin API,
Workflows API, Cloud Build API, Identity and Access Management (IAM) API, Gemini Data Analytics
API, Gemini for Google Cloud API, Secret Manager API.
```bash
gcloud services enable bigquery.googleapis.com bigqueryconnection.googleapis.com storage.googleapis.com \
  aiplatform.googleapis.com artifactregistry.googleapis.com run.googleapis.com workflows.googleapis.com \
  cloudbuild.googleapis.com iam.googleapis.com geminidataanalytics.googleapis.com \
  cloudaicompanion.googleapis.com secretmanager.googleapis.com
```

### B2. Cloud Storage bucket for the source files
Console: **Cloud Storage → Buckets → Create**:
- **Name:** `<PROJECT_ID>-globalmart-raw` (the value of `$BUCKET`)
- **Location type:** Region, `us-central1`
- **Storage class:** Standard
- **Access control:** Uniform, with **Enforce public access prevention** ticked
- **Create**
```bash
gcloud storage buckets create gs://$BUCKET --location=$REGION \
  --uniform-bucket-level-access --public-access-prevention
```

### B3. BigQuery datasets
Five production datasets and three CI datasets, all in `us-central1`. Console: **BigQuery →
Explorer → ⋮ next to your project → Create dataset**. Set **Dataset ID**, **Location type:
Region, us-central1**, **Create dataset**. For the three `*_ci` datasets, also tick
**Enable table expiration** and enter 3 days.
```bash
for ds in bronze silver gold metrics ops; do
  bq --location=$REGION mk --dataset --description "GlobalMart $ds" $PROJECT_ID:$ds
done
for ds in silver_ci gold_ci metrics_ci; do
  bq --location=$REGION mk --dataset --default_table_expiration 259200 --description "dbt CI (temporary)" $PROJECT_ID:$ds
done
```

### B4. BigQuery → Vertex AI connection (for Gemini and embeddings)
Console: **BigQuery → Explorer → + Add → Connections to external data sources** → Connection
type **Vertex AI remote models, remote functions and BigLake (Cloud Resource)** → Connection ID
`vertex-ai` → Location **Region us-central1** → **Create connection**. Open it and copy its
**Service account ID**.
```bash
bq mk --connection --location=$REGION --project_id=$PROJECT_ID --connection_type=CLOUD_RESOURCE vertex-ai
CONN_SA=$(bq show --format=json --connection $PROJECT_ID.$REGION.vertex-ai | python3 -c 'import json,sys; print(json.load(sys.stdin)["cloudResource"]["serviceAccountId"])')
echo $CONN_SA
```
Give that service account **Vertex AI User**. Console: **IAM & Admin → IAM → Grant access**:
principal `$CONN_SA`, role *Vertex AI User*.
```bash
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$CONN_SA" --role=roles/aiplatform.user --condition=None
```

### B5. Artifact Registry repository for the images
Console: **Artifact Registry → Create repository** → Name `globalmart`, Format **Docker**,
Mode Standard, Location **Region us-central1** → **Create**.
```bash
gcloud artifacts repositories create globalmart --repository-format=docker --location=$REGION \
  --description="Images for the loader, dbt and app"
```

### B6. Service accounts
Six identities, each allowed only what it needs. Console: **IAM & Admin → Service accounts → Create
service account** (name only; no roles on this screen).

| Account | Runs |
|---|---|
| `sa-loader` | Bronze loader job |
| `sa-dbt` | dbt job |
| `sa-app` | Web app (read-only) |
| `sa-workflows` | The end-to-end workflow |
| `sa-cloudbuild` | CI/CD builds |

```bash
for sa in loader dbt app workflows cloudbuild; do
  gcloud iam service-accounts create sa-$sa --display-name="GlobalMart $sa"
done
SA() { echo "sa-$1@$PROJECT_ID.iam.gserviceaccount.com"; }
```

### B7. Permissions (IAM)
Project-level roles. Console: **IAM & Admin → IAM → Grant access**, one row per line below.
```bash
P() { gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$1" --role=$2 --condition=None --quiet >/dev/null && echo "$1 $2"; }
for sa in loader dbt app cloudbuild; do P $(SA $sa) roles/bigquery.jobUser; done   # run queries
P $(SA app) roles/geminidataanalytics.dataAgentUser                                 # app → data agent
P $(SA app) roles/cloudaicompanion.user
P $(SA workflows) roles/run.viewer                                                  # workflow reads job runs
P $(SA workflows) roles/logging.logWriter
P $(SA cloudbuild) roles/run.developer                                              # CI deploys
P $(SA cloudbuild) roles/logging.logWriter
P $(SA cloudbuild) roles/artifactregistry.writer
# The Vertex connection: Terraform grants this on the connection only; by hand, project level is simplest.
P $(SA dbt) roles/bigquery.connectionUser
P $(SA cloudbuild) roles/bigquery.connectionUser
```
Dataset-level roles. Console: **BigQuery → dataset → Sharing → Permissions → Add principal**.
CLI: BigQuery SQL `GRANT` statements:
```bash
G() { bq query --use_legacy_sql=false --location=$REGION --project_id=$PROJECT_ID \
  "GRANT \`$3\` ON SCHEMA \`$PROJECT_ID.$2\` TO 'serviceAccount:$1'" >/dev/null && echo "$1 $2 $3"; }
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
Bucket-level roles. Console: **Cloud Storage → bucket → Permissions → Grant access**.
```bash
B() { gcloud storage buckets add-iam-policy-binding gs://$1 --member="serviceAccount:$2" --role=$3 >/dev/null && echo "$1 $2 $3"; }
B $BUCKET $(SA loader)     roles/storage.objectViewer    # read source files
B $BUCKET $(SA dbt)        roles/storage.objectCreator   # write run history + prod manifest
B $BUCKET $(SA cloudbuild) roles/storage.objectViewer    # read the prod manifest in CI
```
CI deploys services that run as the other accounts, so it needs **Service Account User** on them.
Console: **Service accounts → sa-loader → Permissions → Grant access** (repeat for sa-dbt and sa-app).
```bash
for sa in loader dbt app; do
  gcloud iam service-accounts add-iam-policy-binding $(SA $sa) \
    --member="serviceAccount:$(SA cloudbuild)" --role=roles/iam.serviceAccountUser >/dev/null && echo "actAs $sa"
done
```

### B8. Build the container images
```bash
for img in loader dbt app; do
  gcloud builds submit $img --region=$REGION --tag $REPO/$img:latest
done
# Manual CI runs stage source in this bucket (it exists after the first build):
B ${PROJECT_ID}_cloudbuild $(SA cloudbuild) roles/storage.objectViewer
```

### B9. Cloud Run job: Bronze loader
Console: **Cloud Run → Jobs → Deploy container**: image `…/globalmart/loader:latest`, job name
`globalmart-loader`, region us-central1. Under **Container**: memory 1 GiB, CPU 1, task timeout 30 min,
max retries 1. **Variables**: `GCP_PROJECT`, `RAW_BUCKET`, `BQ_LOCATION=us-central1`. **Security**:
service account `sa-loader`. **Create**.
```bash
gcloud run jobs create globalmart-loader --region=$REGION --image=$REPO/loader:latest \
  --service-account=$(SA loader) --tasks=1 --max-retries=1 --task-timeout=1800s --cpu=1 --memory=1Gi \
  --set-env-vars=GCP_PROJECT=$PROJECT_ID,RAW_BUCKET=$BUCKET,BQ_LOCATION=$REGION
```

### B10. Cloud Run job: dbt
Same screens: image `…/dbt:latest`, name `globalmart-dbt`, memory 2 GiB, CPU 2, timeout 60 min,
**max retries 0** (a failing test must stop the pipeline), variables `GCP_PROJECT` and `RAW_BUCKET`,
service account `sa-dbt`.
```bash
gcloud run jobs create globalmart-dbt --region=$REGION --image=$REPO/dbt:latest \
  --service-account=$(SA dbt) --tasks=1 --max-retries=0 --task-timeout=3600s --cpu=2 --memory=2Gi \
  --set-env-vars=GCP_PROJECT=$PROJECT_ID,RAW_BUCKET=$BUCKET
```

### B11. Cloud Run service: the web app
Console: **Cloud Run → Services → Deploy container**: image `…/app:latest`, name `globalmart-app`,
region us-central1, **Authentication: Require authentication**, CPU allocated only during
requests, min instances 0, max 2, memory 512 MiB, variables `GCP_PROJECT` and
`AGENT_ID=globalmart-agent`, service account `sa-app`.
```bash
gcloud run deploy globalmart-app --region=$REGION --image=$REPO/app:latest --service-account=$(SA app) \
  --no-allow-unauthenticated --min-instances=0 --max-instances=2 --cpu=1 --memory=512Mi --cpu-throttling \
  --set-env-vars=GCP_PROJECT=$PROJECT_ID,AGENT_ID=globalmart-agent
```

### B12. Cloud Workflows: the end-to-end pipeline
`workflows/globalmart_e2e.yaml` is a Terraform template, so fill in its placeholders first:
```bash
sed -e "s/\${project}/$PROJECT_ID/g" -e "s/\${region}/$REGION/g" \
    -e "s/\${loader}/globalmart-loader/g" -e "s/\${dbt}/globalmart-dbt/g" -e 's/\$\${/${/g' \
    workflows/globalmart_e2e.yaml > /tmp/globalmart_e2e.yaml
gcloud workflows deploy globalmart-e2e --location=$REGION --source=/tmp/globalmart_e2e.yaml \
  --service-account=$(SA workflows) --call-log-level=log-errors-only \
  --description="Bronze loader, then dbt build"
# The workflow may run exactly these two jobs:
for job in globalmart-loader globalmart-dbt; do
  gcloud run jobs add-iam-policy-binding $job --region=$REGION --member="serviceAccount:$(SA workflows)" --role=roles/run.invoker >/dev/null
done
```
Console alternative: **Workflows → Create**, name `globalmart-e2e`, region us-central1, service
account `sa-workflows`, **Next**, paste the contents of `/tmp/globalmart_e2e.yaml`, **Deploy**.
Then on each job: **Cloud Run → Jobs → job → Permissions → Grant** `sa-workflows` the role
*Cloud Run Invoker*.

---

## Part 5: Upload the data and run the pipeline

```bash
gcloud storage rsync -r source_data gs://$BUCKET/source_data      # 205 files, ~16 MB
gcloud workflows run globalmart-e2e --location=$REGION             # ~8 min; prints state: SUCCEEDED
```
What happens: the loader job puts the 205 files into `bronze.raw_*` (every column STRING, each file
logged in `ops.ingest_log`). The dbt job then builds and tests Silver, Gold, Metrics and the GenAI
tables (~135 models, snapshot and tests). Gemini writes the fraud briefs, the data-quality
explanations, the RAG answers and the executive summaries. The first run also embeds ~16.6k RAG
documents, once.

Watch progress: **Workflows → globalmart-e2e → Executions**, or **Cloud Run → Jobs → job → Logs**.

---

## Part 6: Verify the results

```bash
bq query --use_legacy_sql=false --location=$REGION '
SELECT entity, bronze_count, silver_count, rejected_count, reconciliation_diff FROM silver.pipeline_audit_log ORDER BY entity'
```
Expected: `reconciliation_diff` = 0 for all 6 entities. Customers 1,180, orders 53,750,
transactions 101,624, returns 8,506, products 1,774, vendors 7.

```bash
bq query --use_legacy_sql=false --location=$REGION '
SELECT
  (SELECT COUNT(*) FROM gold.dim_customers WHERE is_current AND customer_sk != -1) AS customers,          -- 590
  (SELECT COUNT(*) FROM gold.fact_sales) AS sales_lines,                                                  -- 94,153
  (SELECT COUNT(*) FROM gold.flagged_return_customers) AS flagged,                                        -- 109
  (SELECT ROUND(SUM(allocated_refund), 2) FROM gold.bridge_return_products) AS allocated_refunds'         -- 2,478,124.40
```
The run history (dbt's `run_results.json`) is in `gs://$BUCKET/dbt_runs/`.

The `parity/` scripts compare every layer with the original Databricks build. They need access to
that Databricks workspace and are optional for a fresh deployment.

---

## Part 7: Data agent (natural-language Q&A)

```bash
.venv/bin/python agent/data_agent.py deploy     # creates "globalmart-agent" over 20 tables
.venv/bin/python agent/data_agent.py test       # 10 questions vs golden SQL; expect 10/10 (≥ 9 passes)
.venv/bin/python agent/data_agent.py ask "Which vendor has the highest return rate?"
```
You can also chat with it in the console under **BigQuery → Agents / Conversational Analytics**.
Its instructions are in `agent/agent_context.yaml`; edit them and run `deploy` again.

---

## Part 8: The web app

The app requires sign-in. Open it through an authenticated local proxy:
```bash
gcloud run services proxy globalmart-app --region=$REGION --port=8080   # answer Y if asked to install a component
```
Browse to <http://localhost:8080>. You get 9 dashboard pages and an **Ask** page (the data agent),
with your email in the top-right corner. Project owners can open it; to let someone else in, grant
them *Cloud Run Invoker* on the service:
```bash
gcloud run services add-iam-policy-binding globalmart-app --region=$REGION --member="user:friend@gmail.com" --role=roles/run.invoker
```
(With Terraform, add them to `app_users` in `terraform.tfvars` instead.)

`/dbt-docs` shows the dbt documentation site once CI has generated it (Part 10).

---

## Part 9: Looker Studio report

Follow [`docs/looker_studio.md`](looker_studio.md). In its "Create the report" link, **replace
`globalmart-gcp-lab` with your project ID**, or create a blank report and add the nine
`gold.rpt_*` views with **Add data → BigQuery**.

---

## Part 10: CI/CD from GitHub (optional)

Every push to `main` runs `cloudbuild.yaml`: tests → dbt CI build into `*_ci` datasets → images →
deploy. It needs your own copy of the repo on GitHub.

1. **Fork** the repo on GitHub (button at the top right of the repo page), or push your clone to a new repo.
2. Let Cloud Build store the GitHub token:
   ```bash
   gcloud projects add-iam-policy-binding $PROJECT_ID --condition=None \
     --member="serviceAccount:service-$PROJECT_NUMBER@gcp-sa-cloudbuild.iam.gserviceaccount.com" --role=roles/secretmanager.admin
   gcloud builds connections create github globalmart-github --region=$REGION
   ```
3. The command prints a link. Open it, sign in to GitHub, click **Authorize Google Cloud Build**,
   then **install the Cloud Build GitHub App** on your repo. Check that it finished:
   ```bash
   gcloud builds connections describe globalmart-github --region=$REGION --format='value(installationState.stage)'   # COMPLETE
   ```
   Console alternative: **Cloud Build → Repositories (2nd gen) → Create host connection → GitHub**,
   region us-central1.
4. Link the repo and create the trigger:
   ```bash
   gcloud builds repositories create gcp-globalmart --connection=globalmart-github --region=$REGION \
     --remote-uri=https://github.com/<your-github-user>/gcp-globalmart.git
   gcloud builds triggers create github --name=globalmart-main --region=$REGION \
     --repository=projects/$PROJECT_ID/locations/$REGION/connections/globalmart-github/repositories/gcp-globalmart \
     --branch-pattern='^main$' --build-config=cloudbuild.yaml \
     --service-account=projects/$PROJECT_ID/serviceAccounts/sa-cloudbuild@$PROJECT_ID.iam.gserviceaccount.com
   ```
5. Push a commit to `main` and watch **Cloud Build → History**. All 6 steps should turn green (~7 min).

CI compares changed dbt models against the last production build's manifest, which the dbt job
saves after every successful run. Run the pipeline (Part 5) at least once before the first CI build.

To run CI by hand without GitHub:
```bash
gcloud builds submit --config=cloudbuild.yaml --region=$REGION \
  --service-account=projects/$PROJECT_ID/serviceAccounts/sa-cloudbuild@$PROJECT_ID.iam.gserviceaccount.com
```

---

## Part 11: Operate, troubleshoot, tear down

### Day to day
| Task | Command |
|---|---|
| Refresh all data | `gcloud workflows run globalmart-e2e --location=$REGION` |
| New source files | add them under `source_data/`, `gcloud storage rsync -r source_data gs://$BUCKET/source_data`, then run the workflow (only new files are loaded) |
| Rebuild only GenAI | `gcloud run jobs execute globalmart-dbt --region=$REGION --args="build,--target,prod,--select,tag:genai"` |
| Open the app | `gcloud run services proxy globalmart-app --region=$REGION --port=8080` |
| Ask the agent | `.venv/bin/python agent/data_agent.py ask "…"` |
| Deploy code changes | push to `main` (Part 10), or run CI by hand |
| Check spend | Console → **Billing → Reports** |

### Troubleshooting
| Symptom | Cause and fix |
|---|---|
| `Permission … denied` or *API not enabled* right after enabling APIs or granting IAM | Propagation delay. Wait 1–2 minutes and retry |
| `gcloud builds submit` fails with a permission error on the staging bucket or Artifact Registry | The build's service account lacks access. In new projects builds run as the Compute Engine default account; grant `PROJECT_NUMBER-compute@developer.gserviceaccount.com` the roles *Artifact Registry Writer*, *Storage Object Viewer* and *Logs Writer*, or pass `--service-account=…sa-cloudbuild…` (Part B8 grants it the staging bucket) |
| `terraform apply` fails creating Cloud Run jobs: image not found | The images weren't built yet. Do Part 4A Step 2, then apply again |
| Workflow fails with *IAM permission denied* on its first run | The run.invoker grant hasn't propagated. Run it again after a minute |
| dbt job fails | Logs: **Cloud Run → Jobs → globalmart-dbt → Logs**. A failing test name tells you which rule or contract broke. The run history is in `gs://$BUCKET/dbt_runs/` |
| Budget creation fails with `INVALID_ARGUMENT` | The amount must be in the billing account's currency (e.g. `900INR`, not `10USD`) |
| App returns 403 | Expected without sign-in. Use the proxy, or grant the user *Cloud Run Invoker* |
| CI step `dbt-ci` fails to download the manifest | Run the pipeline once first (Part 5) |
| GitHub connection stays `PENDING_USER_OAUTH` | The authorization flow wasn't finished. Open the `actionUri` from `gcloud builds connections describe` again and complete both screens (authorize, then install the app) |

### Tear down
See **Teardown** in the [README](../README.md#teardown). In short: `agent/data_agent.py delete`,
delete the trigger and connection, then `terraform destroy` (Path A) or delete the resources from
Part 4B in reverse order. The cleanest option is deleting the whole project: `gcloud projects delete $PROJECT_ID`.

---

## Appendix A: Resource inventory

Everything the platform uses, with the step that creates it by hand (Terraform creates all of them
in Path A, except the last four rows).

| Resource | Name | Path B step |
|---|---|---|
| APIs | 12 services | B1 |
| GCS bucket | `<project>-globalmart-raw` | B2 |
| BigQuery datasets | `bronze`, `silver`, `gold`, `metrics`, `ops`, `silver_ci`, `gold_ci`, `metrics_ci` | B3 |
| BigQuery connection | `us-central1.vertex-ai` (+ Vertex AI User for its service account) | B4 |
| Artifact Registry | `globalmart` (Docker) | B5 |
| Service accounts | `sa-loader`, `sa-dbt`, `sa-app`, `sa-workflows`, `sa-cloudbuild` | B6 |
| IAM bindings | project, dataset, bucket, service-account and job level | B7, B8, B12 |
| Images | `loader`, `dbt`, `app` | B8 |
| Cloud Run jobs | `globalmart-loader`, `globalmart-dbt` | B9, B10 |
| Cloud Run service | `globalmart-app` (authenticated) | B11 |
| Workflow | `globalmart-e2e` | B12 |
| Budget *(not Terraform)* | `globalmart monthly` | 3.3 |
| Data agent *(not Terraform)* | `globalmart-agent` | Part 7 |
| Looker Studio report *(not Terraform)* | GlobalMart Intelligence | Part 9 |
| Cloud Build connection and trigger *(not Terraform)* | `globalmart-github`, `globalmart-main` | Part 10 |

Tables are not created by hand: the loader creates `bronze.raw_*` and `ops.ingest_log`; dbt
creates everything in `silver`, `gold` and `metrics` (including the `silver.customers_snapshot`
history, which should never be dropped).

## Appendix B: Settings that must match your project

| Setting | Where | Value |
|---|---|---|
| Project ID | `terraform/terraform.tfvars` (`project_id`); `GCP_PROJECT` environment variable for local tools | your project |
| Region | `REGION`, `dbt/profiles.yml`, `dbt/dbt_project.yml` (`genai_connection`), `cloudbuild.yaml` | `us-central1` |
| Gemini / embedding models | `dbt/dbt_project.yml` vars `genai_endpoint`, `genai_embedding_endpoint` | `gemini-3.5-flash`, `text-embedding-005` |
| Agent ID | `agent/agent_context.yaml`, app env `AGENT_ID` | `globalmart-agent` |

Model names change over time. If `AI.GENERATE` reports an unknown endpoint, check the current
Gemini models in the BigQuery `AI.GENERATE` documentation and update `genai_endpoint`.
