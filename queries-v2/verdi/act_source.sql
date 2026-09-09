SELECT TO_JSON_STRING(t) AS r
FROM (
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