#!/usr/bin/env bash
# Remove everything scripts/deploy.sh created, keeping the project itself.
#   PROJECT_ID=my-project scripts/teardown.sh                   # asks for confirmation
#   PROJECT_ID=my-project DELETE_PROJECT=1 scripts/teardown.sh  # delete the whole project instead
set -euo pipefail

REGION=${REGION:-us-central1}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
[ -n "${PROJECT_ID:-}" ] || { echo "set PROJECT_ID" >&2; exit 1; }

if [ -n "${DELETE_PROJECT:-}" ]; then
  read -r -p "Delete the WHOLE project $PROJECT_ID (30-day recovery window)? Type the project ID to confirm: " ok
  [ "$ok" = "$PROJECT_ID" ] || { echo "aborted"; exit 1; }
  gcloud projects delete "$PROJECT_ID" --quiet
  echo "Project $PROJECT_ID scheduled for deletion. Also delete its budget under Billing → Budgets & alerts."
  exit 0
fi

read -r -p "Delete all GlobalMart resources and data in $PROJECT_ID? Type the project ID to confirm: " ok
[ "$ok" = "$PROJECT_ID" ] || { echo "aborted"; exit 1; }

echo "==> Data agent"
[ -x .venv/bin/python ] && GCP_PROJECT=$PROJECT_ID .venv/bin/python agent/data_agent.py delete || echo "    (not found)"

echo "==> CI/CD trigger and GitHub connection"
gcloud builds triggers delete globalmart-main --region="$REGION" --project="$PROJECT_ID" --quiet 2>/dev/null || echo "    (no trigger)"
gcloud builds connections delete globalmart-github --region="$REGION" --project="$PROJECT_ID" --quiet 2>/dev/null || echo "    (no connection)"

echo "==> Terraform-managed resources (datasets with tables, bucket with files, jobs, app, workflow, registry, IAM)"
cd terraform
printf 'project_id = "%s"\nregion     = "%s"\n' "$PROJECT_ID" "$REGION" > terraform.tfvars
terraform init -input=false >/dev/null
terraform destroy -input=false -auto-approve

echo
echo "Done. Left in place: the project, its budget (Billing → Budgets & alerts) and any Looker Studio report."
