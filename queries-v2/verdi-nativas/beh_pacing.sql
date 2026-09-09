-- Para M-2 a M-6: cu?ntos afiliados activos/new/rec/ret/chu hab?a al d?a D de ese mes
-- (mismo d?a del mes que ayer) ? usado para calcular pacing hist?rico de proyecciones
WITH all_sales AS (
  SELECT DISTINCT SIT_SITE_ID, AFFILIATE_ID,
    DATE(ORD_CREATED_DT) AS sale_date,
    DATE_TRUNC(ORD_CREATED_DT, MONTH) AS sale_month
  FROM `meli-bi-data.WHOWNER.BT_AFFI_SALES_ATTRIBUTION_DAILY`
  WHERE ORD_STATUS = 'paid'
    AND SIT_SITE_ID = AFFILIATE_SIT_SITE_ID
    AND SIT_SITE_ID IN ('MLB','MLM','MLC','MLA')
    AND ORD_CREATED_DT >= DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH), INTERVAL 7 MONTH)
    AND ORD_CREATED_DT < DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH)
    AND ((ORD_CREATED_DT >= DATE '2026-04-01' AND NMV_ENIGMA_TOTAL_AMT_LC > 0)
      OR (ORD_CREATED_DT < DATE '2026-04-01' AND NMV_TD7DCALIB_TOTAL_AMT_LC > 0))
),
first_ever AS (
  SELECT SIT_SITE_ID, AFFILIATE_ID,
    DATE_TRUNC(MIN(ORD_CREATED_DT), MONTH) AS first_month
  FROM `meli-bi-data.WHOWNER.BT_AFFI_SALES_ATTRIBUTION_DAILY`
  WHERE ORD_STATUS = 'paid'
    AND SIT_SITE_ID = AFFILIATE_SIT_SITE_ID
    AND SIT_SITE_ID IN ('MLB','MLM','MLC','MLA')
    AND ORD_CREATED_DT >= DATE '2024-01-01'
    AND ((ORD_CREATED_DT >= DATE '2026-04-01' AND NMV_ENIGMA_TOTAL_AMT_LC > 0)
      OR (ORD_CREATED_DT < DATE '2026-04-01' AND NMV_TD7DCALIB_TOTAL_AMT_LC > 0))
  GROUP BY 1,2
),
monthly_full AS (
  SELECT SIT_SITE_ID, AFFILIATE_ID, sale_month
  FROM all_sales GROUP BY 1,2,3
),
target_months AS (
  SELECT DATE(DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH), INTERVAL 2 MONTH)) AS m UNION ALL
  SELECT DATE(DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH), INTERVAL 3 MONTH)) UNION ALL
  SELECT DATE(DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH), INTERVAL 4 MONTH)) UNION ALL
  SELECT DATE(DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH), INTERVAL 5 MONTH)) UNION ALL
  SELECT DATE(DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH), INTERVAL 6 MONTH))
),
-- Afiliados activos de d?a 1 al d?a D de cada mes objetivo
at_day AS (
  SELECT s.SIT_SITE_ID, t.m AS month_start, s.AFFILIATE_ID
  FROM all_sales s
  JOIN target_months t ON s.sale_month = t.m
  WHERE EXTRACT(DAY FROM s.sale_date) <= (EXTRACT(DAY FROM CURRENT_DATE('America/Argentina/Buenos_Aires')) - 1)
  GROUP BY 1,2,3
),
-- Afiliados del mes anterior (para clasificaci?n new/rec/ret/chu)
prev_full AS (
  SELECT mf.SIT_SITE_ID, DATE_ADD(mf.sale_month, INTERVAL 1 MONTH) AS target_month, mf.AFFILIATE_ID
  FROM monthly_full mf
  WHERE mf.sale_month IN (
    DATE_SUB(DATE(DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH), INTERVAL 2 MONTH)), INTERVAL 1 MONTH),
    DATE_SUB(DATE(DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH), INTERVAL 3 MONTH)), INTERVAL 1 MONTH),
    DATE_SUB(DATE(DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH), INTERVAL 4 MONTH)), INTERVAL 1 MONTH),
    DATE_SUB(DATE(DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH), INTERVAL 5 MONTH)), INTERVAL 1 MONTH),
    DATE_SUB(DATE(DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH), INTERVAL 6 MONTH)), INTERVAL 1 MONTH)
  )
),
-- Churned al d?a D: en mes anterior completo pero NO en at_day
churned AS (
  SELECT pf.SIT_SITE_ID, pf.target_month AS month_start, pf.AFFILIATE_ID
  FROM prev_full pf
  LEFT JOIN at_day a ON a.SIT_SITE_ID = pf.SIT_SITE_ID
    AND a.month_start = pf.target_month AND a.AFFILIATE_ID = pf.AFFILIATE_ID
  WHERE a.AFFILIATE_ID IS NULL
),
active_counts AS (
  SELECT a.SIT_SITE_ID AS site, a.month_start,
    COUNT(DISTINCT a.AFFILIATE_ID) AS active_at_day,
    COUNT(DISTINCT IF(fe.first_month = a.month_start, a.AFFILIATE_ID, NULL)) AS new_at_day,
    COUNT(DISTINCT IF(fe.first_month < a.month_start AND pf.AFFILIATE_ID IS NULL, a.AFFILIATE_ID, NULL)) AS recovered_at_day,
    COUNT(DISTINCT IF(fe.first_month < a.month_start AND pf.AFFILIATE_ID IS NOT NULL, a.AFFILIATE_ID, NULL)) AS recurrent_at_day
  FROM at_day a
  LEFT JOIN first_ever fe USING (SIT_SITE_ID, AFFILIATE_ID)
  LEFT JOIN prev_full pf ON pf.SIT_SITE_ID = a.SIT_SITE_ID
    AND pf.target_month = a.month_start AND pf.AFFILIATE_ID = a.AFFILIATE_ID
  GROUP BY site, month_start
),
churn_counts AS (
  SELECT SIT_SITE_ID AS site, month_start,
    COUNT(DISTINCT AFFILIATE_ID) AS churned_at_day
  FROM churned GROUP BY 1,2
)
SELECT
  ac.site, FORMAT_DATE('%Y-%m-%d', ac.month_start) AS month_start,
  ac.active_at_day, ac.new_at_day, ac.recovered_at_day, ac.recurrent_at_day,
  COALESCE(cc.churned_at_day, 0) AS churned_at_day
FROM active_counts ac
LEFT JOIN churn_counts cc USING (site, month_start)
ORDER BY site, month_start