-- Para M-1 a M-6: registros acumulados al d?a D del mes vs cierre total
-- Pacing ratio = reg_at_day / reg_full ? base para proyecci?n 6 meses
SELECT
  site_id AS site,
  FORMAT_DATE('%Y-%m-%d', DATE_TRUNC(DATE(ds), MONTH)) AS month_start,
  origen_grouped,
  COUNTIF(EXTRACT(DAY FROM DATE(ds)) <= (EXTRACT(DAY FROM CURRENT_DATE('America/Argentina/Buenos_Aires')) - 1)) AS reg_at_day,
  COUNT(*) AS reg_full
FROM `meli-bi-data.SBOX_AFILIADOSCOREDATA.AFFILIATE_REGISTRATION_CHANNEL`
WHERE DATE(ds) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH), INTERVAL 6 MONTH)
  AND DATE(ds) < DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH)
  AND site_id IN ('MLB','MLM','MLC','MLA')
GROUP BY site, month_start, origen_grouped
ORDER BY site, month_start, origen_grouped