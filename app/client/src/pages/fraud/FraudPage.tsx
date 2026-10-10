import { useAnalyticsQuery, Accordion, AccordionContent, AccordionItem, AccordionTrigger, Badge, BarChart, Card, CardContent, CardHeader, CardTitle, Skeleton, sql } from '../../lib/components';

import { ChartCard, DashboardHeader, Kpi, count, currency, percent } from '../shared/dashboard-ui';

/** uc2_fraud_investigator flags customers scoring >= 40. */
const MIN_ANOMALY = 40;

export function FraudPage() {
  const params = { min_anomaly: sql.number(MIN_ANOMALY) };

  const { data: regions, loading: regionsLoading, error: regionsError } = useAnalyticsQuery(
    'flagged_by_region',
    params,
  );
  const { data: customers, loading: customersLoading, error: customersError } = useAnalyticsQuery(
    'flagged_customers',
    params,
  );

  const flagged = regions?.reduce((sum, r) => sum + Number(r.flagged_customers), 0);
  const atRisk = regions?.reduce((sum, r) => sum + Number(r.total_refund_value), 0);
  const top = customers?.[0];

  const error = regionsError || customersError;
  const loading = regionsLoading || customersLoading;

  return (
    <div className="space-y-6 w-full max-w-7xl mx-auto">
      <DashboardHeader title="Returns Fraud" source="gold.flagged_return_customers" />

      <p className="text-sm text-muted-foreground">
        Customers are scored on their last 12 months of returns against data-driven thresholds; a score
        of {MIN_ANOMALY}+ flags them for review. Briefs are written by the UC2 fraud investigator (LLM).
        Customer names and emails are personal data; access is limited to signed-in users of this app.
      </p>

      {error && (
        <div className="text-destructive bg-destructive/10 p-3 rounded-md">Error: {error}</div>
      )}

      <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
        <Kpi label="Flagged Customers" value={flagged !== undefined ? count(flagged) : undefined} loading={loading} />
        <Kpi label="Refunds Under Review" value={atRisk !== undefined ? currency(atRisk) : undefined} loading={loading} />
        <Kpi label="Highest Score" value={top && `${top.anomaly_score} / 100`} loading={loading} />
        <Kpi label="Top Case" value={top?.customer_name} loading={loading} />
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
          <CardTitle>Top 25 Cases — AI Investigation Briefs</CardTitle>
        </CardHeader>
        <CardContent>
          {customersLoading ? (
            <Skeleton className="h-40 w-full" />
          ) : (
            <Accordion type="single" collapsible className="w-full">
              {customers?.map((c) => (
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
