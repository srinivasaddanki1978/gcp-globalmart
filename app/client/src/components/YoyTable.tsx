import { useAnalyticsQuery, type Row } from '../lib/api';
import { Skeleton } from '../lib/ui';
import { Delta } from '../pages/shared/dashboard-ui';

export interface Column {
  key: string;
  header: string;
  format?: (v: number) => string;
  /** Render as a ▲/▼ change; `suffix` '%' or ' pts'; `invert` when lower is better. */
  change?: { suffix?: string; invert?: boolean };
}

/** A table of rows from one query, with year-over-year columns coloured ▲ green / ▼ red. */
export function YoyTable({ queryKey, parameters, columns }: { queryKey: string; parameters: Record<string, unknown>; columns: Column[] }) {
  const { data, loading, error } = useAnalyticsQuery(queryKey, parameters);
  if (loading) return <Skeleton className="h-40 w-full" />;
  if (error) return <div className="text-sm text-destructive">Error: {error}</div>;
  if (!data?.length) return <div className="text-sm text-muted-foreground">No data</div>;
  const cell = (r: Row, c: Column) => {
    const v = r[c.key];
    if (c.change) return <Delta value={v} suffix={c.change.suffix} invert={c.change.invert} />;
    if (v === null || v === undefined) return <span className="text-muted-foreground">—</span>;
    return c.format && typeof v === 'number' ? c.format(v) : String(v);
  };
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <thead>
          <tr className="border-b text-left text-xs text-muted-foreground">
            {columns.map((c, i) => (
              <th key={c.key} className={`py-2 pr-3 font-medium ${i ? 'text-right' : ''}`}>
                {c.header}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {data.map((r, ri) => (
            <tr key={ri} className="border-b last:border-0">
              {columns.map((c, i) => (
                <td key={c.key} className={`py-2 pr-3 ${i ? 'text-right tabular-nums' : 'font-medium'}`}>
                  {cell(r, c)}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
