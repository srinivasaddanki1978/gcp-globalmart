-- @param region STRING
-- @param segment STRING
-- @param vendor STRING
-- Revenue, profit and orders per year with like-for-like YoY growth: each year is compared
-- with the previous year over the months both have data. yoy_pct is NULL when only some of a
-- year's months can be compared (2017 overlaps 2016 in October only), so one month never
-- passes for annual growth. 2026 (Jan-Sep) is compared with Jan-Sep 2025; partial_year flags it.
WITH f AS (
  SELECT * FROM gold.rpt_sales_lines WHERE (@region = 'All' OR region = @region) AND (@segment = 'All' OR segment = @segment) AND (@vendor = 'All' OR vendor_name = @vendor)
),
pm AS (
  SELECT year, month, comparable FROM gold.rpt_period_months WHERE period = 'FY' AND has_data
),
y AS (
  SELECT f.year, SUM(f.sales) AS revenue, SUM(f.profit) AS profit, COUNT(DISTINCT f.order_id) AS orders,
         SUM(IF(pm.comparable, f.sales, 0)) AS revenue_c
  FROM f JOIN pm ON f.year = pm.year AND f.month = pm.month
  GROUP BY f.year
),
prev AS (
  SELECT pm.year, SUM(f.sales) AS revenue_prior
  FROM pm JOIN f ON f.year = pm.year - 1 AND f.month = pm.month
  WHERE pm.comparable
  GROUP BY pm.year
),
months AS (SELECT year, COUNT(*) AS months, COUNTIF(comparable) AS compared FROM pm GROUP BY year),
labels AS (  -- '2026 (Jan–Sep)', '2016 (Oct)' for years with fewer than 12 months of data
  SELECT year,
         IF(COUNT(*) < 12,
            FORMAT('%d (%s)', year, IF(MIN(month) = MAX(month), FORMAT_DATE('%b', DATE(2000, MIN(month), 1)),
                   CONCAT(FORMAT_DATE('%b', DATE(2000, MIN(month), 1)), '–', FORMAT_DATE('%b', DATE(2000, MAX(month), 1))))),
            CAST(year AS STRING)) AS year_label
  FROM gold.rpt_period_months WHERE period = 'FY' AND has_data GROUP BY year
)
SELECT
  l.year_label AS year,
  ROUND(y.revenue, 2) AS total_sales,
  ROUND(y.profit, 2) AS total_profit,
  y.orders AS order_count,
  ROUND(100 * SAFE_DIVIDE(y.profit, y.revenue), 2) AS margin_pct,
  IF(m.compared = m.months, ROUND(100 * SAFE_DIVIDE(y.revenue_c - prev.revenue_prior, prev.revenue_prior), 1), NULL) AS yoy_pct,
  m.months < 12 AS partial_year
FROM y
JOIN months AS m USING (year)
JOIN labels AS l USING (year)
LEFT JOIN prev USING (year)
ORDER BY y.year
