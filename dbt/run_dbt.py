"""Cloud Run job entrypoint: run dbt, then keep the run history.

Runs `dbt <args>` (default: `build --target prod`), uploads target/run_results.json
to gs://$RAW_BUCKET/dbt_runs/<UTC timestamp>_<status>/ even when the build fails,
and exits with dbt's exit code, so a failing test fails the job and the workflow.
"""

import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

from google.cloud import storage


def main() -> int:
    args = sys.argv[1:] or ["build", "--target", "prod"]
    started = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    code = subprocess.run(["dbt", *args]).returncode

    results = Path("target/run_results.json")
    bucket_name = os.environ.get("RAW_BUCKET")
    if bucket_name and results.exists():
        bucket = storage.Client().bucket(bucket_name)
        status = "success" if code == 0 else "failed"
        blob_name = f"dbt_runs/{started}_{status}/run_results.json"
        bucket.blob(blob_name).upload_from_filename(str(results))
        print(f"run history: gs://{bucket_name}/{blob_name}", flush=True)
        # The manifest of the last successful production build is the state CI compares
        # against (dbt build --select state:modified+ --defer --state ...).
        manifest = Path("target/manifest.json")
        if code == 0 and "--target" in args and args[args.index("--target") + 1] == "prod" and manifest.exists():
            bucket.blob("dbt_state/prod/manifest.json").upload_from_filename(str(manifest))
            print(f"prod state: gs://{bucket_name}/dbt_state/prod/manifest.json", flush=True)
    return code


if __name__ == "__main__":
    sys.exit(main())
