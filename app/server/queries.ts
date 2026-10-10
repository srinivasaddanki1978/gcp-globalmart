// Query allowlist: only files in queries/*.sql can run. Each declares its parameters
// in a header (`-- @param name INT64`), and requests are validated against it before
// the SQL runs as a BigQuery named-parameter query (@name).
import { readdirSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { BigQuery, type Query } from '@google-cloud/bigquery';

export type ParamType = 'INT64' | 'FLOAT64' | 'STRING' | 'BOOL';
export interface QueryDef {
  key: string;
  sql: string;
  params: Record<string, ParamType>;
}

export class QueryError extends Error {
  constructor(
    message: string,
    readonly status = 400,
  ) {
    super(message);
  }
}

const PARAM_HEADER = /^--\s*@param\s+(\w+)\s+(INT64|FLOAT64|STRING|BOOL)\s*$/gm;

export function parseQuery(key: string, sql: string): QueryDef {
  const params: Record<string, ParamType> = {};
  for (const m of sql.matchAll(PARAM_HEADER)) params[m[1]] = m[2] as ParamType;
  return { key, sql, params };
}

export function loadQueries(dir: string): Map<string, QueryDef> {
  const defs = new Map<string, QueryDef>();
  for (const file of readdirSync(dir).filter((f) => f.endsWith('.sql')).sort()) {
    const key = path.basename(file, '.sql');
    defs.set(key, parseQuery(key, readFileSync(path.join(dir, file), 'utf8')));
  }
  return defs;
}

/** Check request parameters against the query's declared types; returns typed values. */
export function validateParams(def: QueryDef, input: unknown): Record<string, number | string | boolean> {
  const given = (input ?? {}) as Record<string, unknown>;
  if (typeof given !== 'object' || Array.isArray(given)) throw new QueryError('parameters must be an object');
  const unknown = Object.keys(given).filter((k) => !(k in def.params));
  if (unknown.length) throw new QueryError(`unknown parameter(s): ${unknown.join(', ')}`);

  const out: Record<string, number | string | boolean> = {};
  for (const [name, type] of Object.entries(def.params)) {
    const v = given[name];
    if (v === undefined || v === null) throw new QueryError(`missing parameter: ${name}`);
    const ok =
      (type === 'INT64' && Number.isSafeInteger(v)) ||
      (type === 'FLOAT64' && typeof v === 'number' && Number.isFinite(v)) ||
      (type === 'STRING' && typeof v === 'string' && v.length <= 200) ||
      (type === 'BOOL' && typeof v === 'boolean');
    if (!ok) throw new QueryError(`parameter ${name} must be ${type}`);
    out[name] = v as number | string | boolean;
  }
  return out;
}

/** BigQuery returns INT64/NUMERIC/DATE etc. as wrapper objects; flatten to JSON values. */
export function plain(value: unknown): unknown {
  if (value === null || typeof value !== 'object') return value;
  if (value instanceof Date) return value.toISOString();
  if ('value' in value) {
    const v = (value as { value: unknown }).value;
    const n = Number(v);
    return typeof v === 'string' && v !== '' && Number.isFinite(n) && /^-?[\d.]+(e[-+]?\d+)?$/i.test(v) ? n : v;
  }
  if (typeof (value as { toNumber?: unknown }).toNumber === 'function') return (value as { toNumber(): number }).toNumber();
  return value;
}

export function queryOptions(def: QueryDef, params: Record<string, unknown>, location: string): Query {
  return {
    query: def.sql,
    params,
    types: def.params as Record<string, string>,
    location,
    maximumBytesBilled: String(1024 ** 3), // 1 GiB guard per query
    useLegacySql: false,
  };
}

export class QueryRunner {
  private cache = new Map<string, { at: number; rows: Record<string, unknown>[] }>();

  constructor(
    private bq: BigQuery,
    private defs: Map<string, QueryDef>,
    private location: string,
    private ttlMs = 5 * 60_000,
  ) {}

  async run(key: string, input: unknown): Promise<Record<string, unknown>[]> {
    const def = this.defs.get(key);
    if (!def) throw new QueryError(`unknown query: ${key}`, 404);
    const params = validateParams(def, input);
    const cacheKey = `${key}:${JSON.stringify(params)}`;
    const hit = this.cache.get(cacheKey);
    if (hit && Date.now() - hit.at < this.ttlMs) return hit.rows;

    const [rows] = await this.bq.query(queryOptions(def, params, this.location));
    const out = rows.map((r: Record<string, unknown>) =>
      Object.fromEntries(Object.entries(r).map(([k, v]) => [k, plain(v)])),
    );
    this.cache.set(cacheKey, { at: Date.now(), rows: out });
    return out;
  }
}
