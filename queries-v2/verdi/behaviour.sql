SELECT TO_JSON_STRING(t) AS r
FROM (
SELECT sit_site_id, dt, period, active_aff,
  retained_aff AS recurrent, recovered_aff AS recovered,
  new_aff, churned_aff AS inactive,
  SAFE_DIVIDE(new_aff + recovered_aff, churned_aff) AS quick_ratio
FROM `meli-bi-data.SBOX_AFILIADOSCOREDATA.MKT_AFFILIATE_BEHAVIOUR`
WHERE period IN ('MONTH','WEEK')
  AND sit_site_id IN ('MLB','MLM','MLC','MLA')
  AND dt >= DATE '2025-01-01'
ORDER BY sit_site_id, period, dt
) t