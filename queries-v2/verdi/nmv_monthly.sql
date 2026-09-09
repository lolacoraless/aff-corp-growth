SELECT TO_JSON_STRING(t) AS r
FROM (
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