"""Silver parity: Databricks vs BigQuery.

1. pipeline_audit_log, row for row.
2. rejected_records as a multiset of (source_table, record_key, affected_field,
   issue_type, record_data, file path relative to source_data/).
3. A profile of each clean_* table: row count, distinct keys, sums of the
   numeric columns, min/max of the parsed dates.

    python parity/compare_silver.py --warehouse-id <id>
"""

import argparse
import sys
from collections import Counter

from google.cloud import bigquery

from run_databricks_baseline import run_statement

REL_PATH = {"bq": r"REGEXP_EXTRACT(_source_file, r'source_data/(.*)$')",
            # Databricks URL-encodes the path (Region%201); GCS keeps the space.
            "db": r"replace(regexp_extract(_source_file, 'source_data/(.*)$', 1), '%20', ' ')"}

# Profile expressions per clean table, written once in SQL valid on both engines.
# Timestamps are compared as text (second precision) to avoid type differences.
PROFILES = {
    "clean_customers": ["count(*)", "count(distinct customer_id)", "count(distinct customer_email)",
                        "count(distinct concat(city, '|', state))", "count(distinct segment)", "count(distinct region)"],
    "clean_orders": ["count(*)", "count(distinct order_id)", "count(distinct ship_mode)", "count(distinct order_status)",
                     "{ts_min}(order_purchase_date)", "{ts_max}(order_purchase_date)",
                     "sum({epoch}(order_purchase_date))"],
    "clean_transactions": ["count(*)", "count(distinct order_id)", "round(sum(sales), 4)",
                           "sum(quantity)", "round(sum(discount), 4)", "count(distinct product_id)"],
    "clean_returns": ["count(*)", "count(distinct order_id)", "round(sum(refund_amount), 2)",
                      "count(distinct return_reason)", "count(distinct return_status)",
                      "{ts_min}(return_date)", "{ts_max}(return_date)"],
    "clean_products": ["count(*)", "count(distinct product_id)", "count(distinct upc)",
                       "sum(length(upc))", "count(distinct category)", "count(distinct brand)"],
    "clean_vendors": ["count(*)", "count(distinct vendor_id)", "count(distinct vendor_name)"],
}
DIALECT = {
    "bq": {"ts_min": "min_ts", "ts_max": "max_ts", "epoch": "unix_seconds"},
    "db": {"ts_min": "min_ts", "ts_max": "max_ts", "epoch": "unix_timestamp"},
}


def render(expr: str, engine: str) -> str:
    d = DIALECT[engine]
    expr = expr.replace("{epoch}", d["epoch"])
    for agg in ("min", "max"):
        fmt = ("format_timestamp('%Y-%m-%d %H:%M:%S', {agg}({col}))" if engine == "bq"
               else "date_format({agg}({col}), 'yyyy-MM-dd HH:mm:ss')")
        token = "{ts_" + agg + "}("
        while token in expr:
            start = expr.index(token)
            end = expr.index(")", start)
            col = expr[start + len(token):end]
            expr = expr[:start] + fmt.format(agg=agg, col=col) + expr[end + 1:]
    return expr


def norm(v) -> str:
    if v is None:
        return "NULL"
    s = str(v)
    try:
        f = float(s)
        return f"{f:.4f}"
    except ValueError:
        return s


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", default="free")
    parser.add_argument("--warehouse-id", required=True)
    parser.add_argument("--project", default="globalmart-gcp-lab")
    args = parser.parse_args()
    bq = bigquery.Client(project=args.project, location="us-central1")

    def bq_rows(sql):
        return [tuple(r.values()) for r in bq.query(sql).result()]

    def db_rows(sql):
        return [tuple(r) for r in run_statement(args.profile, args.warehouse_id, sql)[1]]

    failed = False

    # 1. Audit log
    sql = "SELECT entity, bronze_count, silver_count, rejected_count, reconciliation_diff FROM {} ORDER BY entity"
    b = [tuple(norm(v) for v in r) for r in bq_rows(sql.format(f"`{args.project}.silver.pipeline_audit_log`"))]
    d = [tuple(norm(v) for v in r) for r in db_rows(sql.format("globalmart.silver.pipeline_audit_log"))]
    print("pipeline_audit_log:", "OK" if b == d else "DIFF")
    for row in b:
        print("   ", row)
    if b != d:
        failed = True
        print("    Databricks:", d)

    # 2. Rejected records, row level
    cols = "source_table, record_key, affected_field, issue_type, record_data"
    b = Counter(bq_rows(f"SELECT {cols}, {REL_PATH['bq']} FROM `{args.project}.silver.rejected_records`"))
    d = Counter(db_rows(f"SELECT {cols}, {REL_PATH['db']} FROM globalmart.silver.rejected_records"))
    only_b, only_d = b - d, d - b
    print(f"rejected_records: {'OK' if not only_b and not only_d else 'DIFF'}  "
          f"rows BigQuery={sum(b.values())} Databricks={sum(d.values())}")
    if only_b or only_d:
        failed = True
        for label, extra in (("only BigQuery", only_b), ("only Databricks", only_d)):
            print(f"    {label}: {sum(extra.values())}")
            for row in list(extra)[:5]:
                print("       ", row)
    per_rule = Counter((r[0], r[2], r[3]) for r in b.elements())
    for rule, n in sorted(per_rule.items()):
        print(f"    {rule[0]:20} {rule[1]:15} {rule[2]:14} {n}")

    # 3. Clean table profiles
    for table, exprs in PROFILES.items():
        b = [norm(v) for v in bq_rows(
            f"SELECT {', '.join(render(e, 'bq') for e in exprs)} FROM `{args.project}.silver.{table}`")[0]]
        d = [norm(v) for v in db_rows(
            f"SELECT {', '.join(render(e, 'db') for e in exprs)} FROM globalmart.silver.{table}")[0]]
        ok = b == d
        failed |= not ok
        print(f"{table:20} {'OK' if ok else 'DIFF'}")
        for e, bv, dv in zip(exprs, b, d):
            if bv != dv:
                print(f"    {e}: BigQuery {bv} vs Databricks {dv}")

    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
