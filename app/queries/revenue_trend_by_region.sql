-- @param segment STRING
-- @param vendor STRING
-- Yearly revenue per region, one column per region for a multi-series chart.
WITH labels AS (  -- '2026 (Jan–Sep)', '2016 (Oct)' for years with fewer than 12 months of data
  SELECT year,
         IF(COUNT(*) < 12,
            FORMAT('%d (%s)', year, IF(MIN(month) = MAX(month), FORMAT_DATE('%b', DATE(2000, MIN(month), 1)),
                   CONCAT(FORMAT_DATE('%b', DATE(2000, MIN(month), 1)), '–', FORMAT_DATE('%b', DATE(2000, MAX(month), 1))))),
            CAST(year AS STRING)) AS year_label
  FROM gold.rpt_period_months WHERE period = 'FY' AND has_data GROUP BY year
)
SELECT
  l.year_label AS year,
  ROUND(SUM(IF(region = 'East', sales, 0)), 2) AS east,
  ROUND(SUM(IF(region = 'West', sales, 0)), 2) AS west,
  ROUND(SUM(IF(region = 'South', sales, 0)), 2) AS south,
  ROUND(SUM(IF(region = 'Central', sales, 0)), 2) AS central,
  ROUND(SUM(IF(region = 'North', sales, 0)), 2) AS north
FROM gold.rpt_sales_lines AS s
JOIN labels AS l ON s.year = l.year
WHERE (@segment = 'All' OR segment = @segment) AND (@vendor = 'All' OR vendor_name = @vendor)
GROUP BY s.year, l.year_label
ORDER BY s.year
