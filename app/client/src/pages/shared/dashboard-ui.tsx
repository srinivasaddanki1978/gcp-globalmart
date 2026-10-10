import { Card, CardContent, CardHeader, CardTitle, Skeleton } from '../../lib/components';
import type { ReactNode } from 'react';

export const currency = (value: string | number) =>
  `$${Number(value).toLocaleString('en-US', { maximumFractionDigits: 0 })}`;

export const count = (value: string | number) => Number(value).toLocaleString('en-US');

export const percent = (value: string | number) => `${Number(value).toFixed(1)}%`;

/** Single headline number with a loading skeleton. */
export function Kpi({ label, value, loading }: { label: string; value?: string; loading: boolean }) {
  return (
    <Card className="shadow-lg">
      <CardHeader>
        <CardTitle className="text-sm font-medium text-muted-foreground">{label}</CardTitle>
      </CardHeader>
      <CardContent>
        {loading ? (
          <Skeleton className="h-8 w-28" />
        ) : (
          <div className="text-2xl font-bold text-primary">{value ?? '—'}</div>
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
