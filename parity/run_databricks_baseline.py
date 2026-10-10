"""Run parity/databricks_baseline.sql on a Databricks SQL warehouse and save one
CSV per query to parity/baseline_results/.

Queries are delimited by `-- qNN_name: description` comment lines. Uses the
Databricks CLI (`databricks api post`), so auth comes from a CLI profile.

    python parity/run_databricks_baseline.py --profile free --warehouse-id <id>
"""

import argparse
import csv
import json
import re
import subprocess
import time
from pathlib import Path

HERE = Path(__file__).parent
SQL_FILE = HERE / "databricks_baseline.sql"
OUT_DIR = HERE / "baseline_results"
QUERY_HEADER = re.compile(r"^-- (q\d+_\w+):.*$", re.MULTILINE)


def split_queries(sql: str) -> dict[str, str]:
    parts = QUERY_HEADER.split(sql)
    # parts = [preamble, name1, body1, name2, body2, ...]
    return {name: body.strip().rstrip(";") for name, body in zip(parts[1::2], parts[2::2])}


def api(profile: str, method: str, path: str, body: dict | None = None) -> dict:
    cmd = ["databricks", "-p", profile, "api", method, path]
    if body is not None:
        cmd += ["--json", json.dumps(body)]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(f"databricks api {method} {path} failed: {proc.stderr.strip() or proc.stdout.strip()}")
    return json.loads(proc.stdout)


def run_statement(profile: str, warehouse_id: str, sql: str) -> tuple[list[str], list[list]]:
    resp = api(profile, "post", "/api/2.0/sql/statements", {
        "warehouse_id": warehouse_id,
        "statement": sql,
        "catalog": "globalmart",
        "wait_timeout": "50s",
        "on_wait_timeout": "CONTINUE",
        "disposition": "INLINE",
        "format": "JSON_ARRAY",
    })
    while resp["status"]["state"] in ("PENDING", "RUNNING"):
        time.sleep(3)
        resp = api(profile, "get", f"/api/2.0/sql/statements/{resp['statement_id']}")
    if resp["status"]["state"] != "SUCCEEDED":
        raise RuntimeError(resp["status"].get("error", resp["status"]))

    columns = [c["name"] for c in resp["manifest"]["schema"]["columns"]]
    rows = list(resp.get("result", {}).get("data_array", []) or [])
    next_link = resp.get("result", {}).get("next_chunk_internal_link")
    while next_link:
        chunk = api(profile, "get", next_link)
        rows += chunk.get("data_array", []) or []
        next_link = chunk.get("next_chunk_internal_link")
    return columns, rows


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", default="free")
    parser.add_argument("--warehouse-id", required=True)
    parser.add_argument("--only", nargs="*", help="query names to run (default: all)")
    args = parser.parse_args()

    OUT_DIR.mkdir(exist_ok=True)
    for name, sql in split_queries(SQL_FILE.read_text()).items():
        if args.only and name not in args.only:
            continue
        columns, rows = run_statement(args.profile, args.warehouse_id, sql)
        with open(OUT_DIR / f"{name}.csv", "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(columns)
            writer.writerows(rows)
        print(f"{name}: {len(rows)} rows")


if __name__ == "__main__":
    main()
