"""Check the pipeline output in BigQuery against the known-good results.

Runs every `-- qNN_name:` block in tests/expected_results.sql and compares the rows
with tests/expected_results/qNN_name.csv (order-insensitive). Numbers may differ by
at most one cent (money totals are rounded), text must match exactly.

    GCP_PROJECT=<project> python tests/check_expected_results.py [--only q06_revenue_by_year_region ...]

Exit code 1 if any result differs. Run it after a full pipeline run.
"""

import argparse
import csv
import os
import re
import sys
from pathlib import Path

from google.cloud import bigquery

HERE = Path(__file__).parent
BLOCK = re.compile(r"^-- (q\d+_\w+):.*$", re.MULTILINE)
TOLERANCE = 0.0100001


def blocks(sql: str) -> dict[str, str]:
    parts = BLOCK.split(sql)
    return {name: body.strip().rstrip(";") for name, body in zip(parts[1::2], parts[2::2])}


def cell(v) -> str:
    return "" if v is None else str(v)


def same(a: str, b: str) -> bool:
    if a == b:
        return True
    try:
        return abs(float(a) - float(b)) <= TOLERANCE
    except ValueError:
        return False


def compare(actual: list[tuple], expected: list[tuple]) -> list[str]:
    if len(actual) != len(expected):
        return [f"row count {len(actual)}, expected {len(expected)}"]
    problems = []
    for a, e in zip(sorted(actual), sorted(expected)):
        if len(a) != len(e) or not all(same(x, y) for x, y in zip(a, e)):
            problems.append(f"got {a}, expected {e}")
    return problems


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--project", default=os.environ.get("GCP_PROJECT"))
    parser.add_argument("--only", nargs="*")
    args = parser.parse_args()
    if not args.project:
        sys.exit("set GCP_PROJECT or pass --project")
    bq = bigquery.Client(project=args.project, location="us-central1")

    failed = 0
    for name, sql in blocks((HERE / "expected_results.sql").read_text()).items():
        if args.only and name not in args.only:
            continue
        with open(HERE / "expected_results" / f"{name}.csv", newline="") as f:
            expected = [tuple(r) for r in list(csv.reader(f))[1:]]
        actual = [tuple(cell(v) for v in r.values()) for r in bq.query(sql).result()]
        problems = compare(actual, expected)
        print(f"{'OK  ' if not problems else 'FAIL'}  {name}  ({len(actual)} rows)")
        for p in problems[:5]:
            print(f"      {p}")
        failed += bool(problems)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
