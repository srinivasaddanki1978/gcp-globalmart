import {
  Accordion, AccordionContent, AccordionItem, AccordionTrigger, Badge, BarChart, Card, CardContent, CardHeader, CardTitle,
  LineChart, Skeleton, useAnalyticsQuery,
} from '../../lib/components';
import { FilterBar, FilterSelect, useFilterOptions } from '../../components/FilterBar';
import { YoyTable } from '../../components/YoyTable';
import { RETURN_STATUSES, comparisonNote, useFilters, yoyDelta } from '../../lib/filters';
import { ChartCard, DashboardHeader, Kpi, count, currency, percent } from '../shared/dashboard-ui';

/** Minimum anomaly score for review (matches the UC2 flag threshold). */
const MIN_ANOMALY = 40;

/** Returns over time (with YoY) and customers flagged for review with AI briefs. */
export function FraudPage() {
  const { filters } = useFilters();
  const options = useFilterOptions();
  const year = filters.target_year;
  const params = { ...filters, min_anomaly: MIN_ANOMALY };

  const { data: rk, loading: rkl, error: rke } = useAnalyticsQuery('returns_kpi_yoy', params);
  const { data: regions, loading: rl, error: re } = useAnalyticsQuery('flagged_by_region', params);
  const { data: customers, loading: cl, error: ce } = useAnalyticsQuery('flagged_customers', params);
  const k = rk?.[0];
  const note = comparisonNote(k);
  const flagged = regions?.reduce((s, r) => s + Number(r.flagged_customers), 0);
  const atRisk = regions?.reduce((s, r) => s + Number(r.total_refund_value), 0);
  const error = rke || re || ce;
  const approvalChange = k && k.approval_rate_prior !== null ? k.approval_rate - k.approval_rate_prior : null;

  return (
    <div className="space-y-6 w-full max-w-7xl mx-auto">
      <DashboardHeader title="Returns & Fraud" source="gold.rpt_return_lines + flagged_return_customers" />
      <FilterBar>
        <FilterSelect name="return_reason" label="Return reason" options={options('return_reason')} />
        <FilterSelect name="return_status" label="Status" options={[{ value: 'All', label: 'All' }, ...RETURN_STATUSES.map((s) => ({ value: s, label: s }))]} />
      </FilterBar>
      {error && <div className="text-destructive bg-destructive/10 p-3 rounded-md">Error: {error}</div>}

      <h2 className="text-lg font-semibold">Returns in the period</h2>
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <Kpi label="Returns" value={k && count(k.returns)} delta={yoyDelta(k, k?.returns_yoy)} invert note={note} loading={rkl} />
        <Kpi label="Refunded" value={k && currency(k.refunded)} delta={yoyDelta(k, k?.refunded_yoy)} invert note={note} loading={rkl} />
        <Kpi label="Approval Rate" value={k && percent(k.approval_rate)} delta={yoyDelta(k, approvalChange)} deltaSuffix=" pts" note={note} loading={rkl} />
        <Kpi label="Avg Refund" value={k && currency(k.avg_refund)} loading={rkl} />
      </div>
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <ChartCard title={`Refunds by Month: ${year} vs ${year - 1}`}>
          <LineChart queryKey="returns_by_month" parameters={params} xKey="month_name" yKey={['refunded', 'refunded_prior']}
            labels={{ refunded: String(year), refunded_prior: String(year - 1) }} dashed={['refunded_prior']} valueFormatter={currency} showLegend showSymbol />
        </ChartCard>
        <ChartCard title="Return Reasons: Change vs Last Year">
          <YoyTable queryKey="return_reasons_yoy" parameters={params} columns={[
            { key: 'return_reason', header: 'Reason' },
            { key: 'returns', header: 'Returns', format: count },
            { key: 'refunded', header: 'Refunded', format: currency },
            { key: 'yoy_pct', header: 'YoY', change: { invert: true } },
          ]} />
        </ChartCard>
      </div>

      <h2 className="text-lg font-semibold">Customers flagged for review</h2>
      <p className="text-sm text-muted-foreground">
        Scored on each customer's last 12 months of returns against data-driven thresholds; {MIN_ANOMALY}+ flags them for
        review. Region and segment filters apply here; the year and period don't. Briefs are written by the UC2 fraud
        investigator (Gemini). Names and emails are masked (personal data).
      </p>
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <Kpi label="Flagged Customers" value={flagged !== undefined ? count(flagged) : undefined} loading={rl} />
        <Kpi label="Refunds Under Review" value={atRisk !== undefined ? currency(atRisk) : undefined} loading={rl} />
        <Kpi label="Highest Score" value={customers?.[0] && `${customers[0].anomaly_score} / 100`} loading={cl} />
        <Kpi label="Top Case" value={customers?.[0]?.customer_name} loading={cl} />
      </div>
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <ChartCard title="Flagged Customers by Region">
          <BarChart queryKey="flagged_by_region" parameters={params} xKey="region" yKey="flagged_customers" valueFormatter={count} />
        </ChartCard>
        <ChartCard title="Refunds Under Review by Region">
          <BarChart queryKey="flagged_by_region" parameters={params} xKey="region" yKey="total_refund_value" valueFormatter={currency} />
        </ChartCard>
      </div>
      <Card className="shadow-lg">
        <CardHeader>
          <CardTitle>Top 25 Cases: AI Investigation Briefs</CardTitle>
        </CardHeader>
        <CardContent>
          {cl ? (
            <Skeleton className="h-40 w-full" />
          ) : !customers?.length ? (
            <div className="text-sm text-muted-foreground">No flagged customers for these filters</div>
          ) : (
            <Accordion type="single" collapsible className="w-full">
              {customers.map((c) => (
                <AccordionItem key={c.customer_id} value={c.customer_id}>
                  <AccordionTrigger>
                    <div className="flex flex-1 items-center gap-3 text-left flex-wrap">
                      <Badge variant="destructive">{c.anomaly_score}</Badge>
                      <span className="font-medium">{c.customer_name}</span>
                      {c.customer_email && <span className="text-sm text-muted-foreground">{c.customer_email}</span>}
                      <span className="text-sm text-muted-foreground">
                        {c.region} · {c.segment} · {c.total_returns} returns · {currency(c.total_refund_value)} refunded ·{' '}
                        {percent(c.approval_rate)} approved
                      </span>
                    </div>
                  </AccordionTrigger>
                  <AccordionContent className="space-y-2">
                    <p className="text-xs text-muted-foreground">Rules: {c.rules_violated}</p>
                    <p className="text-sm leading-relaxed">{c.investigation_brief ?? 'Brief not available.'}</p>
                  </AccordionContent>
                </AccordionItem>
              ))}
            </Accordion>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
