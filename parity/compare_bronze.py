"""Bronze parity: compare a per-column profile of every bronze table between
Databricks and BigQuery: row count, then non-null count, distinct count and
total text length per column. Column names are matched case-insensitively
(BigQuery Bronze lower-cases headers).

    python parity/compare_bronze.py --profile free --warehouse-id <id>
"""

import argparse
import sys

from google.cloud import bigquery

from run_databricks_baseline import run_statement

ENTITIES = ["customers", "orders", "transactions", "returns", "products", "vendors"]
SKIP = {"_rescued_data", "_source_file", "_load_timestamp"}


def profile_sql(table: str, columns: list[str], quote: str, length_fn: str) -> str:
    parts = ["COUNT(*) AS n"]
    for i, c in enumerate(columns):
        q = f"{quote}{c}{quote}"
        parts += [f"COUNT({q}) AS nn_{i}", f"COUNT(DISTINCT {q}) AS nd_{i}",
                  f"COALESCE(SUM({length_fn}({q})), 0) AS len_{i}"]
    return f"SELECT {', '.join(parts)} FROM {table}"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", default="free")
    parser.add_argument("--warehouse-id", required=True)
    parser.add_argument("--project", default="globalmart-gcp-lab")
    args = parser.parse_args()

    bq = bigquery.Client(project=args.project, location="us-central1")
    mismatches = 0
    for entity in ENTITIES:
        table = f"raw_{entity}"
        bq_cols = [f.name for f in bq.get_table(f"{args.project}.bronze.{table}").schema if f.name not in SKIP]
        _, rows = run_statement(args.profile, args.warehouse_id,
                                f"SELECT column_name FROM globalmart.information_schema.columns "
                                f"WHERE table_schema = 'bronze' AND table_name = '{table}'")
        db_cols = {r[0].lower(): r[0] for r in rows if r[0] not in SKIP}

        if set(bq_cols) != set(db_cols):
            print(f"{table}: column sets differ: only BigQuery {set(bq_cols) - set(db_cols)}, "
                  f"only Databricks {set(db_cols) - set(bq_cols)}")
            mismatches += 1
        cols = [c for c in bq_cols if c in db_cols]

        bq_row = list(next(iter(bq.query(profile_sql(f"`{args.project}.bronze.{table}`", cols, "`", "LENGTH")).result())).values())
        _, db_rows = run_statement(args.profile, args.warehouse_id,
                                   profile_sql(f"globalmart.bronze.{table}", [db_cols[c] for c in cols], "`", "char_length"))
        db_row = [int(v) for v in db_rows[0]]

        diffs = []
        if bq_row[0] != db_row[0]:
            diffs.append(f"rows {bq_row[0]} vs {db_row[0]}")
        for i, c in enumerate(cols):
            b, d = bq_row[1 + 3 * i: 4 + 3 * i], db_row[1 + 3 * i: 4 + 3 * i]
            if b != d:
                diffs.append(f"{c}: non-null/distinct/length BigQuery {b} vs Databricks {d}")
        status = "OK" if not diffs else "DIFF"
        print(f"{table:20} {status}  rows={bq_row[0]}  columns={len(cols)}")
        for d in diffs:
            print(f"    {d}")
        mismatches += bool(diffs)
    sys.exit(1 if mismatches else 0)


if __name__ == "__main__":
    main()
