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