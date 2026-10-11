// Chart components (BarChart, LineChart, AreaChart, DonutChart) drawn with Recharts.
// Props: queryKey, parameters, xKey, yKey, valueFormatter, showLegend. Each fetches its own query.
import {
  Area,
  AreaChart as RArea,
  Bar,
  BarChart as RBar,
  CartesianGrid,
  Cell,
  Legend,
  Line,
  LineChart as RLine,
  Pie,
  PieChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts';
import type { ReactNode } from 'react';
import { useAnalyticsQuery } from './api';

export const PALETTE = [
  '#2563eb', '#16a34a', '#f59e0b', '#db2777', '#7c3aed', '#0891b2',
  '#dc2626', '#65a30d', '#ea580c', '#4f46e5', '#0d9488', '#a16207',
];

interface ChartProps {
  queryKey: string;
  parameters?: Record<string, unknown>;
  xKey: string;
  yKey: string | string[];
  valueFormatter?: (v: number) => string;
  showLegend?: boolean;
  /** Line charts: draw a marker at each point. */
  showSymbol?: boolean;
  /** Display names for series, e.g. { revenue: '2025', revenue_prior: '2024' }. */
  labels?: Record<string, string>;
  /** Series drawn dashed (lines) or faded (bars/areas), e.g. the prior year. */
  dashed?: string[];
  height?: number;
}

const label = (k: string) => k.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());
const seriesName = (p: ChartProps, k: string) => p.labels?.[k] ?? label(k);
const compact = (v: number) => Intl.NumberFormat('en-US', { notation: 'compact', maximumFractionDigits: 1 }).format(v);

/** Comparison series (the prior year) are grey, so "this year vs last year" reads at a glance. */
const PRIOR = '#94a3b8';
function color(p: ChartProps, k: string, i: number) {
  return p.dashed?.includes(k) ? PRIOR : PALETTE[i % PALETTE.length];
}

function useChartData({ queryKey, parameters }: ChartProps) {
  const { data, loading, error } = useAnalyticsQuery(queryKey, parameters);
  return { data: data ?? [], loading, error };
}

function Frame({ loading, error, empty, height, children }: { loading: boolean; error?: string; empty: boolean; height: number; children: ReactNode }) {
  if (loading) return <div className="w-full animate-pulse rounded-md bg-muted" style={{ height }} />;
  if (error) return <div className="text-sm text-destructive">Error: {error}</div>;
  if (empty) return <div className="text-sm text-muted-foreground">No data</div>;
  return (
    <div style={{ height }}>
      <ResponsiveContainer width="100%" height="100%">
        {children as never}
      </ResponsiveContainer>
    </div>
  );
}

function cartesian(kind: 'bar' | 'line' | 'area', props: ChartProps) {
  const { data, loading, error } = useChartData(props);
  const keys = Array.isArray(props.yKey) ? props.yKey : [props.yKey];
  const fmt = props.valueFormatter ?? ((v: number) => v.toLocaleString('en-US'));
  const height = props.height ?? 300;
  const common = (
    <>
      <CartesianGrid strokeDasharray="3 3" vertical={false} />
      <XAxis dataKey={props.xKey} tick={{ fontSize: 12 }} interval="preserveStartEnd" />
      <YAxis tickFormatter={compact} tick={{ fontSize: 12 }} width={56} />
      <Tooltip formatter={(v) => (v === null || v === undefined ? '—' : fmt(Number(v)))} />
      {props.showLegend && <Legend itemSorter={() => 0} />}  {/* keep series order, not alphabetical */}
    </>
  );
  const Chart = kind === 'bar' ? RBar : kind === 'line' ? RLine : RArea;
  return (
    <Frame loading={loading} error={error} empty={!data.length} height={height}>
      <Chart data={data} margin={{ top: 8, right: 8, left: 0, bottom: 0 }}>
        {common}
        {keys.map((k, i) =>
          kind === 'bar' ? (
            <Bar key={k} dataKey={k} name={seriesName(props, k)} fill={color(props, k, i)} fillOpacity={props.dashed?.includes(k) ? 0.7 : 1} radius={[3, 3, 0, 0]} isAnimationActive={false} />
          ) : kind === 'line' ? (
            <Line key={k} dataKey={k} name={seriesName(props, k)} stroke={color(props, k, i)} strokeWidth={2} strokeDasharray={props.dashed?.includes(k) ? '6 4' : undefined} dot={props.showSymbol ? { r: 3 } : false} connectNulls={false} isAnimationActive={false} />
          ) : (
            <Area key={k} dataKey={k} name={seriesName(props, k)} stroke={color(props, k, i)} strokeDasharray={props.dashed?.includes(k) ? '6 4' : undefined} fill={color(props, k, i)} fillOpacity={props.dashed?.includes(k) ? 0.05 : 0.15} isAnimationActive={false} />
          ),
        )}
      </Chart>
    </Frame>
  );
}

export const BarChart = (p: ChartProps) => cartesian('bar', p);
export const LineChart = (p: ChartProps) => cartesian('line', p);
export const AreaChart = (p: ChartProps) => cartesian('area', p);

export function DonutChart(props: ChartProps) {
  const { data, loading, error } = useChartData(props);
  const key = Array.isArray(props.yKey) ? props.yKey[0] : props.yKey;
  const fmt = props.valueFormatter ?? ((v: number) => v.toLocaleString('en-US'));
  return (
    <Frame loading={loading} error={error} empty={!data.length} height={props.height ?? 300}>
      <PieChart>
        <Pie data={data} dataKey={key} nameKey={props.xKey} innerRadius="55%" outerRadius="85%" paddingAngle={1} isAnimationActive={false}>
          {data.map((_, i) => (
            <Cell key={i} fill={PALETTE[i % PALETTE.length]} />
          ))}
        </Pie>
        <Tooltip formatter={(v) => fmt(Number(v))} />
        <Legend />
      </PieChart>
    </Frame>
  );
}
