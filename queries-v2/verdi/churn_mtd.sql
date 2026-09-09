SELECT TO_JSON_STRING(t) AS r
FROM (
WITH window_sales AS (
  SELECT SIT_SITE_ID, AFFILIATE_ID,
    MAX(CASE WHEN DATE(ORD_CREATED_DT) BETWEEN DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH) AND DATE_SUB(CURRENT_DATE('America/Argentina/Buenos_Aires'), INTERVAL 1 DAY) THEN 1 ELSE 0 END) AS in_curr,
    MAX(CASE WHEN DATE(ORD_CREATED_DT) BETWEEN DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH), INTERVAL 1 MONTH) AND DATE_ADD(DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH), INTERVAL 1 MONTH), INTERVAL GREATEST(1, LEAST(EXTRACT(DAY FROM CURRENT_DATE('America/Argentina/Buenos_Aires')) - 1, EXTRACT(DAY FROM LAST_DAY(DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH), INTERVAL 1 MONTH))))) - 1 DAY) THEN 1 ELSE 0 END) AS in_prev,
    MAX(CASE WHEN DATE_TRUNC(ORD_CREATED_DT,MONTH)=DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH), INTERVAL 1 MONTH) THEN 1 ELSE 0 END) AS in_apr_full,
    MAX(CASE WHEN DATE_TRUNC(ORD_CREATED_DT,MONTH)=DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH), INTERVAL 2 MONTH) THEN 1 ELSE 0 END) AS in_mar_full,
    MIN(DATE_TRUNC(ORD_CREATED_DT,MONTH)) AS first_month,
    COUNT(DISTINCT CASE WHEN DATE_TRUNC(ORD_CREATED_DT,MONTH)<=DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH), INTERVAL 1 MONTH)
      THEN DATE_TRUNC(ORD_CREATED_DT,MONTH) END) AS months_hist
  FROM `meli-bi-data.WHOWNER.BT_AFFI_SALES_ATTRIBUTION_DAILY`
  WHERE ORD_STATUS='paid' AND SIT_SITE_ID=AFFILIATE_SIT_SITE_ID
    AND SIT_SITE_ID IN ('MLB','MLM','MLC','MLA') AND ORD_CREATED_DT >= DATE '2024-01-01'
    AND ((ORD_CREATED_DT >= DATE '2026-04-01' AND NMV_ENIGMA_TOTAL_AMT_LC>0)
      OR (ORD_CREATED_DT<DATE '2026-04-01' AND NMV_TD7DCALIB_TOTAL_AMT_LC>0))
  GROUP BY 1,2
)
SELECT SIT_SITE_ID,
  COUNT(DISTINCT IF(in_curr=0 AND first_month=DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH), INTERVAL 1 MONTH) AND in_apr_full=1,AFFILIATE_ID,NULL)) AS curr_churned_new,
  COUNT(DISTINCT IF(in_apr_full=1,AFFILIATE_ID,NULL)) AS apr_active_base,
  ROUND(SAFE_DIVIDE(
    COUNT(DISTINCT IF(in_curr=0 AND first_month=DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH), INTERVAL 1 MONTH) AND in_apr_full=1,AFFILIATE_ID,NULL)),
    COUNT(DISTINCT IF(in_apr_full=1,AFFILIATE_ID,NULL)))*100,2) AS pct_churn_new_curr,
  COUNT(DISTINCT IF(in_prev=0 AND first_month=DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH), INTERVAL 2 MONTH) AND in_mar_full=1,AFFILIATE_ID,NULL)) AS prev_churned_new,
  COUNT(DISTINCT IF(in_mar_full=1,AFFILIATE_ID,NULL)) AS mar_active_base,
  ROUND(SAFE_DIVIDE(
    COUNT(DISTINCT IF(in_prev=0 AND first_month=DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH), INTERVAL 2 MONTH) AND in_mar_full=1,AFFILIATE_ID,NULL)),
    COUNT(DISTINCT IF(in_mar_full=1,AFFILIATE_ID,NULL)))*100,2) AS pct_churn_new_prev,
  ROUND(SAFE_DIVIDE(COUNTIF(in_apr_full=1 AND in_curr=0 AND months_hist=1),
    COUNTIF(in_apr_full=1 AND in_curr=0))*100,1) AS curr_pct_omw,
  ROUND(SAFE_DIVIDE(COUNTIF(in_apr_full=1 AND in_curr=0 AND months_hist BETWEEN 2 AND 3),
    COUNTIF(in_apr_full=1 AND in_curr=0))*100,1) AS curr_pct_early,
  ROUND(SAFE_DIVIDE(COUNTIF(in_apr_full=1 AND in_curr=0 AND months_hist BETWEEN 4 AND 6),
    COUNTIF(in_apr_full=1 AND in_curr=0))*100,1) AS curr_pct_mid,
  ROUND(SAFE_DIVIDE(COUNTIF(in_apr_full=1 AND in_curr=0 AND months_hist>=7),
    COUNTIF(in_apr_full=1 AND in_curr=0))*100,1) AS curr_pct_established,
  ROUND(SAFE_DIVIDE(COUNTIF(in_mar_full=1 AND in_prev=0 AND months_hist=1),
    COUNTIF(in_mar_full=1 AND in_prev=0))*100,1) AS prev_pct_omw,
  ROUND(SAFE_DIVIDE(COUNTIF(in_mar_full=1 AND in_prev=0 AND months_hist BETWEEN 2 AND 3),
    COUNTIF(in_mar_full=1 AND in_prev=0))*100,1) AS prev_pct_early,
  ROUND(SAFE_DIVIDE(COUNTIF(in_mar_full=1 AND in_prev=0 AND months_hist BETWEEN 4 AND 6),
    COUNTIF(in_mar_full=1 AND in_prev=0))*100,1) AS prev_pct_mid,
  ROUND(SAFE_DIVIDE(COUNTIF(in_mar_full=1 AND in_prev=0 AND months_hist>=7),
    COUNTIF(in_mar_full=1 AND in_prev=0))*100,1) AS prev_pct_established
FROM window_sales GROUP BY 1
) t