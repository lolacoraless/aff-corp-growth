SELECT TO_JSON_STRING(t) AS r
FROM (
WITH monthly_active AS (
  SELECT SIT_SITE_ID, DATE_TRUNC(ORD_CREATED_DT, MONTH) AS month, AFFILIATE_ID
  FROM `meli-bi-data.WHOWNER.BT_AFFI_SALES_ATTRIBUTION_DAILY`
  WHERE ORD_STATUS = 'paid' AND SIT_SITE_ID IN ('MLB','MLM','MLC','MLA')
    AND SIT_SITE_ID = AFFILIATE_SIT_SITE_ID
    AND ORD_CREATED_DT >= DATE '2024-01-01'
    AND ORD_CREATED_DT < DATE_TRUNC(CURRENT_DATE(), MONTH)
    AND ((ORD_CREATED_DT >= DATE '2026-04-01' AND NMV_ENIGMA_TOTAL_AMT_LC > 0)
      OR (ORD_CREATED_DT < DATE '2026-04-01' AND NMV_TD7DCALIB_TOTAL_AMT_LC > 0))
  GROUP BY 1,2,3
),
first_active AS (
  SELECT SIT_SITE_ID, AFFILIATE_ID, MIN(month) AS first_month
  FROM monthly_active GROUP BY 1,2
),
segs AS (
  SELECT c.SIT_SITE_ID, c.month, c.AFFILIATE_ID,
    CASE WHEN f.first_month = c.month THEN 'new'
         WHEN p.AFFILIATE_ID IS NOT NULL THEN 'recurrent'
         ELSE 'recovered' END AS segment
  FROM monthly_active c
  JOIN first_active f USING (SIT_SITE_ID, AFFILIATE_ID)
  LEFT JOIN monthly_active p
    ON c.SIT_SITE_ID = p.SIT_SITE_ID AND c.AFFILIATE_ID = p.AFFILIATE_ID
    AND p.month = DATE_SUB(c.month, INTERVAL 1 MONTH)
),
-- Una fila por segmento + una fila 'total' (todos los activos del mes) como referencia.
joined AS (
  SELECT s.SIT_SITE_ID, s.month, s.segment,
    (nx.AFFILIATE_ID IS NOT NULL) AS retenido
  FROM segs s
  LEFT JOIN monthly_active nx
    ON s.SIT_SITE_ID = nx.SIT_SITE_ID AND s.AFFILIATE_ID = nx.AFFILIATE_ID
    AND nx.month = DATE_ADD(s.month, INTERVAL 1 MONTH)
  -- El ultimo mes cerrado no se puede evaluar: su M+1 todavia no cerro.
  WHERE s.month >= DATE '2025-01-01'
    AND s.month < DATE_SUB(DATE_TRUNC(CURRENT_DATE(), MONTH), INTERVAL 1 MONTH)
)
SELECT SIT_SITE_ID AS sit_site_id, FORMAT_DATE('%Y-%m', month) AS mes, segment,
  COUNT(*) AS cohorte, COUNTIF(retenido) AS retenidos,
  ROUND(SAFE_DIVIDE(COUNTIF(retenido), COUNT(*)) * 100, 1) AS pct_retencion
FROM joined GROUP BY 1,2,3
UNION ALL
SELECT SIT_SITE_ID AS sit_site_id, FORMAT_DATE('%Y-%m', month) AS mes, 'total' AS segment,
  COUNT(*) AS cohorte, COUNTIF(retenido) AS retenidos,
  ROUND(SAFE_DIVIDE(COUNTIF(retenido), COUNT(*)) * 100, 1) AS pct_retencion
FROM joined GROUP BY 1,2
ORDER BY sit_site_id, mes, segment
) t