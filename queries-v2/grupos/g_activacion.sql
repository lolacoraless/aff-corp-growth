SELECT 'act1' AS _q, TO_JSON_STRING(t) AS r FROM (
WITH register AS (
  SELECT USER_ID, SITE_ID, DATE_TRUNC(DATE(DATE_REGISTER),MONTH) AS mes_reg
  FROM `meli-bi-data.SBOX_AFILIADOSCOREDATA.AFFILIATE_AFFILIATE`
  WHERE DATE_REGISTER >= DATE '2025-01-01' AND SITE_ID IN ('MLB','MLM','MLC','MLA')
),
first_sale AS (
  SELECT SIT_SITE_ID, AFFILIATE_ID,
    DATE_TRUNC(MIN(ORD_CREATED_DT),MONTH) AS mes_primera_venta
  FROM `meli-bi-data.WHOWNER.BT_AFFI_SALES_ATTRIBUTION_DAILY`
  WHERE SIT_SITE_ID IN ('MLB','MLM','MLC','MLA') AND ORD_STATUS='paid'
    AND SIT_SITE_ID=AFFILIATE_SIT_SITE_ID AND ORD_CREATED_DT >= DATE '2025-01-01'
    AND ((ORD_CREATED_DT >= DATE '2026-04-01' AND NMV_ENIGMA_TOTAL_AMT_LC>0)
      OR (ORD_CREATED_DT<DATE '2026-04-01' AND NMV_TD7DCALIB_TOTAL_AMT_LC>0))
  GROUP BY 1,2
)
SELECT r.SITE_ID, r.mes_reg,
  COUNT(DISTINCT r.USER_ID) AS total_registros,
  COUNT(DISTINCT IF(f.mes_primera_venta=r.mes_reg, r.USER_ID, NULL)) AS activaron_mismo_mes,
  ROUND(SAFE_DIVIDE(COUNT(DISTINCT IF(f.mes_primera_venta=r.mes_reg,r.USER_ID,NULL)),
    COUNT(DISTINCT r.USER_ID))*100,1) AS pct_activaron
FROM register r
LEFT JOIN first_sale f ON r.USER_ID=f.AFFILIATE_ID AND r.SITE_ID=f.SIT_SITE_ID
GROUP BY 1,2 ORDER BY SITE_ID, mes_reg
) t
UNION ALL
SELECT 'act2' AS _q, TO_JSON_STRING(t) AS r FROM (
WITH register AS (
  SELECT USER_ID, SITE_ID, DATE_TRUNC(DATE(DATE_REGISTER),MONTH) AS mes_reg,
    DATE(TIMESTAMP_SUB(TIMESTAMP(DATE_REGISTER), INTERVAL 4 HOUR)) AS date_reg_adj
  FROM `meli-bi-data.SBOX_AFILIADOSCOREDATA.AFFILIATE_AFFILIATE`
  WHERE DATE_REGISTER >= DATE '2025-01-01' AND SITE_ID IN ('MLB','MLM','MLC','MLA')
),
first_sale AS (
  SELECT SIT_SITE_ID, AFFILIATE_ID, MIN(ORD_CREATED_DT) AS first_sale_dt
  FROM `meli-bi-data.WHOWNER.BT_AFFI_SALES_ATTRIBUTION_DAILY`
  WHERE SIT_SITE_ID IN ('MLB','MLM','MLC','MLA') AND ORD_STATUS='paid'
    AND SIT_SITE_ID=AFFILIATE_SIT_SITE_ID AND ORD_CREATED_DT >= DATE '2025-01-01'
    AND ((ORD_CREATED_DT >= DATE '2026-04-01' AND NMV_ENIGMA_TOTAL_AMT_LC>0)
      OR (ORD_CREATED_DT<DATE '2026-04-01' AND NMV_TD7DCALIB_TOTAL_AMT_LC>0))
  GROUP BY 1,2
),
seg AS (
  SELECT r.SITE_ID, r.mes_reg,
    CASE WHEN f.first_sale_dt IS NULL THEN 'no_act'
         WHEN DATE_DIFF(f.first_sale_dt,r.date_reg_adj,DAY)<=7  THEN 'd7'
         WHEN DATE_DIFF(f.first_sale_dt,r.date_reg_adj,DAY)<=15 THEN 'd15'
         WHEN DATE_DIFF(f.first_sale_dt,r.date_reg_adj,DAY)<=30 THEN 'd30'
         WHEN DATE_DIFF(f.first_sale_dt,r.date_reg_adj,DAY)<=45 THEN 'd45'
         ELSE 'd46p' END AS cohort
  FROM register r
  LEFT JOIN first_sale f ON r.USER_ID=f.AFFILIATE_ID AND r.SITE_ID=f.SIT_SITE_ID
)
SELECT SITE_ID, mes_reg, COUNT(*) AS total,
  ROUND(COUNTIF(cohort='d7') /COUNT(*)*100,1) AS pct_d7,
  ROUND(COUNTIF(cohort='d15')/COUNT(*)*100,1) AS pct_d15,
  ROUND(COUNTIF(cohort='d30')/COUNT(*)*100,1) AS pct_d30,
  ROUND(COUNTIF(cohort='d45')/COUNT(*)*100,1) AS pct_d45,
  ROUND(COUNTIF(cohort='d46p')/COUNT(*)*100,1) AS pct_d46p,
  ROUND(COUNTIF(cohort='no_act')/COUNT(*)*100,1) AS pct_no_act
FROM seg GROUP BY 1,2 ORDER BY SITE_ID, mes_reg
) t
UNION ALL
SELECT 'act_source' AS _q, TO_JSON_STRING(t) AS r FROM (
WITH reg_src AS (
  SELECT
    USER_ID,
    SITE_ID,
    DATE_TRUNC(DATE(ds), MONTH) AS mes_reg,
    CASE
      WHEN LOWER(origen_grouped) LIKE 'pom%'
        OR LOWER(origen_grouped) IN ('paid media','tiktok','facebook','google','instagram','twitter','youtube','paid','x')
      THEN 'pom'
      WHEN LOWER(origen_grouped) LIKE 'direct%'
        OR LOWER(origen_grouped) IN ('app','web')
      THEN 'direct'
      ELSE NULL
    END AS canal
  FROM `meli-bi-data.SBOX_AFILIADOSCOREDATA.AFFILIATE_REGISTRATION_CHANNEL`
  WHERE DATE(ds) >= DATE '2025-01-01'
    AND SITE_ID IN ('MLB','MLM','MLC','MLA')
    AND (
      LOWER(origen_grouped) LIKE 'pom%'
      OR LOWER(origen_grouped) IN ('paid media','tiktok','facebook','google','instagram','twitter','youtube','paid','x')
      OR LOWER(origen_grouped) LIKE 'direct%'
      OR LOWER(origen_grouped) IN ('app','web')
    )
),
first_sale AS (
  SELECT SIT_SITE_ID, AFFILIATE_ID,
    DATE_TRUNC(MIN(ORD_CREATED_DT), MONTH) AS mes_primera_venta
  FROM `meli-bi-data.WHOWNER.BT_AFFI_SALES_ATTRIBUTION_DAILY`
  WHERE SIT_SITE_ID IN ('MLB','MLM','MLC','MLA') AND ORD_STATUS='paid'
    AND SIT_SITE_ID=AFFILIATE_SIT_SITE_ID AND ORD_CREATED_DT >= DATE '2025-01-01'
    AND ((ORD_CREATED_DT >= DATE '2026-04-01' AND NMV_ENIGMA_TOTAL_AMT_LC>0)
      OR (ORD_CREATED_DT < DATE '2026-04-01' AND NMV_TD7DCALIB_TOTAL_AMT_LC>0))
  GROUP BY 1, 2
)
SELECT r.SITE_ID AS site_id, r.mes_reg, r.canal,
  COUNT(DISTINCT r.USER_ID) AS total_registros,
  COUNT(DISTINCT IF(f.mes_primera_venta = r.mes_reg, r.USER_ID, NULL)) AS activaron_mismo_mes,
  ROUND(SAFE_DIVIDE(
    COUNT(DISTINCT IF(f.mes_primera_venta = r.mes_reg, r.USER_ID, NULL)),
    COUNT(DISTINCT r.USER_ID)) * 100, 1) AS pct_activaron
FROM reg_src r
LEFT JOIN first_sale f ON CAST(r.USER_ID AS INT64) = f.AFFILIATE_ID AND r.SITE_ID = f.SIT_SITE_ID
GROUP BY 1, 2, 3 ORDER BY site_id, mes_reg, canal
) t
UNION ALL
SELECT 'act_new_days' AS _q, TO_JSON_STRING(t) AS r FROM (
WITH register AS (
  SELECT USER_ID, SITE_ID,
    DATE(TIMESTAMP_SUB(TIMESTAMP(DATE_REGISTER), INTERVAL 4 HOUR)) AS date_reg_adj
  FROM `meli-bi-data.SBOX_AFILIADOSCOREDATA.AFFILIATE_AFFILIATE`
  WHERE DATE_REGISTER >= DATE '2025-01-01' AND SITE_ID IN ('MLB','MLM','MLC','MLA')
),
first_sale AS (
  SELECT SIT_SITE_ID, AFFILIATE_ID,
    DATE_TRUNC(MIN(ORD_CREATED_DT), MONTH) AS mes_primera_venta,
    MIN(ORD_CREATED_DT) AS first_sale_dt
  FROM `meli-bi-data.WHOWNER.BT_AFFI_SALES_ATTRIBUTION_DAILY`
  WHERE SIT_SITE_ID IN ('MLB','MLM','MLC','MLA') AND ORD_STATUS='paid'
    AND SIT_SITE_ID=AFFILIATE_SIT_SITE_ID AND ORD_CREATED_DT >= DATE '2025-01-01'
    AND ((ORD_CREATED_DT >= DATE '2026-04-01' AND NMV_ENIGMA_TOTAL_AMT_LC>0)
      OR (ORD_CREATED_DT < DATE '2026-04-01' AND NMV_TD7DCALIB_TOTAL_AMT_LC>0))
  GROUP BY 1, 2
)
SELECT r.SITE_ID, f.mes_primera_venta AS mes,
  COUNT(DISTINCT r.USER_ID) AS total_new,
  ROUND(COUNTIF(DATE_DIFF(f.first_sale_dt, r.date_reg_adj, DAY) = 0)     / COUNT(*) * 100, 1) AS pct_d0,
  ROUND(COUNTIF(DATE_DIFF(f.first_sale_dt, r.date_reg_adj, DAY) BETWEEN 1  AND 7)  / COUNT(*) * 100, 1) AS pct_d1_7,
  ROUND(COUNTIF(DATE_DIFF(f.first_sale_dt, r.date_reg_adj, DAY) BETWEEN 8  AND 30) / COUNT(*) * 100, 1) AS pct_d8_30,
  ROUND(COUNTIF(DATE_DIFF(f.first_sale_dt, r.date_reg_adj, DAY) BETWEEN 31 AND 60) / COUNT(*) * 100, 1) AS pct_d31_60,
  ROUND(COUNTIF(DATE_DIFF(f.first_sale_dt, r.date_reg_adj, DAY) > 60)              / COUNT(*) * 100, 1) AS pct_d60p
FROM register r
INNER JOIN first_sale f ON r.USER_ID = f.AFFILIATE_ID AND r.SITE_ID = f.SIT_SITE_ID
GROUP BY 1, 2 ORDER BY SITE_ID, mes
) t