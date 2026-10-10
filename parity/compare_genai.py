"""GenAI parity: compare the deterministic parts of the four GenAI tables with
Databricks. AI-written text differs by design (Risk 3), so only the inputs,
counts and KPI figures are compared; the text is checked for presence.

    python parity/compare_genai.py --warehouse-id <id>
"""

import argparse
import json
import sys

from google.cloud import bigquery

from compare_gold import close, norm
from run_databricks_baseline import run_statement


def flatten(value, prefix=""):
    """JSON -> {path: leaf} so KPI documents can be compared field by field."""
    if isinstance(value, dict):
        out = {}
        for k, v in value.items():
            out.update(flatten(v, f"{prefix}.{k}" if prefix else k))
        return out
    if isinstance(value, list):
        out = {}
        for i, v in enumerate(value):
            out.update(flatten(v, f"{prefix}[{i}]"))
        return out
    return {prefix: norm(value)}


def within(a, b, tolerance: float) -> bool:
    try:
        return abs(float(a) - float(b)) <= tolerance + 1e-9
    except (TypeError, ValueError):
        return False


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", default="free")
    parser.add_argument("--warehouse-id", required=True)
    parser.add_argument("--project", default="globalmart-gcp-lab")
    args = parser.parse_args()
    bq = bigquery.Client(project=args.project, location="us-central1")

    def bq_rows(sql):
        return [tuple(norm(v) for v in r.values()) for r in bq.query(sql.replace("{s}", f"`{args.project}.gold`")).result()]

    def db_rows(sql):
        return [tuple(norm(v) for v in r) for r in run_statement(args.profile, args.warehouse_id, sql.replace("{s}", "globalmart.gold"))[1]]

    failed = False

    def report(name, ok, detail=""):
        nonlocal failed
        failed |= not ok
        print(f"{name:34} {'OK' if ok else 'DIFF'}  {detail}")

    # UC1: one row per failing rule with counts and rate
    sql = ("SELECT entity, affected_field, issue_type, rejected_count, total_entity_records, rejection_rate_pct "
           "FROM {s}.dq_audit_report ORDER BY entity, affected_field")
    b, d = bq_rows(sql), db_rows(sql)
    missing = bq_rows("SELECT COUNTIF(ai_explanation IS NULL) FROM {s}.dq_audit_report")[0][0]
    report("dq_audit_report", b == d, f"rows={len(b)}  missing explanations={missing}")

    # UC2: flagged customers and their scores (reasons compared as a sorted list)
    reasons = {"bq": "ARRAY_TO_STRING(ARRAY(SELECT x FROM UNNEST(SPLIT(return_reasons, ', ')) x ORDER BY x), ', ')",
               "db": "array_join(array_sort(split(return_reasons, ', ')), ', ')"}
    cols = ("customer_id, total_returns, total_refund_value, avg_refund_per_return, approval_rate, "
            "distinct_reason_count, {r}, anomaly_score, rules_violated")
    b = sorted(bq_rows(f"SELECT {cols.format(r=reasons['bq'])} FROM {{s}}.flagged_return_customers"))
    d = sorted(db_rows(f"SELECT {cols.format(r=reasons['db'])} FROM {{s}}.flagged_return_customers"))
    missing = bq_rows("SELECT COUNTIF(investigation_brief IS NULL) FROM {s}.flagged_return_customers")[0][0]
    report("flagged_return_customers", b == d, f"flagged={len(b)} (Databricks {len(d)})  missing briefs={missing}")

    # UC3: same questions answered, same number of retrieved documents
    sql = "SELECT question, retrieved_count FROM {s}.rag_query_history ORDER BY question"
    b, d = bq_rows(sql), db_rows(sql)
    missing = bq_rows("SELECT COUNTIF(answer IS NULL) FROM {s}.rag_query_history")[0][0]
    report("rag_query_history", b == d, f"questions={len(b)}  missing answers={missing}")

    # UC4: KPI JSON field by field (numbers within a cent)
    sql = "SELECT insight_type, kpi_data FROM {s}.ai_business_insights ORDER BY insight_type"
    b = {r[0]: flatten(json.loads(r[1])) for r in bq_rows(sql)}
    d = {r[0]: flatten(json.loads(r[1])) for r in db_rows(sql)}
    for insight in sorted(set(b) | set(d)):
        bk, dk = b.get(insight, {}), d.get(insight, {})
        diffs = [k for k in sorted(set(bk) | set(dk)) if not close(bk.get(k, "<missing>"), dk.get(k, "<missing>"))]
        # Totals here are sums of already-rounded metric rows, some of which differ by
        # one cent (Databricks float sums), so cents accumulate: allow up to $0.10.
        rounding = [k for k in diffs if within(bk.get(k), dk.get(k), 0.10)]
        diffs = [k for k in diffs if k not in rounding]
        detail = f"fields={len(bk)}" + (f"  (rounding: {', '.join(rounding)})" if rounding else "")
        report(f"ai_business_insights:{insight}", not diffs, detail)
        for k in diffs[:6]:
            print(f"    {k}: BigQuery {bk.get(k, '<missing>')} vs Databricks {dk.get(k, '<missing>')}")
    missing = bq_rows("SELECT COUNTIF(executive_summary IS NULL) FROM {s}.ai_business_insights")[0][0]
    print(f"{'':34}     missing summaries={missing}")

    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
