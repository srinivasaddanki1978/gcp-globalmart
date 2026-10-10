"""GlobalMart Bronze loader: incremental file ingestion from GCS into BigQuery.

Lists the source files in GCS, skips files that are already loaded, and appends
each new file to bronze.raw_<entity> with every column as STRING, plus
_source_file (full gs:// path) and _load_timestamp. Each loaded file is
recorded in ops.ingest_log, so running the loader twice loads nothing the
second time.

    python loader/main.py              # load new files
    python loader/main.py --dry-run    # only list what would be loaded

Configured by environment variables: GCP_PROJECT, RAW_BUCKET, SOURCE_PREFIX,
BQ_LOCATION.
"""

import argparse
import csv
import io
import json
import logging
import os
import re
import sys
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from datetime import datetime, timezone

from google.cloud import bigquery, storage

PROJECT = os.environ.get("GCP_PROJECT", "globalmart-gcp-lab")
BUCKET = os.environ.get("RAW_BUCKET", f"{PROJECT}-globalmart-raw")
PREFIX = os.environ.get("SOURCE_PREFIX", "source_data/")
LOCATION = os.environ.get("BQ_LOCATION", "us-central1")

BRONZE = "bronze"
INGEST_LOG = "ops.ingest_log"

# Entity -> expected file format. A file maps to an entity by its name prefix,
# e.g. "Region 3/orders_2021.csv" -> orders, "products.json" -> products.
ENTITY_FORMATS = {
    "customers": "csv",
    "orders": "csv",
    "transactions": "csv",
    "vendors": "csv",
    "returns": "json",
    "products": "json",
}
FILE_NAME = re.compile(r"^(?P<entity>[a-z]+)(?:_[^/]*)?\.(?P<ext>csv|json)$")

METADATA_COLUMNS = [
    bigquery.SchemaField("_source_file", "STRING"),
    bigquery.SchemaField("_load_timestamp", "TIMESTAMP"),
]

INGEST_LOG_SCHEMA = [
    bigquery.SchemaField("file_uri", "STRING", mode="REQUIRED"),
    bigquery.SchemaField("entity", "STRING", mode="REQUIRED"),
    bigquery.SchemaField("target_table", "STRING", mode="REQUIRED"),
    bigquery.SchemaField("row_count", "INT64"),
    bigquery.SchemaField("size_bytes", "INT64"),
    bigquery.SchemaField("generation", "INT64"),
    bigquery.SchemaField("md5_hash", "STRING"),
    bigquery.SchemaField("load_job_id", "STRING"),
    bigquery.SchemaField("loaded_at", "TIMESTAMP", mode="REQUIRED"),
    bigquery.SchemaField("note", "STRING"),
]

log = logging.getLogger("bronze_loader")


@dataclass
class SourceFile:
    uri: str
    name: str  # object name inside the bucket
    entity: str
    size: int
    generation: int
    md5_hash: str


# --- Parsing (pure functions, unit tested) -------------------------------------

def entity_for(object_name: str) -> str | None:
    """Return the entity for a source object name, or None if it isn't a source file."""
    m = FILE_NAME.match(object_name.rsplit("/", 1)[-1])
    if not m or ENTITY_FORMATS.get(m["entity"]) != m["ext"]:
        return None
    return m["entity"]


def _as_string(value) -> str | None:
    """Bronze keeps every value as text. JSON numbers arrive already as their raw
    text (see parse_json); nested values are kept as compact JSON."""
    if value is None:
        return None
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (dict, list)):
        return json.dumps(value, separators=(",", ":"), ensure_ascii=False)
    return str(value)


def parse_csv(text: str, source: str) -> tuple[list[str], list[dict]]:
    """CSV -> (columns, rows). Headers are lower-cased; empty fields become NULL
    (missing, not an empty string)."""
    reader = csv.reader(io.StringIO(text))
    header = [h.strip().lower() for h in next(reader)]
    _check_unique(header, source)
    rows = []
    for line_no, values in enumerate(reader, start=2):
        if not values:
            continue
        if len(values) != len(header):
            raise ValueError(f"{source}:{line_no}: {len(values)} fields, header has {len(header)}")
        rows.append({c: (v if v != "" else None) for c, v in zip(header, values)})
    return header, rows


def parse_json(text: str, source: str) -> tuple[list[str], list[dict]]:
    """JSON array (or NDJSON) -> (columns, rows). Keys are lower-cased. Numbers
    keep their original text (106.36 stays "106.36"), with no float round-trip."""
    as_text = {"parse_float": str, "parse_int": str, "parse_constant": str}
    stripped = text.lstrip()
    if stripped.startswith("["):
        records = json.loads(text, **as_text)
    else:
        records = [json.loads(line, **as_text) for line in text.splitlines() if line.strip()]

    columns: list[str] = []
    rows = []
    for i, record in enumerate(records):
        if not isinstance(record, dict):
            raise ValueError(f"{source}: element {i} is not a JSON object")
        keys = [k.strip().lower() for k in record]
        _check_unique(keys, source)
        for k in keys:
            if k not in columns:
                columns.append(k)
        rows.append({k: _as_string(v) for k, v in zip(keys, record.values())})
    return columns, rows


def _check_unique(columns: list[str], source: str) -> None:
    dupes = {c for c in columns if columns.count(c) > 1}
    if dupes:
        raise ValueError(f"{source}: columns collide after lower-casing: {sorted(dupes)}")


def merge_columns(existing: list[str], new: list[str]) -> list[str]:
    """Existing column order first, then new columns in first-seen order."""
    return existing + [c for c in new if c not in existing]


# --- GCS / BigQuery ------------------------------------------------------------

def list_source_files(gcs: storage.Client) -> list[SourceFile]:
    files = []
    for blob in gcs.list_blobs(BUCKET, prefix=PREFIX):
        entity = entity_for(blob.name)
        if entity is None:
            if not blob.name.endswith("/"):
                log.warning("skipping unrecognised object gs://%s/%s", BUCKET, blob.name)
            continue
        files.append(SourceFile(
            uri=f"gs://{BUCKET}/{blob.name}", name=blob.name, entity=entity,
            size=blob.size, generation=blob.generation, md5_hash=blob.md5_hash,
        ))
    return sorted(files, key=lambda f: f.uri)


def ensure_ingest_log(bq: bigquery.Client) -> None:
    table = bigquery.Table(f"{PROJECT}.{INGEST_LOG}", schema=INGEST_LOG_SCHEMA)
    table.description = "One row per source file loaded into bronze by the loader"
    bq.create_table(table, exists_ok=True)


def already_loaded(bq: bigquery.Client) -> set[str]:
    """URIs in ops.ingest_log, plus any _source_file already in bronze. The second
    set covers a crash between a bronze load and its ingest_log write; those files
    are backfilled into the log so they are never loaded twice."""
    logged = {r.file_uri for r in bq.query(f"SELECT DISTINCT file_uri FROM `{PROJECT}.{INGEST_LOG}`").result()}

    in_bronze: dict[str, str] = {}
    for entity in ENTITY_FORMATS:
        table_id = f"{PROJECT}.{BRONZE}.raw_{entity}"
        try:
            bq.get_table(table_id)
        except Exception:  # table not created yet
            continue
        sql = f"SELECT DISTINCT _source_file AS uri FROM `{table_id}`"
        for r in bq.query(sql).result():
            in_bronze[r.uri] = entity

    missing = {uri: e for uri, e in in_bronze.items() if uri not in logged}
    if missing:
        log.warning("backfilling %d ingest_log rows for files already in bronze", len(missing))
        now = datetime.now(timezone.utc)
        write_ingest_log(bq, [
            {"file_uri": uri, "entity": e, "target_table": f"{BRONZE}.raw_{e}",
             "loaded_at": now.isoformat(), "note": "recovered: found in bronze, missing from ingest_log"}
            for uri, e in missing.items()
        ])
    return logged | set(in_bronze)


def write_ingest_log(bq: bigquery.Client, rows: list[dict]) -> None:
    # A load job, not streaming inserts, so the rows are immediately DML-able.
    job = bq.load_table_from_json(rows, f"{PROJECT}.{INGEST_LOG}", job_config=bigquery.LoadJobConfig(
        schema=INGEST_LOG_SCHEMA, write_disposition="WRITE_APPEND",
    ))
    job.result()


def load_entity(bq: bigquery.Client, gcs: storage.Client, entity: str,
                files: list[SourceFile], load_ts: datetime) -> list[dict]:
    """Parse all new files for one entity and append them in a single load job.
    Returns the ingest_log rows for the files."""
    table_id = f"{PROJECT}.{BRONZE}.raw_{entity}"
    parse = parse_csv if ENTITY_FORMATS[entity] == "csv" else parse_json
    bucket = gcs.bucket(BUCKET)

    try:
        existing = [f.name for f in bq.get_table(table_id).schema if not f.name.startswith("_")]
    except Exception:
        existing = []

    columns = list(existing)
    ndjson = io.StringIO()
    counts: dict[str, int] = {}
    ts = load_ts.isoformat()
    # 10 workers = the storage client's HTTP connection pool size.
    with ThreadPoolExecutor(max_workers=10) as pool:
        texts = pool.map(lambda f: bucket.blob(f.name).download_as_bytes().decode("utf-8-sig"), files)
    for f, text in zip(files, texts):
        file_columns, rows = parse(text, f.uri)
        columns = merge_columns(columns, file_columns)
        for row in rows:
            row["_source_file"] = f.uri
            row["_load_timestamp"] = ts
            ndjson.write(json.dumps(row, ensure_ascii=False) + "\n")
        counts[f.uri] = len(rows)

    schema = [bigquery.SchemaField(c, "STRING") for c in columns] + METADATA_COLUMNS
    job = bq.load_table_from_file(
        io.BytesIO(ndjson.getvalue().encode("utf-8")), table_id,
        job_config=bigquery.LoadJobConfig(
            source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
            schema=schema,
            write_disposition="WRITE_APPEND",
            create_disposition="CREATE_IF_NEEDED",
            schema_update_options=[bigquery.SchemaUpdateOption.ALLOW_FIELD_ADDITION],
        ),
    )
    job.result()
    added = [c for c in columns if c not in existing]
    log.info("%s: loaded %d rows from %d files%s", table_id, sum(counts.values()), len(files),
             f" (new columns: {', '.join(added)})" if existing and added else "")

    return [{
        "file_uri": f.uri, "entity": entity, "target_table": f"{BRONZE}.raw_{entity}",
        "row_count": counts[f.uri], "size_bytes": f.size, "generation": f.generation,
        "md5_hash": f.md5_hash, "load_job_id": job.job_id, "loaded_at": ts,
    } for f in files]


def run(dry_run: bool) -> int:
    bq = bigquery.Client(project=PROJECT, location=LOCATION)
    gcs = storage.Client(project=PROJECT)

    ensure_ingest_log(bq)
    loaded = already_loaded(bq)
    sources = list_source_files(gcs)
    new = [f for f in sources if f.uri not in loaded]
    log.info("found %d source files, %d already loaded, %d new", len(sources), len(sources) - len(new), len(new))

    by_entity: dict[str, list[SourceFile]] = defaultdict(list)
    for f in new:
        by_entity[f.entity].append(f)
    for entity, files in sorted(by_entity.items()):
        log.info("%s: %d new files", entity, len(files))
    if dry_run or not new:
        return 0

    load_ts = datetime.now(timezone.utc)
    for entity, files in sorted(by_entity.items()):
        write_ingest_log(bq, load_entity(bq, gcs, entity, files, load_ts))
    log.info("done: %d files loaded", len(new))
    return 0


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--dry-run", action="store_true", help="list new files without loading")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s", stream=sys.stdout)
    sys.exit(run(args.dry_run))


if __name__ == "__main__":
    main()
