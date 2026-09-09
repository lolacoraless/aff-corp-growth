-- registrations v2: mes + semana pre-agregados.
-- El browser agrupaba el diario por (year,month) y por buckets de 7 dias desde W8.
-- Replicamos ESA logica en SQL para que los totales no se muevan.
WITH base AS (
  SELECT DATE(ds) AS ds, site_id, origen, origen_grouped
  FROM `meli-bi-data.SBOX_AFILIADOSCOREDATA.AFFILIATE_REGISTRATION_CHANNEL`
  WHERE DATE(ds) >= '${D.HIST}' AND site_id IN ('MLB','MLM','MLC','MLA')
)
SELECT 'month' AS grain,
  FORMAT_DATE('%Y-%m-%d', DATE_TRUNC(ds, MONTH)) AS ds,
  site_id, origen, origen_grouped, COUNT(*) AS users,
  EXTRACT(YEAR FROM ds) AS year, EXTRACT(MONTH FROM ds) AS month
FROM base GROUP BY 1,2,3,4,5,7,8
UNION ALL
-- bucket = piso((ds - W8)/7), mismo calculo que hace el JS
SELECT 'week',
  FORMAT_DATE('%Y-%m-%d', DATE_ADD(DATE '${D.W8}',
      INTERVAL DIV(DATE_DIFF(ds, DATE '${D.W8}', DAY), 7) * 7 DAY)),
  site_id, origen, origen_grouped, COUNT(*),
  NULL, NULL
FROM base
WHERE DATE_DIFF(ds, DATE '${D.W8}', DAY) BETWEEN 0 AND 83
GROUP BY 1,2,3,4,5
ORDER BY 1,3,2,4
