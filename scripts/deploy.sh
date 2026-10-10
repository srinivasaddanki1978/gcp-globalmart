#!/usr/bin/env bash
# Deploy the whole GlobalMart platform into a Google Cloud project, end to end.
# Safe to re-run: every step creates what's missing and leaves the rest alone.
#
#   PROJECT_ID=my-project scripts/deploy.sh                                  # existing project
#   PROJECT_ID=my-project BILLING_ACCOUNT=XXXXXX-XXXXXX-XXXXXX scripts/deploy.sh   # create it too
#
# Optional settings (environment variables):
#   BILLING_ACCOUNT   create the project if it doesn't exist and link this billing account
#   BUDGET            monthly budget alert in the billing account's currency, e.g. 10USD or 900INR
#   GITHUB_REPO       https://github.com/<user>/gcp-globalmart.git to set up CI/CD on push to main
#   SKIP_PIPELINE=1   don't run the data pipeline (and skip the checks that need its data)
#   REGION            default us-central1 (the code assumes it; see docs/AUTOMATED_DEPLOYMENT.md)
set -euo pipefail

REGION=${REGION:-us-central1}
export CLOUDSDK_CORE_DISABLE_PROMPTS=1   # gcloud never waits for input
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '\033[1;33m    ! %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
retry() { # retry <attempts> <cmd...>: new APIs and IAM grants take a minute to apply
  local n=$1; shift
  for i in $(seq 1 "$n"); do "$@" && return 0; [ "$i" -lt "$n" ] && { warn "retrying in 30s ($i/$n)"; sleep 30; }; done
  return 1
}

# --- 1. Prerequisites ---------------------------------------------------------------
step "1/10 Checking tools and sign-in"
[ -n "${PROJECT_ID:-}" ] || die "set PROJECT_ID, e.g. PROJECT_ID=globalmart-lab-1234 scripts/deploy.sh"
for t in gcloud bq terraform; do command -v $t >/dev/null || die "$t not found (see docs/AUTOMATED_DEPLOYMENT.md, Prerequisites)"; done
PYTHON=$(command -v python3.12 || command -v python3 || true)
[ -n "$PYTHON" ] && "$PYTHON" -c 'import sys; sys.exit(sys.version_info < (3, 12))' || die "Python 3.12+ is required"
[ -n "$(gcloud auth list --filter=status:ACTIVE --format='value(account)')" ] || die "run: gcloud auth login"
gcloud auth application-default print-access-token >/dev/null 2>&1 || die "run: gcloud auth application-default login"
info "account: $(gcloud auth list --filter=status:ACTIVE --format='value(account)')  project: $PROJECT_ID  region: $REGION"

# --- 2. Project, billing, budget ----------------------------------------------------
step "2/10 Project and billing"
if gcloud projects describe "$PROJECT_ID" >/dev/null 2>&1; then
  info "project exists"
else
  [ -n "${BILLING_ACCOUNT:-}" ] || die "project $PROJECT_ID not found: create it, or set BILLING_ACCOUNT to let this script create it"
  gcloud projects create "$PROJECT_ID" --name="GlobalMart" --quiet
fi
if [ "$(gcloud billing projects describe "$PROJECT_ID" --format='value(billingEnabled)' 2>/dev/null)" != "True" ]; then
  [ -n "${BILLING_ACCOUNT:-}" ] || die "billing isn't enabled on $PROJECT_ID: link a billing account, or set BILLING_ACCOUNT"
  gcloud billing projects link "$PROJECT_ID" --billing-account="$BILLING_ACCOUNT" --quiet >/dev/null
fi
info "billing enabled"
gcloud config set project "$PROJECT_ID" --quiet 2>/dev/null
gcloud auth application-default set-quota-project "$PROJECT_ID" --quiet >/dev/null 2>&1 || true
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')
if [ -n "${BUDGET:-}" ]; then
  BA=${BILLING_ACCOUNT:-$(gcloud billing projects describe "$PROJECT_ID" --format='value(billingAccountName)' | sed 's#billingAccounts/##')}
  gcloud services enable billingbudgets.googleapis.com --quiet
  if gcloud billing budgets list --billing-account="$BA" --format='value(displayName)' 2>/dev/null | grep -qx "$PROJECT_ID monthly"; then
    info "budget exists"
  else
    gcloud billing budgets create --billing-account="$BA" --display-name="$PROJECT_ID monthly" \
      --budget-amount="$BUDGET" --filter-projects="projects/$PROJECT_NUMBER" --calendar-period=month \
      --threshold-rule=percent=0.5 --threshold-rule=percent=0.9 --threshold-rule=percent=1.0 --quiet >/dev/null \
      && info "budget alert $BUDGET created" || warn "budget not created (the amount must use the billing account's currency, e.g. 900INR)"
  fi
fi

# --- 3. Terraform foundation (APIs + image registry) --------------------------------
step "3/10 Terraform: APIs and image registry"
cd terraform
printf 'project_id = "%s"\nregion     = "%s"\n' "$PROJECT_ID" "$REGION" > terraform.tfvars
terraform init -input=false -upgrade=false >/dev/null
retry 3 terraform apply -input=false -auto-approve -target=google_artifact_registry_repository.images >/dev/null
cd "$ROOT"
info "APIs enabled, registry ready"

# --- 4. Container images --------------------------------------------------------------
step "4/10 Building the loader, dbt and app images (Cloud Build, ~5 min)"
REPO=$REGION-docker.pkg.dev/$PROJECT_ID/globalmart
# Builds run as the Compute Engine default service account; make sure it may build and push.
CE_SA="serviceAccount:$PROJECT_NUMBER-compute@developer.gserviceaccount.com"
for role in roles/artifactregistry.writer roles/storage.objectViewer roles/logging.logWriter; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" --member="$CE_SA" --role=$role --condition=None --quiet >/dev/null 2>&1
done
for img in loader dbt app; do
  if [ -z "${REBUILD:-}" ] && gcloud artifacts docker tags list "$REPO/$img" --quiet --format='value(tag.basename())' 2>/dev/null </dev/null | grep -qx latest; then
    info "$img: image exists (set REBUILD=1 to rebuild)"
  else
    retry 2 gcloud builds submit "$img" --region="$REGION" --tag "$REPO/$img:latest" --quiet >/dev/null
    info "$img: built"
  fi
done

# --- 5. Terraform: everything else --------------------------------------------------
step "5/10 Terraform: bucket, datasets, service accounts, IAM, jobs, app, workflow, CI datasets"
cd terraform
retry 3 terraform apply -input=false -auto-approve >/dev/null
BUCKET=$(terraform output -raw raw_bucket | sed 's#gs://##')
cd "$ROOT"
info "infrastructure ready (bucket gs://$BUCKET)"

# --- 6. Python tools --------------------------------------------------------------------
step "6/10 Python environment"
[ -x .venv/bin/python ] || "$PYTHON" -m venv .venv
.venv/bin/pip install -q -r loader/requirements.txt -r dbt/requirements.txt
info ".venv ready"

# --- 7. Source data -------------------------------------------------------------------
step "7/10 Uploading the 205 source files"
gcloud storage rsync -r --checksums-only source_data "gs://$BUCKET/source_data" --quiet >/dev/null 2>&1
info "$(gcloud storage ls -r "gs://$BUCKET/source_data/**" | grep -cE '\.(csv|json)$') files in gs://$BUCKET/source_data"

export GCP_PROJECT=$PROJECT_ID
if [ -z "${SKIP_PIPELINE:-}" ]; then
  # --- 8. Pipeline --------------------------------------------------------------------
  step "8/10 Running the pipeline: loader → dbt (Silver, Gold, Metrics, GenAI), ~8 min"
  run_workflow() { gcloud workflows run globalmart-e2e --location="$REGION" --format='value(state)' 2>/dev/null | tail -1 | grep -q SUCCEEDED; }
  retry 2 run_workflow || die "workflow failed: see Workflows → globalmart-e2e → Executions, and the Cloud Run job logs"
  info "pipeline SUCCEEDED"
  .venv/bin/python tests/check_expected_results.py || warn "some results differ from tests/expected_results (see above)"
else
  step "8/10 Pipeline skipped (SKIP_PIPELINE=1)"
fi

# --- 9. Data agent ---------------------------------------------------------------------
step "9/10 Data agent"
.venv/bin/python agent/data_agent.py deploy
if [ -z "${SKIP_PIPELINE:-}" ]; then
  .venv/bin/python agent/data_agent.py test | tail -1 || warn "agent test below target"
fi

# --- 10. CI/CD (optional) ----------------------------------------------------------------
step "10/10 CI/CD from GitHub"
if [ -z "${GITHUB_REPO:-}" ]; then
  info "skipped (set GITHUB_REPO=https://github.com/<user>/gcp-globalmart.git to enable)"
else
  gcloud projects add-iam-policy-binding "$PROJECT_ID" --condition=None --quiet >/dev/null 2>&1 \
    --member="serviceAccount:service-$PROJECT_NUMBER@gcp-sa-cloudbuild.iam.gserviceaccount.com" --role=roles/secretmanager.admin
  gcloud builds connections describe globalmart-github --region="$REGION" >/dev/null 2>&1 \
    || gcloud builds connections create github globalmart-github --region="$REGION" --quiet >/dev/null 2>&1 || true
  STAGE=$(gcloud builds connections describe globalmart-github --region="$REGION" --format='value(installationState.stage)')
  if [ "$STAGE" != "COMPLETE" ]; then
    warn "GitHub isn't authorized yet. Open this link, authorize Cloud Build and install its GitHub App on your repo,"
    warn "then run this script again to create the trigger:"
    gcloud builds connections describe globalmart-github --region="$REGION" --format='value(installationState.actionUri)'
  else
    gcloud builds repositories describe gcp-globalmart --connection=globalmart-github --region="$REGION" >/dev/null 2>&1 \
      || gcloud builds repositories create gcp-globalmart --connection=globalmart-github --region="$REGION" --remote-uri="$GITHUB_REPO" --quiet >/dev/null
    if gcloud builds triggers describe globalmart-main --region="$REGION" >/dev/null 2>&1; then
      info "trigger globalmart-main exists"
    else
      gcloud builds triggers create github --name=globalmart-main --region="$REGION" \
        --repository="projects/$PROJECT_ID/locations/$REGION/connections/globalmart-github/repositories/gcp-globalmart" \
        --branch-pattern='^main$' --build-config=cloudbuild.yaml \
        --service-account="projects/$PROJECT_ID/serviceAccounts/sa-cloudbuild@$PROJECT_ID.iam.gserviceaccount.com" --quiet >/dev/null
      info "trigger globalmart-main created: every push to main now tests and deploys"
    fi
  fi
fi

LOOKER_URL=$("$PYTHON" - "$PROJECT_ID" <<'EOF'
import sys
from urllib.parse import urlencode
views = ["rpt_revenue", "rpt_segment", "rpt_vendor_returns", "rpt_return_reasons", "rpt_flagged",
         "rpt_slow_moving", "rpt_return_cost", "rpt_dq", "rpt_insights"]
p = {"r.reportName": "GlobalMart Intelligence", "c.mode": "edit"}
for i, v in enumerate(views):
    p.update({f"ds.ds{i}.connector": "bigQuery", f"ds.ds{i}.type": "TABLE", f"ds.ds{i}.projectId": sys.argv[1],
              f"ds.ds{i}.datasetId": "gold", f"ds.ds{i}.tableId": v, f"ds.ds{i}.datasourceName": v})
print("https://lookerstudio.google.com/reporting/create?" + urlencode(p))
EOF
)

printf '\n\033[1;32mDone. GlobalMart is deployed in %s.\033[0m\n\n' "$PROJECT_ID"
cat <<EOF
  Web app:        gcloud run services proxy globalmart-app --region=$REGION --port=8080
                  then open http://localhost:8080
  Ask the agent:  GCP_PROJECT=$PROJECT_ID .venv/bin/python agent/data_agent.py ask "Which vendor has the highest return rate?"
  Refresh data:   gcloud workflows run globalmart-e2e --location=$REGION
  Dashboards:     open the link below, then build the pages per docs/looker_studio.md
                  $LOOKER_URL
  Remove it all:  PROJECT_ID=$PROJECT_ID scripts/teardown.sh
EOF
