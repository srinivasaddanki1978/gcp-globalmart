"""GlobalMart data agent on the Conversational Analytics API (v1).

    python agent/data_agent.py deploy            # create or update from agent_context.yaml
    python agent/data_agent.py ask "question"    # one question: answer, SQL, rows
    python agent/data_agent.py test [--only id]  # run test_questions.yaml and score it
    python agent/data_agent.py delete            # remove the agent (teardown)

Auth: Application Default Credentials (gcloud auth application-default login).
The agent queries BigQuery as the signed-in user.
"""

import argparse
import json
import math
import os
import sys
import time
from pathlib import Path

import google.auth
import yaml
from google.auth.transport.requests import AuthorizedSession
from google.cloud import bigquery

HERE = Path(__file__).parent
PROJECT = os.environ.get("GCP_PROJECT", "globalmart-gcp-lab")
LOCATION = "global"
API = "https://geminidataanalytics.googleapis.com/v1"
PARENT = f"projects/{PROJECT}/locations/{LOCATION}"


def session() -> AuthorizedSession:
    creds, _ = google.auth.default(scopes=["https://www.googleapis.com/auth/cloud-platform"])
    s = AuthorizedSession(creds)
    s.headers["x-goog-user-project"] = PROJECT
    return s


def call(s: AuthorizedSession, method: str, url: str, **kwargs):
    r = s.request(method, url, timeout=300, **kwargs)
    if r.status_code >= 400:
        raise RuntimeError(f"{method} {url} -> {r.status_code}: {r.text[:1000]}")
    return r.json() if r.text else {}


def wait(s: AuthorizedSession, op: dict) -> dict:
    while not op.get("done"):
        time.sleep(2)
        op = call(s, "GET", f"{API}/{op['name']}")
    if "error" in op:
        raise RuntimeError(f"operation failed: {op['error']}")
    return op.get("response", {})


# --- deploy --------------------------------------------------------------------

def agent_body(cfg: dict) -> dict:
    context = {
        "systemInstruction": cfg["system_instruction"],
        "datasourceReferences": {"bq": {"tableReferences": [
            {"projectId": PROJECT, "datasetId": ds, "tableId": t}
            for ds, tables in cfg["tables"].items() for t in tables
        ]}},
        "exampleQueries": [
            {"naturalLanguageQuestion": e["question"], "sqlQuery": e["sql"].format(project=PROJECT).strip()}
            for e in cfg.get("example_queries", [])
        ],
        "glossaryTerms": [
            {"displayName": g["term"], "description": g["description"]} for g in cfg.get("glossary", [])
        ],
    }
    return {
        "displayName": cfg["display_name"],
        "description": cfg["description"].strip(),
        "dataAnalyticsAgent": {"stagingContext": context, "publishedContext": context},
    }


def deploy(s: AuthorizedSession, cfg: dict) -> None:
    name = f"{PARENT}/dataAgents/{cfg['agent_id']}"
    body = agent_body(cfg)
    r = s.get(f"{API}/{name}", timeout=60)
    if r.status_code == 404:
        op = call(s, "POST", f"{API}/{PARENT}/dataAgents", params={"dataAgentId": cfg["agent_id"]}, json=body)
        action = "created"
    else:
        mask = "displayName,description,dataAnalyticsAgent.stagingContext,dataAnalyticsAgent.publishedContext"
        op = call(s, "PATCH", f"{API}/{name}", params={"updateMask": mask}, json=body)
        action = "updated"
    wait(s, op)
    tables = sum(len(t) for t in cfg["tables"].values())
    print(f"{action} {name} ({tables} tables, {len(body['dataAnalyticsAgent']['publishedContext']['exampleQueries'])} example queries)")


# --- chat ----------------------------------------------------------------------

def ask(s: AuthorizedSession, agent_id: str, question: str) -> dict:
    """Ask one question; return final text, generated SQL and result rows."""
    messages = call(s, "POST", f"{API}/{PARENT}:chat", json={
        "messages": [{"userMessage": {"text": question}}],
        "dataAgentContext": {"dataAgent": f"{PARENT}/dataAgents/{agent_id}", "contextVersion": "PUBLISHED"},
    })
    out = {"text": [], "sql": None, "rows": [], "errors": []}
    for m in messages if isinstance(messages, list) else [messages]:
        sm = m.get("systemMessage", {})
        if "text" in sm and sm["text"].get("textType") == "FINAL_RESPONSE":
            out["text"] += sm["text"].get("parts", [])
        data = sm.get("data", {})
        if data.get("generatedSql"):
            out["sql"] = data["generatedSql"]
        if data.get("result", {}).get("data"):
            out["rows"] = data["result"]["data"]
        if "error" in sm:
            out["errors"].append(sm["error"])
    out["text"] = "\n".join(out["text"]).strip()
    return out


# --- test ----------------------------------------------------------------------

def leaves(value) -> list:
    if isinstance(value, dict):
        return [x for v in value.values() for x in leaves(v)]
    if isinstance(value, (list, tuple)):
        return [x for v in value for x in leaves(v)]
    return [value]


def as_number(v):
    try:
        f = float(v)
        return f if math.isfinite(f) else None
    except (TypeError, ValueError):
        return None


def found(expected, actual: list) -> bool:
    n = as_number(expected)
    if n is not None:
        return any((a := as_number(x)) is not None and abs(a - n) <= max(0.01, abs(n) * 0.005) for x in actual)
    e = str(expected).strip().lower()
    return any(str(x).strip().lower() == e for x in actual)


def run_tests(s: AuthorizedSession, agent_id: str, only: list | None) -> int:
    bq = bigquery.Client(project=PROJECT, location="us-central1")
    tests = yaml.safe_load((HERE / "test_questions.yaml").read_text())["questions"]
    passed, total = 0, 0
    report = []
    for t in tests:
        if only and t["id"] not in only:
            continue
        total += 1
        expected = [v for r in bq.query(t["golden_sql"]).result() for v in r.values()]
        try:
            res = ask(s, agent_id, t["question"])
        except RuntimeError as e:
            res = {"text": "", "sql": None, "rows": [], "errors": [str(e)]}
        actual = leaves(res["rows"])
        missing = [e for e in expected if not found(e, actual)]
        ok = not missing and bool(res["rows"])
        passed += ok
        print(f"{'PASS' if ok else 'FAIL'}  {t['id']}: {t['question']}")
        if not ok:
            print(f"      missing expected values: {missing[:5]}  errors: {res['errors'][:1]}")
        report.append({"id": t["id"], "question": t["question"], "passed": ok, "expected": expected,
                       "agent_rows": res["rows"][:20], "generated_sql": res["sql"], "answer": res["text"]})
    out = HERE / "test_results.json"
    out.write_text(json.dumps(report, indent=2, default=str))
    print(f"\n{passed}/{total} correct (target >= 9/10). SQL and answers: {out}")
    return 0 if passed >= math.ceil(total * 0.9) else 1


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("deploy")
    a = sub.add_parser("ask")
    a.add_argument("question")
    t = sub.add_parser("test")
    t.add_argument("--only", nargs="*")
    sub.add_parser("delete")
    args = parser.parse_args()

    cfg = yaml.safe_load((HERE / "agent_context.yaml").read_text())
    s = session()
    if args.cmd == "deploy":
        deploy(s, cfg)
    elif args.cmd == "delete":
        wait(s, call(s, "DELETE", f"{API}/{PARENT}/dataAgents/{cfg['agent_id']}"))
        print(f"deleted {cfg['agent_id']}")
    elif args.cmd == "ask":
        res = ask(s, cfg["agent_id"], args.question)
        print(res["text"] or "(no text)", "\n\nSQL:\n", res["sql"], "\n\nRows:", json.dumps(res["rows"][:10], indent=1))
    else:
        sys.exit(run_tests(s, cfg["agent_id"], args.only))


if __name__ == "__main__":
    main()
