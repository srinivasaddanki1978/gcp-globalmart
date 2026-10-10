import { useAnalyticsQuery, Accordion, AccordionContent, AccordionItem, AccordionTrigger, Badge, Card, CardContent, CardHeader, CardTitle, Skeleton } from '../../lib/appkit';

import { DashboardHeader, count, percent } from '../shared/dashboard-ui';

const NO_PARAMS: Record<string, never> = {};

const INSIGHT_TITLES: Record<string, string> = {
  revenue_performance: 'Revenue Performance',
  vendor_return_rate: 'Vendor Returns',
  slow_moving_inventory: 'Inventory & Return Costs',
};

export function InsightsPage() {
  const { data: insights, loading: insightsLoading, error: insightsError } = useAnalyticsQuery('ai_insights', NO_PARAMS);
  const { data: issues, loading: issuesLoading, error: issuesError } = useAnalyticsQuery('dq_audit', NO_PARAMS);
  const error = insightsError || issuesError;

  return (
    <div className="space-y-6 w-full max-w-7xl mx-auto">
      <DashboardHeader title="AI Insights" source="gold.ai_business_insights + dq_audit_report" />

      {error && (
        <div className="text-destructive bg-destructive/10 p-3 rounded-md">Error: {error}</div>
      )}

      <h2 className="text-lg font-semibold">Executive Summaries</h2>
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {insightsLoading
          ? [0, 1, 2].map((i) => <Skeleton key={i} className="h-56 w-full" />)
          : insights?.map((i) => (
              <Card key={i.insight_type} className="shadow-lg">
                <CardHeader>
                  <CardTitle>{INSIGHT_TITLES[i.insight_type] ?? i.insight_type}</CardTitle>
                  <p className="text-xs text-muted-foreground">Generated {i.generated_at?.slice(0, 16)}</p>
                </CardHeader>
                <CardContent>
                  <p className="text-sm leading-relaxed">{i.executive_summary ?? 'Summary not available.'}</p>
                </CardContent>
              </Card>
            ))}
      </div>

      <h2 className="text-lg font-semibold">Data Quality Issues (Silver layer)</h2>
      <Card className="shadow-lg">
        <CardContent className="pt-6">
          {issuesLoading ? (
            <Skeleton className="h-40 w-full" />
          ) : (
            <Accordion type="single" collapsible className="w-full">
              {issues?.map((q) => (
                <AccordionItem key={`${q.entity}-${q.affected_field}-${q.issue_type}`} value={`${q.entity}-${q.affected_field}`}>
                  <AccordionTrigger>
                    <div className="flex flex-1 items-center gap-3 text-left flex-wrap">
                      <Badge variant="secondary">{q.issue_type}</Badge>
                      <span className="font-medium">
                        {q.entity}.{q.affected_field}
                      </span>
                      <span className="text-sm text-muted-foreground">
                        {count(q.rejected_count)} of {count(q.total_entity_records)} rejected ({percent(q.rejection_rate_pct)})
                      </span>
                    </div>
                  </AccordionTrigger>
                  <AccordionContent>
                    <p className="text-sm leading-relaxed">{q.ai_explanation ?? 'Explanation not available.'}</p>
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
