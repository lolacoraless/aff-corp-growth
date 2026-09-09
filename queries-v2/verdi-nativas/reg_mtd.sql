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