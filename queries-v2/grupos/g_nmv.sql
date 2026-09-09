SELECT 'nmv_monthly' AS _q, TO_JSON_STRING(t) AS r FROM (
WITH ts AS (
  SELECT DATE_TRUNC(DT,MONTH) AS mes, SIT_SITE_ID,
    SUM(NMV_AFF) AS nmv_aff_total, SUM(NMV_TS) AS nmv_ts
  FROM `meli-bi-data.WHOWNER.BT_SC_TOTAL_SITE_AFILIADOS`
  WHERE DT >= DATE '2025-01-01' AND SIT_SITE_ID IN ('MLB','MLM','MLC','MLA') GROUP BY 1,2
),
beh AS (
  SELECT dt AS mes, sit_site_id, active_aff
  FROM `meli-bi-data.SBOX_AFILIADOSCOREDATA.MKT_AFFILIATE_BEHAVIOUR`
  WHERE period = 'MONTH' AND sit_site_id IN ('MLB','MLM','MLC','MLA') AND dt >= DATE '2025-01-01'
),
seg_nmv AS (
  SELECT DATE_TRUNC(CAST(DT AS DATE),MONTH) AS mes, SIT_SITE_ID,
    CASE WHEN SUB_DEFINITION = 'LT' THEN 'lt' ELSE 'nlt' END AS seg,
    SUM(NMV_AFF) AS nmv_aff,
    COUNT(DISTINCT IF(CUS_CUST_ID_AFF > 0, CUS_CUST_ID_AFF, NULL)) AS nlt_active
  FROM `meli-bi-data.WHOWNER.BT_SC_AFFILIATE_BASE`
  WHERE CAST(DT AS DATE) >= DATE '2025-01-01' AND SIT_SITE_ID IN ('MLB','MLM','MLC','MLA')
  GROUP BY 1,2,3
),
kam_excl AS (
  SELECT DISTINCT CAST(cus_cust_id_aff AS INT64) AS affiliate_id, sit_site_id
  FROM `meli-bi-data.SBOX_AFILIADOSCOREDATA.MKT_AFFILIATE_TYPE`
  UNION DISTINCT
  SELECT DISTINCT cus_cust_id_aff, sit_site_id
  FROM `meli-bi-data.SBOX_AFILIADOSCOREDATA.MKT_KA_CATEGORIES`
  WHERE segment = 'Potential KAM'
),
lt_active AS (
  SELECT DATE_TRUNC(s.ORD_CREATED_DT, MONTH) AS mes, s.SIT_SITE_ID,
    COUNT(DISTINCT s.AFFILIATE_ID) AS active_lt
  FROM `meli-bi-data.WHOWNER.BT_AFFI_SALES_ATTRIBUTION_DAILY` s
  LEFT JOIN kam_excl e ON s.AFFILIATE_ID = e.affiliate_id AND s.SIT_SITE_ID = e.sit_site_id
  WHERE e.affiliate_id IS NULL
    AND s.AFFILIATE_ID IS NOT NULL AND s.AFFILIATE_ID != 0
    AND s.ORD_CREATED_DT >= DATE '2025-01-01'
    AND s.SIT_SITE_ID IN ('MLB','MLM','MLC','MLA')
  GROUP BY 1,2
)
SELECT s.mes, s.SIT_SITE_ID, s.seg, s.nmv_aff, t.nmv_ts,
  SAFE_DIVIDE(s.nmv_aff,t.nmv_ts) AS share_ts,
  CASE WHEN s.seg = 'lt' THEN la.active_lt ELSE s.nlt_active END AS active_aff,
  CASE WHEN s.seg = 'lt' THEN SAFE_DIVIDE(s.nmv_aff, la.active_lt)
       ELSE SAFE_DIVIDE(s.nmv_aff, s.nlt_active) END AS npa
FROM seg_nmv s
JOIN ts t USING(mes, SIT_SITE_ID)
LEFT JOIN lt_active la ON s.mes = la.mes AND s.SIT_SITE_ID = la.SIT_SITE_ID AND s.seg = 'lt'
UNION ALL
SELECT t.mes, t.SIT_SITE_ID, 'all' AS seg, t.nmv_aff_total AS nmv_aff, t.nmv_ts,
  SAFE_DIVIDE(t.nmv_aff_total,t.nmv_ts) AS share_ts,
  b.active_aff, SAFE_DIVIDE(t.nmv_aff_total,b.active_aff) AS npa
FROM ts t JOIN beh b USING(mes,SIT_SITE_ID)
ORDER BY mes, SIT_SITE_ID, seg
) t
UNION ALL
SELECT 'nmv_weekly' AS _q, TO_JSON_STRING(t) AS r FROM (
WITH ts AS (
  SELECT EXTRACT(YEAR FROM DT) AS yr, EXTRACT(ISOWEEK FROM DT) AS wk,
    SIT_SITE_ID, SUM(NMV_AFF) AS nmv_aff_total, SUM(NMV_TS) AS nmv_ts
  FROM `meli-bi-data.WHOWNER.BT_SC_TOTAL_SITE_AFILIADOS`
  WHERE DT >= DATE_SUB(CURRENT_DATE('America/Argentina/Buenos_Aires'), INTERVAL MOD(EXTRACT(DAYOFWEEK FROM CURRENT_DATE('America/Argentina/Buenos_Aires')) + 5, 7) + 84 DAY) AND DT < DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH)
    AND SIT_SITE_ID IN ('MLB','MLM','MLC','MLA') GROUP BY 1,2,3
),
beh AS (
  SELECT EXTRACT(YEAR FROM dt) AS yr, EXTRACT(ISOWEEK FROM dt) AS wk,
    sit_site_id, active_aff
  FROM `meli-bi-data.SBOX_AFILIADOSCOREDATA.MKT_AFFILIATE_BEHAVIOUR`
  WHERE period = 'WEEK' AND sit_site_id IN ('MLB','MLM','MLC','MLA') AND dt >= DATE_SUB(CURRENT_DATE('America/Argentina/Buenos_Aires'), INTERVAL MOD(EXTRACT(DAYOFWEEK FROM CURRENT_DATE('America/Argentina/Buenos_Aires')) + 5, 7) + 84 DAY)
)
SELECT t.yr, t.wk, t.SIT_SITE_ID, 'all' AS seg,
  t.nmv_aff_total AS nmv_aff, t.nmv_ts,
  SAFE_DIVIDE(t.nmv_aff_total,t.nmv_ts) AS share_ts,
  b.active_aff, SAFE_DIVIDE(t.nmv_aff_total,b.active_aff) AS npa
FROM ts t LEFT JOIN beh b USING(yr,wk,SIT_SITE_ID)
ORDER BY yr, wk, SIT_SITE_ID
) t
UNION ALL
SELECT 'nmv_mtd' AS _q, TO_JSON_STRING(t) AS r FROM (
WITH total AS (
  SELECT SIT_SITE_ID,
    SUM(CASE WHEN DT BETWEEN DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH) AND DATE_SUB(CURRENT_DATE('America/Argentina/Buenos_Aires'), INTERVAL 1 DAY)      THEN NMV_AFF ELSE 0 END) AS nmv_curr,
    SUM(CASE WHEN DT BETWEEN DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH) AND DATE_SUB(CURRENT_DATE('America/Argentina/Buenos_Aires'), INTERVAL 1 DAY)      THEN NMV_TS  ELSE 0 END) AS ts_curr,
    SUM(CASE WHEN DT BETWEEN DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH), INTERVAL 1 MONTH) AND DATE_ADD(DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH), INTERVAL 1 MONTH), INTERVAL GREATEST(1, LEAST(EXTRACT(DAY FROM CURRENT_DATE('America/Argentina/Buenos_Aires')) - 1, EXTRACT(DAY FROM LAST_DAY(DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH), INTERVAL 1 MONTH))))) - 1 DAY) THEN NMV_AFF ELSE 0 END) AS nmv_prev,
    SUM(CASE WHEN DT BETWEEN DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH), INTERVAL 1 MONTH) AND DATE_ADD(DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH), INTERVAL 1 MONTH), INTERVAL GREATEST(1, LEAST(EXTRACT(DAY FROM CURRENT_DATE('America/Argentina/Buenos_Aires')) - 1, EXTRACT(DAY FROM LAST_DAY(DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH), INTERVAL 1 MONTH))))) - 1 DAY) THEN NMV_TS  ELSE 0 END) AS ts_prev
  FROM `meli-bi-data.WHOWNER.BT_SC_TOTAL_SITE_AFILIADOS`
  WHERE DT >= DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH), INTERVAL 1 MONTH) AND SIT_SITE_ID IN ('MLB','MLM','MLC','MLA') GROUP BY 1
),
lt_nmv AS (
  SELECT SIT_SITE_ID,
    SUM(CASE WHEN CAST(DT AS DATE) BETWEEN DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH) AND DATE_SUB(CURRENT_DATE('America/Argentina/Buenos_Aires'), INTERVAL 1 DAY)      THEN NMV_AFF ELSE 0 END) AS lt_nmv_curr,
    SUM(CASE WHEN CAST(DT AS DATE) BETWEEN DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH), INTERVAL 1 MONTH) AND DATE_ADD(DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH), INTERVAL 1 MONTH), INTERVAL GREATEST(1, LEAST(EXTRACT(DAY FROM CURRENT_DATE('America/Argentina/Buenos_Aires')) - 1, EXTRACT(DAY FROM LAST_DAY(DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH), INTERVAL 1 MONTH))))) - 1 DAY) THEN NMV_AFF ELSE 0 END) AS lt_nmv_prev
  FROM `meli-bi-data.WHOWNER.BT_SC_AFFILIATE_BASE`
  WHERE CAST(DT AS DATE) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH), INTERVAL 1 MONTH)
    AND SIT_SITE_ID IN ('MLB','MLM','MLC','MLA') AND SUB_DEFINITION = 'LT' GROUP BY 1
),
kam_excl AS (
  SELECT DISTINCT CAST(cus_cust_id_aff AS INT64) AS affiliate_id, sit_site_id
  FROM `meli-bi-data.SBOX_AFILIADOSCOREDATA.MKT_AFFILIATE_TYPE`
  UNION DISTINCT
  SELECT DISTINCT cus_cust_id_aff, sit_site_id
  FROM `meli-bi-data.SBOX_AFILIADOSCOREDATA.MKT_KA_CATEGORIES`
  WHERE segment = 'Potential KAM'
),
lt_active AS (
  SELECT s.SIT_SITE_ID,
    COUNT(DISTINCT CASE WHEN s.ORD_CREATED_DT BETWEEN DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH) AND DATE_SUB(CURRENT_DATE('America/Argentina/Buenos_Aires'), INTERVAL 1 DAY)      THEN s.AFFILIATE_ID END) AS lt_active_curr,
    COUNT(DISTINCT CASE WHEN s.ORD_CREATED_DT BETWEEN DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH), INTERVAL 1 MONTH) AND DATE_ADD(DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH), INTERVAL 1 MONTH), INTERVAL GREATEST(1, LEAST(EXTRACT(DAY FROM CURRENT_DATE('America/Argentina/Buenos_Aires')) - 1, EXTRACT(DAY FROM LAST_DAY(DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH), INTERVAL 1 MONTH))))) - 1 DAY) THEN s.AFFILIATE_ID END) AS lt_active_prev
  FROM `meli-bi-data.WHOWNER.BT_AFFI_SALES_ATTRIBUTION_DAILY` s
  LEFT JOIN kam_excl e ON s.AFFILIATE_ID = e.affiliate_id AND s.SIT_SITE_ID = e.sit_site_id
  WHERE e.affiliate_id IS NULL
    AND s.AFFILIATE_ID IS NOT NULL AND s.AFFILIATE_ID != 0
    AND s.ORD_CREATED_DT >= DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH), INTERVAL 1 MONTH)
    AND s.SIT_SITE_ID IN ('MLB','MLM','MLC','MLA')
  GROUP BY 1
)
SELECT t.SIT_SITE_ID, t.nmv_curr, t.ts_curr, t.nmv_prev, t.ts_prev,
  n.lt_nmv_curr, n.lt_nmv_prev, a.lt_active_curr, a.lt_active_prev
FROM total t
LEFT JOIN lt_nmv n USING(SIT_SITE_ID)
LEFT JOIN lt_active a USING(SIT_SITE_ID)
) t
UNION ALL
SELECT 'nmv_pacing' AS _q, TO_JSON_STRING(t) AS r FROM (
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
) t
UNION ALL
SELECT 'nmv_lt_by_status' AS _q, TO_JSON_STRING(t) AS r FROM (
WITH kam_excl AS (
  SELECT DISTINCT CAST(cus_cust_id_aff AS INT64) AS affiliate_id, sit_site_id
  FROM `meli-bi-data.SBOX_AFILIADOSCOREDATA.MKT_AFFILIATE_TYPE`
  UNION DISTINCT
  SELECT DISTINCT cus_cust_id_aff, sit_site_id
  FROM `meli-bi-data.SBOX_AFILIADOSCOREDATA.MKT_KA_CATEGORIES`
  WHERE segment = 'Potential KAM'
),
monthly_sales AS (
  SELECT s.SIT_SITE_ID, s.AFFILIATE_ID, DATE_TRUNC(s.ORD_CREATED_DT, MONTH) AS mes,
    SUM(CASE WHEN s.ORD_CREATED_DT >= DATE '2026-04-01' THEN s.NMV_ENIGMA_TOTAL_AMT_LC
             ELSE s.NMV_TD7DCALIB_TOTAL_AMT_LC END) AS nmv_aff
  FROM `meli-bi-data.WHOWNER.BT_AFFI_SALES_ATTRIBUTION_DAILY` s
  LEFT JOIN kam_excl e ON s.AFFILIATE_ID = e.affiliate_id AND s.SIT_SITE_ID = e.sit_site_id
  WHERE e.affiliate_id IS NULL
    AND s.AFFILIATE_ID IS NOT NULL AND s.AFFILIATE_ID != 0
    AND s.ORD_STATUS = 'paid' AND s.SIT_SITE_ID = s.AFFILIATE_SIT_SITE_ID
    AND s.ORD_CREATED_DT >= DATE '2025-01-01'
    AND s.SIT_SITE_ID IN ('MLB','MLM','MLC','MLA')
    AND ((s.ORD_CREATED_DT >= DATE '2026-04-01' AND s.NMV_ENIGMA_TOTAL_AMT_LC > 0)
      OR (s.ORD_CREATED_DT < DATE '2026-04-01' AND s.NMV_TD7DCALIB_TOTAL_AMT_LC > 0))
  GROUP BY 1,2,3
),
first_sale AS (
  SELECT SIT_SITE_ID, AFFILIATE_ID, MIN(mes) AS first_month
  FROM monthly_sales GROUP BY 1,2
),
segments AS (
  SELECT c.SIT_SITE_ID, c.AFFILIATE_ID, c.mes, c.nmv_aff,
    CASE WHEN f.first_month = c.mes THEN 'new'
         WHEN p.AFFILIATE_ID IS NULL THEN 'recovered'
         ELSE 'recurrent' END AS segment
  FROM monthly_sales c
  JOIN first_sale f USING (SIT_SITE_ID, AFFILIATE_ID)
  LEFT JOIN monthly_sales p
    ON c.SIT_SITE_ID = p.SIT_SITE_ID AND c.AFFILIATE_ID = p.AFFILIATE_ID
    AND p.mes = DATE_SUB(c.mes, INTERVAL 1 MONTH)
)
SELECT mes, SIT_SITE_ID, segment,
  COUNT(DISTINCT AFFILIATE_ID) AS active_aff,
  SUM(nmv_aff) AS nmv_aff,
  SAFE_DIVIDE(SUM(nmv_aff), COUNT(DISTINCT AFFILIATE_ID)) AS npa
FROM segments
GROUP BY 1,2,3
ORDER BY mes, SIT_SITE_ID, segment
) t