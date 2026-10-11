# Automated deployment: clone, run one script, done

`scripts/deploy.sh` creates the whole GlobalMart platform in your Google Cloud project: infrastructure,
container images, data, the pipeline run, the data agent and (optionally) CI/CD. Use this when you
want it running quickly. To learn what each piece is and build it yourself, follow
[`MANUAL_SETUP_GUIDE.md`](MANUAL_SETUP_GUIDE.md) instead.

**Time:** ~25 minutes, almost all of it waiting. **Cost:** within the free tiers for normal use; the
Gemini calls in a pipeline run cost cents.

---

## 1. Prerequisites (one time)

**Accounts**
1. A Google account. A personal Gmail works.
2. A **billing account**: <https://console.cloud.google.com/billing> → **Create account** (country,
   currency, payment card; new users usually get free-trial credit). Note its ID,
   `XXXXXX-XXXXXX-XXXXXX`, from the account's Overview page.
   [`MANUAL_SETUP_GUIDE.md` Module 1](MANUAL_SETUP_GUIDE.md#module-1-google-account-billing-account-and-budget)
   has the detailed steps.

**Tools on your computer**

| Tool | Install |
|---|---|
| Git | <https://git-scm.com/downloads> (Windows: use **Git Bash** for everything below) |
| Google Cloud CLI | <https://cloud.google.com/sdk/docs/install> (macOS: `brew install --cask gcloud-cli`) |
| Terraform ≥ 1.6 | <https://developer.hashicorp.com/terraform/install> (macOS: `brew tap hashicorp/tap && brew install hashicorp/tap/terraform`) |
| Python 3.12+ | <https://www.python.org/downloads/> (macOS: `brew install python@3.12`) |

You don't need Docker: images are built by Cloud Build.

```bash
git --version && gcloud --version | head -1 && terraform version | head -1 && python3.12 --version
```

---

## 2. Sign in and clone

```bash
gcloud auth login                         # browser: pick your Google account, Allow
gcloud auth application-default login     # browser: Allow (used by Terraform, dbt and the scripts)

git clone https://github.com/srinivasaddanki1978/gcp-globalmart.git    # or your fork, for CI/CD
cd gcp-globalmart
```

---

## 3. Deploy

Pick a **project ID**: globally unique, 6–30 characters, lowercase letters, digits and hyphens.

**New project** (the script creates it and links your billing account):
```bash
PROJECT_ID=globalmart-lab-1234 BILLING_ACCOUNT=XXXXXX-XXXXXX-XXXXXX BUDGET=10USD scripts/deploy.sh
```
**Existing project** (billing already enabled):
```bash
PROJECT_ID=my-existing-project scripts/deploy.sh
```

### Options

| Variable | Meaning |
|---|---|
| `PROJECT_ID` *(required)* | the project to deploy into |
| `BILLING_ACCOUNT` | create the project if it's missing and link this billing account |
| `BUDGET` | create a monthly budget alert at 50/90/100 %, **in your billing account's currency**: `10USD`, `900INR`, `10EUR`… |
| `GITHUB_REPO` | e.g. `https://github.com/<you>/gcp-globalmart.git`: set up CI/CD (section 6) |
| `SKIP_PIPELINE=1` | create everything but don't run the pipeline yet |
| `REBUILD=1` | rebuild the container images even if they exist |
| `REGION` | default `us-central1`. Keep it: `dbt/profiles.yml`, `dbt/dbt_project.yml` and `cloudbuild.yaml` assume it |

---

## 4. What the script does

Ten steps, each printed as `==> n/10`. Every step checks first and only creates what's missing, so if
something fails you can fix it and **run the same command again**.

| Step | What happens | Behind the scenes |
|---|---|---|
| 1. Tools and sign-in | Stops early with a clear message if a tool or sign-in is missing | `gcloud auth list`, ADC token check, Python version |
| 2. Project and billing | Creates the project and links billing if needed; sets it as the default; optional budget | `gcloud projects create`, `gcloud billing projects link`, `gcloud billing budgets create` |
| 3. APIs and image registry | Enables the 12 APIs and creates the Docker registry `globalmart` | writes `terraform/terraform.tfvars`, then `terraform apply -target=…artifact_registry…` |
| 4. Container images | Builds the `loader`, `dbt` and `app` images in the cloud (~5 min); skipped if they exist | `gcloud builds submit <dir> --tag …:latest`; gives the build account permission to push |
| 5. Everything else | Bucket, 8 BigQuery datasets, Vertex AI connection, 5 service accounts and all their permissions, the 2 Cloud Run jobs, the web app, the workflow, the CI datasets | `terraform apply` (~60 resources; see the README for the layout) |
| 6. Python environment | Creates `.venv` with dbt and the BigQuery libraries | `pip install -r …requirements.txt` |
| 7. Source data | Uploads the 205 files from `source_data/` | `gcloud storage rsync` |
| 8. Pipeline | Runs the loader, then dbt (Silver → Gold → Metrics → GenAI, ~135 models and tests), ~8 min; then checks the results against `tests/expected_results/` | `gcloud workflows run globalmart-e2e`, `tests/check_expected_results.py` |
| 9. Data agent | Creates or updates the natural-language agent over 20 tables and runs its 10 test questions | `agent/data_agent.py deploy`, `test` |
| 10. CI/CD | Only with `GITHUB_REPO`: GitHub connection, repo link, push trigger | `gcloud builds connections / repositories / triggers` |

At the end it prints how to open the app, ask the agent, refresh the data, build the dashboards
(with a ready link for your project) and remove everything.

---

## 5. Check the result

The script already ran the two automatic checks:
- **expected results:** 10 lines ending in `OK`;
- **data agent:** `10/10 correct`.

Then look for yourself: open the web app. It has nine dashboard pages, plus an **Ask** page where you
chat with the data agent.
- **From your computer:** run
  `gcloud run services proxy globalmart-app --region=us-central1 --port=8080` and open
  <http://localhost:8080>.
- **From Cloud Shell** (the `>_` icon in the console): run
  `gcloud run services proxy globalmart-app --region=us-central1 --port=8080`, then click
  **Web Preview → Preview on port 8080**. Don't click the `127.0.0.1` link it prints: that points at
  your laptop and gives "refused to connect". Step-by-step in
  [`MANUAL_SETUP_GUIDE.md` Module 14](MANUAL_SETUP_GUIDE.md#module-14-the-web-app-on-cloud-run). Without the proxy (or another signed-in request) the app returns 403. That's intended: it
requires authentication. To let someone else open it, add them to `app_users` in
`terraform/terraform.tfvars` (e.g. `app_users = ["user:friend@gmail.com"]`) and run
`cd terraform && terraform apply`.

In the console: **BigQuery** shows the datasets `bronze`, `silver`, `gold`, `metrics` and `ops`;
**Workflows → globalmart-e2e → Executions** shows the run; **Cloud Run** shows the two jobs and the app.

**Dashboards:** open the Looker Studio link the script printed (it already points at your project),
then build the four pages as described in [`looker_studio.md`](looker_studio.md). This is the one
manual step: Looker Studio has no API for building pages.

---

## 6. CI/CD (optional)

To test and deploy automatically on every push to `main`:

1. **Fork** this repo on GitHub, and clone your fork.
2. Run the script with your fork's URL:
   ```bash
   PROJECT_ID=<id> GITHUB_REPO=https://github.com/<you>/gcp-globalmart.git scripts/deploy.sh
   ```
3. The first time, step 10 prints an **authorization link**. Open it, click **Authorize Google
   Cloud Build** on GitHub, then **install the Cloud Build GitHub App** on your fork.
4. Run the same command again. Step 10 now creates the trigger `globalmart-main` (the other steps
   just confirm everything is in place).
5. Push a commit to `main` and watch **Cloud Build → History**: tests, a dbt CI build, images, deploy
   (~7 min).

---

## 7. Day to day

| Task | Command |
|---|---|
| Refresh all data | `gcloud workflows run globalmart-e2e --location=us-central1` |
| Add source files | put them in `source_data/`, re-run `scripts/deploy.sh` (only new files load) |
| Deploy code changes | push to `main` (with CI/CD), or `REBUILD=1 PROJECT_ID=<id> scripts/deploy.sh` |
| Check the numbers | `GCP_PROJECT=<id> .venv/bin/python tests/check_expected_results.py` |
| Ask a question | `GCP_PROJECT=<id> .venv/bin/python agent/data_agent.py ask "…"` |

---

## 8. Troubleshooting

| Message | Fix |
|---|---|
| `set PROJECT_ID` / `… not found` | Install the missing tool or set the variable, then re-run |
| `run: gcloud auth login` / `…application-default login` | Sign in (section 2) and re-run |
| `project … not found` | Create it in the console, or pass `BILLING_ACCOUNT` so the script creates it |
| `billing isn't enabled` | Link a billing account to the project, or pass `BILLING_ACCOUNT` |
| Project ID already taken (`gcloud projects create` fails) | IDs are global: choose another, e.g. add digits |
| `budget not created` | Use the billing account's currency, e.g. `BUDGET=900INR` |
| "127.0.0.1 refused to connect" opening the app from Cloud Shell | Use **Web Preview → Preview on port 8080**, not the printed `127.0.0.1` link |
| `retrying in 30s` | Normal right after APIs are enabled or permissions granted; it retries by itself |
| Terraform errors mentioning `http2: client connection` or timeouts to `*.googleapis.com` | A network problem between your computer and Google's APIs (Wi-Fi, VPN, proxy). The script retries; if it still fails, check your connection and run the same command again: completed steps are skipped |
| Image build fails | Open **Cloud Build → History** for the log. Re-run with `REBUILD=1` once fixed |
| `workflow failed` | **Workflows → globalmart-e2e → Executions** shows which job failed; that job's **Logs** (Cloud Run → Jobs) show why. For dbt, the failing test's name points at the rule or contract |
| `some results differ` | Only expected if the source data or the models changed; the lines above it show which numbers moved |
| Step 10 keeps printing the authorization link | GitHub authorization isn't finished: complete both screens (authorize, then install the app) and re-run |
| `terraform apply` says a resource already exists | It was created outside Terraform (e.g. by hand following the manual guide). Use a fresh project, or delete that resource first |

---

## 9. Remove everything

```bash
PROJECT_ID=<id> scripts/teardown.sh                    # all GlobalMart resources and data; keeps the project
PROJECT_ID=<id> DELETE_PROJECT=1 scripts/teardown.sh   # or delete the whole project (30-day recovery)
```
Both ask you to type the project ID to confirm. Delete the budget under **Billing → Budgets &
alerts**, and the Looker Studio report in Looker Studio.

`silver.customers_snapshot` holds the only copy of customer change history. Export it first if you want
to keep it.
