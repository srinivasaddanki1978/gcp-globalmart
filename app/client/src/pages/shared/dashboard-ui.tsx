import { Card, CardContent, CardHeader, CardTitle, Skeleton } from '../../lib/components';
import type { ReactNode } from 'react';

export const currency = (value: string | number) =>
  `$${Number(value).toLocaleString('en-US', { maximumFractionDigits: 0 })}`;

export const count = (value: string | number) => Number(value).toLocaleString('en-US');

export const percent = (value: string | number) => `${Number(value).toFixed(1)}%`;

/** Year-over-year change: ▲ green / ▼ red (inverted for "lower is better" measures). */
export function Delta({ value, suffix = '%', invert = false }: { value?: number | null; suffix?: string; invert?: boolean }) {
  if (value === null || value === undefined || Number.isNaN(Number(value))) return null;
  const v = Number(value);
  const good = invert ? v < 0 : v > 0;
  const color = v === 0 ? 'text-muted-foreground' : good ? 'text-green-600' : 'text-red-600';
  return (
    <span className={`font-semibold ${color}`}>
      {v > 0 ? '▲' : v < 0 ? '▼' : '■'} {Math.abs(v).toFixed(1)}
      {suffix}
    </span>
  );
}

/** Headline number with a loading skeleton and an optional year-over-year change. */
export function Kpi({
  label,
  value,
  loading,
  delta,
  deltaSuffix,
  invert,
  note,
}: {
  label: string;
  value?: string;
  loading: boolean;
  delta?: number | null;
  deltaSuffix?: string;
  invert?: boolean;
  note?: string;
}) {
  return (
    <Card className="shadow-lg">
      <CardHeader>
        <CardTitle className="text-sm font-medium text-muted-foreground">{label}</CardTitle>
      </CardHeader>
      <CardContent>
        {loading ? (
          <Skeleton className="h-8 w-28" />
        ) : (
          <>
            <div className="text-2xl font-bold text-primary">{value ?? '—'}</div>
            {(note || (delta !== undefined && delta !== null)) && (
              <div className="mt-1 text-xs text-muted-foreground">
                <Delta value={delta} suffix={deltaSuffix} invert={invert} /> {note}
              </div>
            )}
          </>
        )}
      </CardContent>
    </Card>
  );
}

/** Page header naming the dashboard and the BigQuery table behind it. */
export function DashboardHeader({
  title,
  source,
  children,
}: {
  title: string;
  source: string;
  children?: ReactNode;
}) {
  return (
    <div className="flex items-end justify-between gap-6 flex-wrap">
      <div>
        <h1 className="text-2xl font-bold">{title}</h1>
        <p className="text-sm text-muted-foreground">
          Source: <code>{source}</code>
        </p>
      </div>
      {children}
    </div>
  );
}

/** Titled card wrapper for a single chart. */
export function ChartCard({
  title,
  wide,
  children,
}: {
  title: string;
  wide?: boolean;
  children: ReactNode;
}) {
  return (
    <Card className={`shadow-lg flex min-w-0${wide ? ' lg:col-span-2' : ''}`}>
      <CardHeader>
        <CardTitle>{title}</CardTitle>
      </CardHeader>
      <CardContent>{children}</CardContent>
    </Card>
  );
}
