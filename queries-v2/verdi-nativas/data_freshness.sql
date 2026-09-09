-- MAX fecha disponible por tabla fuente ? para el tag "Datos cerrados hasta el X inclusive"
SELECT 'total_site'    AS tbl, FORMAT_DATE('%Y-%m-%d', MAX(DT)) AS max_dt
FROM `meli-bi-data.WHOWNER.BT_SC_TOTAL_SITE_AFILIADOS`
WHERE SIT_SITE_ID IN ('MLB','MLM','MLC','MLA')
UNION ALL
SELECT 'affiliate_base' AS tbl, FORMAT_DATE('%Y-%m-%d', MAX(CAST(DT AS DATE))) AS max_dt
FROM `meli-bi-data.WHOWNER.BT_SC_AFFILIATE_BASE`
WHERE SIT_SITE_ID IN ('MLB','MLM','MLC','MLA')
UNION ALL
SELECT 'attr_daily'    AS tbl, FORMAT_DATE('%Y-%m-%d', MAX(DATE(ORD_CREATED_DT))) AS max_dt
FROM `meli-bi-data.WHOWNER.BT_AFFI_SALES_ATTRIBUTION_DAILY`
WHERE SIT_SITE_ID IN ('MLB','MLM','MLC','MLA')
  AND ORD_STATUS = 'paid' AND SIT_SITE_ID = AFFILIATE_SIT_SITE_ID
UNION ALL
SELECT 'registrations' AS tbl, FORMAT_DATE('%Y-%m-%d', MAX(DATE(ds))) AS max_dt
FROM `meli-bi-data.SBOX_AFILIADOSCOREDATA.AFFILIATE_REGISTRATION_CHANNEL`
WHERE site_id IN ('MLB','MLM','MLC','MLA')
UNION ALL
SELECT 'landing'       AS tbl, FORMAT_DATE('%Y-%m-%d', MAX(DATE(ds))) AS max_dt
FROM `meli-bi-data.SBOX_AFILIADOSCOREDATA.MKT_REGISTRATION_JOURNEY`
WHERE page = 'landing'