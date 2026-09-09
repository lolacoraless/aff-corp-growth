-- Para M-1 a M-6: NMV acumulado al d?a D del mes vs cierre total
-- Pacing ratio = nmv_at_day / nmv_full ? base para proyecci?n 6 meses
SELECT
  SIT_SITE_ID AS site,
  FORMAT_DATE('%Y-%m-%d', DATE_TRUNC(DT, MONTH)) AS month_start,
  SUM(CASE WHEN EXTRACT(DAY FROM DT) <= (EXTRACT(DAY FROM CURRENT_DATE('America/Argentina/Buenos_Aires')) - 1) THEN NMV_AFF ELSE 0 END) AS nmv_at_day,
  SUM(NMV_AFF) AS nmv_full
FROM `meli-bi-data.WHOWNER.BT_SC_TOTAL_SITE_AFILIADOS`
WHERE SIT_SITE_ID IN ('MLB','MLM','MLC','MLA')
  AND DT >= DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH), INTERVAL 6 MONTH)
  AND DT < DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH)
GROUP BY site, month_start
ORDER BY site, month_start