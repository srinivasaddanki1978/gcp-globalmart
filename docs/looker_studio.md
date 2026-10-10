# Looker Studio report: GlobalMart Intelligence

4 pages, each chart reading one `gold.rpt_*` view (dbt, `models/reporting/`). Looker Studio
has no API for building pages, so the report is assembled in the UI. The link below creates it
with all 9 BigQuery data sources already attached.

## 1. Create the report

Sign in as the account that owns `globalmart-gcp-lab`, then open:

[Create "GlobalMart Intelligence" with the 9 data sources](https://lookerstudio.google.com/reporting/create?r.reportName=GlobalMart+Intelligence&c.mode=edit&ds.ds0.connector=bigQuery&ds.ds0.type=TABLE&ds.ds0.projectId=globalmart-gcp-lab&ds.ds0.datasetId=gold&ds.ds0.tableId=rpt_revenue&ds.ds0.datasourceName=rpt_revenue&ds.ds1.connector=bigQuery&ds.ds1.type=TABLE&ds.ds1.projectId=globalmart-gcp-lab&ds.ds1.datasetId=gold&ds.ds1.tableId=rpt_segment&ds.ds1.datasourceName=rpt_segment&ds.ds2.connector=bigQuery&ds.ds2.type=TABLE&ds.ds2.projectId=globalmart-gcp-lab&ds.ds2.datasetId=gold&ds.ds2.tableId=rpt_vendor_returns&ds.ds2.datasourceName=rpt_vendor_returns&ds.ds3.connector=bigQuery&ds.ds3.type=TABLE&ds.ds3.projectId=globalmart-gcp-lab&ds.ds3.datasetId=gold&ds.ds3.tableId=rpt_return_reasons&ds.ds3.datasourceName=rpt_return_reasons&ds.ds4.connector=bigQuery&ds.ds4.type=TABLE&ds.ds4.projectId=globalmart-gcp-lab&ds.ds4.datasetId=gold&ds.ds4.tableId=rpt_flagged&ds.ds4.datasourceName=rpt_flagged&ds.ds5.connector=bigQuery&ds.ds5.type=TABLE&ds.ds5.projectId=globalmart-gcp-lab&ds.ds5.datasetId=gold&ds.ds5.tableId=rpt_slow_moving&ds.ds5.datasourceName=rpt_slow_moving&ds.ds6.connector=bigQuery&ds.ds6.type=TABLE&ds.ds6.projectId=globalmart-gcp-lab&ds.ds6.datasetId=gold&ds.ds6.tableId=rpt_return_cost&ds.ds6.datasourceName=rpt_return_cost&ds.ds7.connector=bigQuery&ds.ds7.type=TABLE&ds.ds7.projectId=globalmart-gcp-lab&ds.ds7.datasetId=gold&ds.ds7.tableId=rpt_dq&ds.ds7.datasourceName=rpt_dq&ds.ds8.connector=bigQuery&ds.ds8.type=TABLE&ds.ds8.projectId=globalmart-gcp-lab&ds.ds8.datasetId=gold&ds.ds8.tableId=rpt_insights&ds.ds8.datasourceName=rpt_insights)

If only some data sources appear, add the rest with **Add data → BigQuery →
globalmart-gcp-lab → gold → rpt_…**.

## 2. Build the pages

Add a **Year** filter control (field `year` from `rpt_revenue`) to page 1 and set it to apply
report-wide (*Make report-level*).

| Page | Chart | Data source | Setup |
|---|---|---|---|
| **Revenue** | Scorecard: Total revenue | rpt_revenue | Metric: SUM(total_sales) |
| | Scorecard: Total profit | rpt_revenue | Metric: SUM(total_profit) |
| | Scorecard: Orders | rpt_revenue | Metric: SUM(order_count) |
| | Bar: Revenue by year | rpt_revenue | Dimension year, metric SUM(total_sales) |
| | Bar: Revenue by region | rpt_revenue | Dimension region, metric SUM(total_sales) |
| | Time series: Monthly revenue trend | rpt_revenue | Dimension month_start (Year Month), metric SUM(total_sales), breakdown region |
| | Bar: Profit margin by segment (%) | rpt_segment | Dimension segment, metric margin_pct (aggregation None/Avg) |
| **Returns & Fraud** | Scorecard: Flagged customers | rpt_flagged | Record Count |
| | Scorecard: Refunds from flagged customers | rpt_flagged | SUM(total_refund_value) |
| | Scorecard: Avg anomaly score | rpt_flagged | AVG(anomaly_score) |
| | Bar: Vendor return rate (%) | rpt_vendor_returns | Dimension vendor_name, metric return_rate_pct (Avg) |
| | Bar: Returns by reason | rpt_return_reasons | Dimension return_reason, metric SUM(return_count), breakdown region |
| | Bar: Flagged customers by region | rpt_flagged | Dimension region, Record Count |
| | Table: Flagged customers (AI briefs) | rpt_flagged | customer_name, region, anomaly_score, rules_violated, investigation_brief; sort anomaly_score desc |
| **Inventory** | Bar: Slow-moving products by region | rpt_slow_moving | Dimension region, metric SUM(slow_moving_products) |
| | Bar: Products sold by region | rpt_slow_moving | Dimension region, metric SUM(product_regions) |
| | Bar: Top 20 products by return cost | rpt_return_cost | Dimension product_name, metric SUM(total_return_cost) |
| | Table: Return-cost detail | rpt_return_cost | All fields |
| **Data Quality & AI** | Scorecard: Rejected records | rpt_dq | SUM(rejected_count) |
| | Bar: Rejections by entity and field | rpt_dq | Dimension entity, breakdown affected_field, metric SUM(rejected_count) |
| | Table: Data quality audit (UC1) | rpt_dq | All fields |
| | Table: AI executive insights | rpt_insights | insight_type, executive_summary |

The year filter only affects charts whose data source has a `year` field (the Revenue page).

## 3. Record it

Share the report as needed, then paste its URL into `dbt/models/exposures.yml`
(`looker_studio_report.url`) so dbt lineage links to it.

## Expected figures (sanity check)

Total revenue $25,989,415.60 (all years) · 109 flagged customers · Seaborne Ltd. highest return
rate 15.04% · 6,027 rejected records.
