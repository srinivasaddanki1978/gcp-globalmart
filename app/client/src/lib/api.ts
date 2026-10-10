// Data access for the pages: same shape as AppKit's useAnalyticsQuery, backed by
// POST /api/query/:key (allowlisted SQL files run on BigQuery).
import { useEffect, useState } from 'react';

export type Row = Record<string, any>; // eslint-disable-line @typescript-eslint/no-explicit-any

/** Parameter helpers kept for page compatibility: values are sent as plain JSON. */
export const sql = {
  number: (v: number) => v,
  string: (v: string) => v,
  boolean: (v: boolean) => v,
};

const inflight = new Map<string, Promise<Row[]>>();

export function fetchQuery(key: string, parameters: Record<string, unknown> = {}): Promise<Row[]> {
  const id = `${key}:${JSON.stringify(parameters)}`;
  let p = inflight.get(id);
  if (!p) {
    p = fetch(`/api/query/${encodeURIComponent(key)}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ parameters }),
    })
      .then(async (r) => {
        const body = await r.json().catch(() => ({}));
        if (!r.ok) throw new Error(body.error ?? `HTTP ${r.status}`);
        return body.rows as Row[];
      })
      .finally(() => setTimeout(() => inflight.delete(id), 0));
    inflight.set(id, p);
  }
  return p;
}

export function useAnalyticsQuery(key: string, parameters: Record<string, unknown> = {}) {
  const [state, setState] = useState<{ data?: Row[]; loading: boolean; error?: string }>({ loading: true });
  const paramKey = JSON.stringify(parameters);
  useEffect(() => {
    let live = true;
    setState((s) => ({ data: s.data, loading: true }));
    fetchQuery(key, JSON.parse(paramKey))
      .then((data) => live && setState({ data, loading: false }))
      .catch((e: Error) => live && setState({ loading: false, error: e.message }));
    return () => {
      live = false;
    };
  }, [key, paramKey]);
  return state;
}
