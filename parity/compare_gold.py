"""Gold parity: Databricks vs BigQuery, row by row on business columns.

Surrogate keys differ by design (FARM_FINGERPRINT vs monotonically_increasing_id),
so rows are compared as multisets of their business columns. BigQuery's Unknown
member rows (-1) are excluded, and BigQuery's -1 keys are compared with
Databricks' NULL keys. Numbers are compared exactly (as parsed doubles).

    python parity/compare_gold.py --warehouse-id <id> [--only fact_sales ...]
"""

import argparse
import sys
from collections import Counter
from datetime import date, datetime

from google.cloud import bigquery

from run_databricks_baseline import run_statement

# table -> (business columns, BigQuery filter excluding Unknown members)
TABLES = {
    "dim_customers": ("customer_id, customer_name, customer_email, segment, city, state, region",
                      "customer_sk != -1 AND is_current"),  # SCD2: current version = Databricks' SCD1 row
    "dim_products": ("product_id, product_name, brand, category, upc", "product_sk != -1"),
    "dim_vendors": ("vendor_id, vendor_name", "vendor_sk != -1"),
    "dim_dates": ("date_key, year, quarter, month, month_name, day, day_of_week, is_weekend", "date_sk != -1"),
    "fact_sales": ("order_id, customer_id, product_id, vendor_id, order_date_key, sales, quantity, discount, "
                   "profit, ship_mode, order_status, payment_type", None),
    "fact_returns": ("order_id, customer_id, vendor_id, return_date_key, refund_amount, return_reason, return_status", None),
    "bridge_return_products": ("order_id, product_id, return_date_key, return_reason, return_status, refund_amount, "
                               "line_sales, total_order_sales, allocation_weight, allocated_refund", None),
    "mv_revenue_by_region": ("year, month, month_name, region, order_count, total_sales, total_profit, "
                             "total_quantity, unique_customers", None),
    "mv_return_rate_by_vendor": ("vendor_id, vendor_name, total_orders, total_sales, return_order_count, "
                                 "total_refunded, return_rate_pct", None),
    "mv_slow_moving_products": ("product_id, product_name, brand, region, total_sales, total_quantity, "
                                "order_count, total_profit, is_slow_moving", None),
}

# BigQuery -1 keys must line up with Databricks NULL keys.
UNKNOWN_KEYS = {
    "fact_sales": ["customer_sk", "product_sk", "vendor_sk", "order_date_sk"],
    "fact_returns": ["customer_sk", "vendor_sk", "return_date_sk"],
    "bridge_return_products": ["product_sk", "return_date_sk"],
}


def norm(v) -> str:
    if v is None:
        return "NULL"
    if isinstance(v, bool):
        return str(v).lower()
    if isinstance(v, datetime):
        return v.strftime("%Y-%m-%d %H:%M:%S")
    if isinstance(v, date):
        return v.isoformat()
    s = str(v)
    if s in ("true", "false"):
        return s
    try:
        return repr(float(s))
    except ValueError:
        return s


CENT = 0.0100001  # rounded money columns may differ by one cent (float summation order)


def close(a: str, b: str) -> bool:
    if a == b:
        return True
    try:
        x, y = float(a), float(b)
    except ValueError:
        return False
    return abs(x - y) <= CENT or abs(x - y) <= 1e-9 * max(abs(x), abs(y))


def pair_rounding(only_b: Counter, only_d: Counter) -> tuple[int, float, list, list]:
    """Pair leftover rows that differ only by rounding. Returns (paired, max_abs_diff,
    unpaired BigQuery rows, unpaired Databricks rows)."""
    left_d = list(only_d.elements())
    unpaired_b, paired, max_diff = [], 0, 0.0
    for rb in only_b.elements():
        for i, rd in enumerate(left_d):
            if len(rb) == len(rd) and all(close(a, b) for a, b in zip(rb, rd)):
                for a, b in zip(rb, rd):
                    if a != b:
                        max_diff = max(max_diff, abs(float(a) - float(b)))
                paired += 1
                del left_d[i]
                break
        else:
            unpaired_b.append(rb)
    return paired, max_diff, unpaired_b, left_d


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", default="free")
    parser.add_argument("--warehouse-id", required=True)
    parser.add_argument("--project", default="globalmart-gcp-lab")
    parser.add_argument("--only", nargs="*")
    args = parser.parse_args()
    bq = bigquery.Client(project=args.project, location="us-central1")

    def bq_rows(sql):
        return [tuple(norm(v) for v in r.values()) for r in bq.query(sql).result()]

    def db_rows(sql):
        return [tuple(norm(v) for v in r) for r in run_statement(args.profile, args.warehouse_id, sql)[1]]

    failed = False
    for table, (cols, bq_filter) in TABLES.items():
        if args.only and table not in args.only:
            continue
        where = f" WHERE {bq_filter}" if bq_filter else ""
        b = Counter(bq_rows(f"SELECT {cols} FROM `{args.project}.gold.{table}`{where}"))
        d = Counter(db_rows(f"SELECT {cols} FROM globalmart.gold.{table}"))
        only_b, only_d = b - d, d - b
        paired, max_diff, only_b, only_d = pair_rounding(only_b, only_d)
        ok = not only_b and not only_d
        line = f"{table:26} {'OK' if ok else 'DIFF'}  rows={sum(b.values())}"
        if paired:
            line += f"  (rounding: {paired} rows within {max_diff:.4g})"
        if table in UNKNOWN_KEYS:
            keys = UNKNOWN_KEYS[table]
            bu = bq_rows(f"SELECT {', '.join(f'COUNTIF({k} = -1)' for k in keys)} FROM `{args.project}.gold.{table}`")[0]
            du = db_rows(f"SELECT {', '.join(f'count_if({k} IS NULL)' for k in keys)} FROM globalmart.gold.{table}")[0]
            line += "  unknown keys " + ", ".join(f"{k}={x}" for k, x in zip(keys, bu))
            if bu != du:
                ok = False
                line += f"  (Databricks NULL keys: {du})"
        print(line)
        if not ok:
            failed = True
            for label, extra in (("only BigQuery", only_b), ("only Databricks", only_d)):
                if extra:
                    print(f"    {label}: {len(extra)}")
                    for row in sorted(extra)[:4]:
                        print("       ", row)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
