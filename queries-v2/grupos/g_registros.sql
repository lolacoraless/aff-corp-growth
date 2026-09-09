SELECT 'registrations' AS _q, TO_JSON_STRING(t) AS r FROM (
-- registrations v2: mes + semana pre-agregados.
-- El browser agrupaba el diario por (year,month) y por buckets de 7 dias desde W8.
-- Replicamos ESA logica en SQL para que los totales no se muevan.
WITH base AS (
  SELECT DATE(ds) AS ds, site_id, origen, origen_grouped
  FROM `meli-bi-data.SBOX_AFILIADOSCOREDATA.AFFILIATE_REGISTRATION_CHANNEL`
  WHERE DATE(ds) >= DATE '2025-01-01' AND site_id IN ('MLB','MLM','MLC','MLA')
)
SELECT 'month' AS grain,
  FORMAT_DATE('%Y-%m-%d', DATE_TRUNC(ds, MONTH)) AS ds,
  site_id, origen, origen_grouped, COUNT(*) AS users,
  EXTRACT(YEAR FROM ds) AS year, EXTRACT(MONTH FROM ds) AS month
FROM base GROUP BY 1,2,3,4,5,7,8
UNION ALL
-- bucket = piso((ds - W8)/7), mismo calculo que hace el JS
SELECT 'week',
  FORMAT_DATE('%Y-%m-%d', DATE_ADD(DATE_SUB(CURRENT_DATE('America/Argentina/Buenos_Aires'), INTERVAL MOD(EXTRACT(DAYOFWEEK FROM CURRENT_DATE('America/Argentina/Buenos_Aires')) + 5, 7) + 84 DAY),
      INTERVAL DIV(DATE_DIFF(ds, DATE_SUB(CURRENT_DATE('America/Argentina/Buenos_Aires'), INTERVAL MOD(EXTRACT(DAYOFWEEK FROM CURRENT_DATE('America/Argentina/Buenos_Aires')) + 5, 7) + 84 DAY), DAY), 7) * 7 DAY)),
  site_id, origen, origen_grouped, COUNT(*),
  NULL, NULL
FROM base
WHERE DATE_DIFF(ds, DATE_SUB(CURRENT_DATE('America/Argentina/Buenos_Aires'), INTERVAL MOD(EXTRACT(DAYOFWEEK FROM CURRENT_DATE('America/Argentina/Buenos_Aires')) + 5, 7) + 84 DAY), DAY) BETWEEN 0 AND 83
GROUP BY 1,2,3,4,5
ORDER BY 1,3,2,4
) t
UNION ALL
SELECT 'reg_mtd' AS _q, TO_JSON_STRING(t) AS r FROM (
-- D-1 calculado en BQ (UTC-3), independiente del horario de ejecucion del script
-- Periodos simetricos: curr = inicio mes ? D-1 | prev = mismo rango, mes anterior
SELECT site_id, origen, origen_grouped, COUNT(*) AS users, 'curr' AS period
FROM `meli-bi-data.SBOX_AFILIADOSCOREDATA.AFFILIATE_REGISTRATION_CHANNEL`
WHERE DATE(ds) BETWEEN DATE_TRUNC(CURRENT_DATE('-3'), MONTH)
                   AND DATE_SUB(CURRENT_DATE('-3'), INTERVAL 1 DAY)
  AND site_id IN ('MLB','MLM','MLC','MLA')
GROUP BY ALL
UNION ALL
SELECT site_id, origen, origen_grouped, COUNT(*) AS users, 'prev' AS period
FROM `meli-bi-data.SBOX_AFILIADOSCOREDATA.AFFILIATE_REGISTRATION_CHANNEL`
WHERE DATE(ds) BETWEEN DATE_TRUNC(DATE_SUB(CURRENT_DATE('-3'), INTERVAL 1 MONTH), MONTH)
                   AND DATE_SUB(DATE_SUB(CURRENT_DATE('-3'), INTERVAL 1 DAY), INTERVAL 1 MONTH)
  AND site_id IN ('MLB','MLM','MLC','MLA')
GROUP BY ALL
) t
UNION ALL
SELECT 'reg_pacing' AS _q, TO_JSON_STRING(t) AS r FROM (
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
) t