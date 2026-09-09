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