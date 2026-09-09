SELECT 'behaviour' AS _q, TO_JSON_STRING(t) AS r FROM (
SELECT sit_site_id, dt, period, active_aff,
  retained_aff AS recurrent, recovered_aff AS recovered,
  new_aff, churned_aff AS inactive,
  SAFE_DIVIDE(new_aff + recovered_aff, churned_aff) AS quick_ratio
FROM `meli-bi-data.SBOX_AFILIADOSCOREDATA.MKT_AFFILIATE_BEHAVIOUR`
WHERE period IN ('MONTH','WEEK')
  AND sit_site_id IN ('MLB','MLM','MLC','MLA')
  AND dt >= DATE '2025-01-01'
ORDER BY sit_site_id, period, dt
) t
UNION ALL
SELECT 'beh_mtd' AS _q, TO_JSON_STRING(t) AS r FROM (
WITH all_sales AS (
  SELECT SIT_SITE_ID, AFFILIATE_ID, DATE_TRUNC(ORD_CREATED_DT, MONTH) AS sale_month
  FROM `meli-bi-data.WHOWNER.BT_AFFI_SALES_ATTRIBUTION_DAILY`
  WHERE ORD_STATUS = 'paid' AND SIT_SITE_ID = AFFILIATE_SIT_SITE_ID
    AND SIT_SITE_ID IN ('MLB','MLM','MLC','MLA')
    AND ORD_CREATED_DT >= DATE '2024-01-01'
    AND ((ORD_CREATED_DT >= DATE '2026-04-01' AND NMV_ENIGMA_TOTAL_AMT_LC > 0)
      OR (ORD_CREATED_DT < DATE '2026-04-01' AND NMV_TD7DCALIB_TOTAL_AMT_LC > 0))
  GROUP BY 1,2,3
),
first_sale AS (SELECT SIT_SITE_ID, AFFILIATE_ID, MIN(sale_month) AS first_month FROM all_sales GROUP BY 1,2),
curr_7d AS (
  SELECT DISTINCT SIT_SITE_ID, AFFILIATE_ID
  FROM `meli-bi-data.WHOWNER.BT_AFFI_SALES_ATTRIBUTION_DAILY`
  WHERE ORD_CREATED_DT BETWEEN DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH) AND DATE_SUB(CURRENT_DATE('America/Argentina/Buenos_Aires'), INTERVAL 1 DAY)
    AND ORD_STATUS = 'paid' AND SIT_SITE_ID = AFFILIATE_SIT_SITE_ID
    AND SIT_SITE_ID IN ('MLB','MLM','MLC','MLA') AND NMV_ENIGMA_TOTAL_AMT_LC > 0
),
prev_7d AS (
  SELECT DISTINCT SIT_SITE_ID, AFFILIATE_ID
  FROM `meli-bi-data.WHOWNER.BT_AFFI_SALES_ATTRIBUTION_DAILY`
  WHERE ORD_CREATED_DT BETWEEN DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH), INTERVAL 1 MONTH) AND DATE_ADD(DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH), INTERVAL 1 MONTH), INTERVAL GREATEST(1, LEAST(EXTRACT(DAY FROM CURRENT_DATE('America/Argentina/Buenos_Aires')) - 1, EXTRACT(DAY FROM LAST_DAY(DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH), INTERVAL 1 MONTH))))) - 1 DAY)
    AND ORD_STATUS = 'paid' AND SIT_SITE_ID = AFFILIATE_SIT_SITE_ID
    AND SIT_SITE_ID IN ('MLB','MLM','MLC','MLA') AND NMV_ENIGMA_TOTAL_AMT_LC > 0
),
apr_full AS (SELECT DISTINCT SIT_SITE_ID, AFFILIATE_ID FROM all_sales WHERE sale_month = DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH), INTERVAL 1 MONTH)),
mar_full AS (SELECT DISTINCT SIT_SITE_ID, AFFILIATE_ID FROM all_sales WHERE sale_month = DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH), INTERVAL 2 MONTH)),
curr_flow AS (
  SELECT c.SIT_SITE_ID,
    COUNT(DISTINCT c.AFFILIATE_ID) AS active_aff,
    COUNT(DISTINCT IF(f.first_month = DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH), c.AFFILIATE_ID, NULL)) AS new_aff,
    COUNT(DISTINCT IF(f.first_month < DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH) AND a.AFFILIATE_ID IS NULL, c.AFFILIATE_ID, NULL)) AS recovered_aff
  FROM curr_7d c LEFT JOIN first_sale f USING (SIT_SITE_ID, AFFILIATE_ID)
  LEFT JOIN apr_full a USING (SIT_SITE_ID, AFFILIATE_ID) GROUP BY 1
),
curr_churn AS (
  SELECT a.SIT_SITE_ID, COUNT(DISTINCT IF(c.AFFILIATE_ID IS NULL, a.AFFILIATE_ID, NULL)) AS churned_aff
  FROM apr_full a LEFT JOIN curr_7d c USING (SIT_SITE_ID, AFFILIATE_ID) GROUP BY 1
),
prev_flow AS (
  SELECT p.SIT_SITE_ID,
    COUNT(DISTINCT p.AFFILIATE_ID) AS active_aff,
    COUNT(DISTINCT IF(f.first_month = DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH), INTERVAL 1 MONTH), p.AFFILIATE_ID, NULL)) AS new_aff,
    COUNT(DISTINCT IF(f.first_month < DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH), INTERVAL 1 MONTH) AND m.AFFILIATE_ID IS NULL, p.AFFILIATE_ID, NULL)) AS recovered_aff
  FROM prev_7d p LEFT JOIN first_sale f USING (SIT_SITE_ID, AFFILIATE_ID)
  LEFT JOIN mar_full m USING (SIT_SITE_ID, AFFILIATE_ID) GROUP BY 1
),
prev_churn AS (
  SELECT m.SIT_SITE_ID, COUNT(DISTINCT IF(p.AFFILIATE_ID IS NULL, m.AFFILIATE_ID, NULL)) AS churned_aff
  FROM mar_full m LEFT JOIN prev_7d p USING (SIT_SITE_ID, AFFILIATE_ID) GROUP BY 1
)
SELECT cf.SIT_SITE_ID, 'curr' AS period, cf.active_aff, cf.new_aff, cf.recovered_aff, cc.churned_aff
FROM curr_flow cf JOIN curr_churn cc USING (SIT_SITE_ID)
UNION ALL
SELECT pf.SIT_SITE_ID, 'prev' AS period, pf.active_aff, pf.new_aff, pf.recovered_aff, pc.churned_aff
FROM prev_flow pf JOIN prev_churn pc USING (SIT_SITE_ID)
) t
UNION ALL
SELECT 'beh_pacing' AS _q, TO_JSON_STRING(t) AS r FROM (
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
) t
UNION ALL
SELECT 'qr_rolling' AS _q, TO_JSON_STRING(t) AS r FROM (
WITH all_sales AS (
  SELECT SIT_SITE_ID, AFFILIATE_ID, DATE(ORD_CREATED_DT) AS sale_date
  FROM `meli-bi-data.WHOWNER.BT_AFFI_SALES_ATTRIBUTION_DAILY`
  WHERE ORD_STATUS = 'paid' AND SIT_SITE_ID = AFFILIATE_SIT_SITE_ID
    AND SIT_SITE_ID IN ('MLB','MLM','MLC','MLA')
    AND ORD_CREATED_DT >= DATE_SUB(DATE_SUB(CURRENT_DATE('America/Argentina/Buenos_Aires'), INTERVAL 1 DAY), INTERVAL 61 DAY)
    AND ((ORD_CREATED_DT >= DATE '2026-04-01' AND NMV_ENIGMA_TOTAL_AMT_LC > 0)
      OR (ORD_CREATED_DT < DATE '2026-04-01' AND NMV_TD7DCALIB_TOTAL_AMT_LC > 0))
  GROUP BY 1,2,3
),
first_ever AS (
  SELECT SIT_SITE_ID, AFFILIATE_ID, MIN(DATE(ORD_CREATED_DT)) AS first_date
  FROM `meli-bi-data.WHOWNER.BT_AFFI_SALES_ATTRIBUTION_DAILY`
  WHERE ORD_STATUS = 'paid' AND SIT_SITE_ID = AFFILIATE_SIT_SITE_ID
    AND SIT_SITE_ID IN ('MLB','MLM','MLC','MLA') AND ORD_CREATED_DT >= DATE '2024-01-01'
    AND ((ORD_CREATED_DT >= DATE '2026-04-01' AND NMV_ENIGMA_TOTAL_AMT_LC > 0)
      OR (ORD_CREATED_DT < DATE '2026-04-01' AND NMV_TD7DCALIB_TOTAL_AMT_LC > 0))
  GROUP BY 1,2
),
win_curr AS (SELECT DISTINCT SIT_SITE_ID, AFFILIATE_ID FROM all_sales
  WHERE sale_date BETWEEN DATE_SUB(DATE_SUB(CURRENT_DATE('America/Argentina/Buenos_Aires'), INTERVAL 1 DAY), INTERVAL 29 DAY) AND DATE_SUB(CURRENT_DATE('America/Argentina/Buenos_Aires'), INTERVAL 1 DAY)),
win_prev AS (SELECT DISTINCT SIT_SITE_ID, AFFILIATE_ID FROM all_sales
  WHERE sale_date BETWEEN DATE_SUB(DATE_SUB(CURRENT_DATE('America/Argentina/Buenos_Aires'), INTERVAL 1 DAY), INTERVAL 59 DAY) AND DATE_SUB(DATE_SUB(CURRENT_DATE('America/Argentina/Buenos_Aires'), INTERVAL 1 DAY), INTERVAL 30 DAY)),
affiliates AS (
  SELECT SIT_SITE_ID, AFFILIATE_ID FROM win_curr
  UNION DISTINCT
  SELECT SIT_SITE_ID, AFFILIATE_ID FROM win_prev
)
SELECT a.SIT_SITE_ID,
  FORMAT_DATE('%Y-%m-%d', DATE_SUB(DATE_SUB(CURRENT_DATE('America/Argentina/Buenos_Aires'), INTERVAL 1 DAY), INTERVAL 29 DAY)) AS window_start,
  DATE_SUB(CURRENT_DATE('America/Argentina/Buenos_Aires'), INTERVAL 1 DAY) AS window_end,
  COUNT(DISTINCT IF(c.AFFILIATE_ID IS NOT NULL AND f.first_date >= DATE_SUB(DATE_SUB(CURRENT_DATE('America/Argentina/Buenos_Aires'), INTERVAL 1 DAY), INTERVAL 29 DAY), a.AFFILIATE_ID, NULL)) AS new_30d,
  COUNT(DISTINCT IF(c.AFFILIATE_ID IS NOT NULL AND p.AFFILIATE_ID IS NULL AND (f.first_date IS NULL OR f.first_date < DATE_SUB(DATE_SUB(CURRENT_DATE('America/Argentina/Buenos_Aires'), INTERVAL 1 DAY), INTERVAL 59 DAY)), a.AFFILIATE_ID, NULL)) AS recovered_30d,
  COUNT(DISTINCT IF(p.AFFILIATE_ID IS NOT NULL AND c.AFFILIATE_ID IS NULL, a.AFFILIATE_ID, NULL)) AS churned_30d,
  COUNT(DISTINCT c.AFFILIATE_ID) AS active_30d
FROM affiliates a
LEFT JOIN win_curr c USING (SIT_SITE_ID, AFFILIATE_ID)
LEFT JOIN win_prev p USING (SIT_SITE_ID, AFFILIATE_ID)
LEFT JOIN first_ever f USING (SIT_SITE_ID, AFFILIATE_ID)
GROUP BY 1,2,3
) t