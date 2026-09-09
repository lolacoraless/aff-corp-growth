WITH monthly_active AS (
  SELECT SIT_SITE_ID, DATE_TRUNC(ORD_CREATED_DT,MONTH) AS month, AFFILIATE_ID
  FROM `meli-bi-data.WHOWNER.BT_AFFI_SALES_ATTRIBUTION_DAILY`
  WHERE ORD_STATUS='paid' AND SIT_SITE_ID IN ('MLB','MLM','MLC','MLA')
    AND SIT_SITE_ID=AFFILIATE_SIT_SITE_ID AND ORD_CREATED_DT >= DATE '2024-01-01'
    AND ORD_CREATED_DT < DATE_TRUNC(CURRENT_DATE(),MONTH)
    AND ((ORD_CREATED_DT >= DATE '2026-04-01' AND NMV_ENIGMA_TOTAL_AMT_LC>0)
      OR (ORD_CREATED_DT<DATE '2026-04-01' AND NMV_TD7DCALIB_TOTAL_AMT_LC>0))
  GROUP BY 1,2,3
),
first_active AS (SELECT SIT_SITE_ID, AFFILIATE_ID, MIN(month) AS first_month FROM monthly_active GROUP BY 1,2),
flagged AS (
  SELECT ma.SIT_SITE_ID, ma.month, ma.AFFILIATE_ID, fa.first_month=ma.month AS is_new
  FROM monthly_active ma LEFT JOIN first_active fa USING(SIT_SITE_ID,AFFILIATE_ID)
),
metrics AS (
  SELECT prev.SIT_SITE_ID, DATE_ADD(prev.month,INTERVAL 1 MONTH) AS month,
    COUNT(DISTINCT prev.AFFILIATE_ID) AS active_prev,
    COUNT(DISTINCT IF(curr.AFFILIATE_ID IS NULL,prev.AFFILIATE_ID,NULL)) AS churned,
    COUNT(DISTINCT IF(curr.AFFILIATE_ID IS NULL AND prev.is_new=TRUE,prev.AFFILIATE_ID,NULL)) AS churned_new,
    COUNT(DISTINCT IF(curr.AFFILIATE_ID IS NULL AND prev.is_new=FALSE AND m2.AFFILIATE_ID IS NULL,prev.AFFILIATE_ID,NULL)) AS churned_recovered,
    COUNT(DISTINCT IF(curr.AFFILIATE_ID IS NULL AND prev.is_new=FALSE AND m2.AFFILIATE_ID IS NOT NULL,prev.AFFILIATE_ID,NULL)) AS churned_recurrent
  FROM flagged prev
  LEFT JOIN monthly_active curr
    ON prev.AFFILIATE_ID=curr.AFFILIATE_ID AND prev.SIT_SITE_ID=curr.SIT_SITE_ID
    AND curr.month=DATE_ADD(prev.month,INTERVAL 1 MONTH)
  LEFT JOIN monthly_active m2
    ON prev.AFFILIATE_ID=m2.AFFILIATE_ID AND prev.SIT_SITE_ID=m2.SIT_SITE_ID
    AND m2.month=DATE_SUB(prev.month,INTERVAL 1 MONTH)
  GROUP BY 1,2
)
SELECT month, SIT_SITE_ID, active_prev, churned, churned_new, churned_recovered, churned_recurrent,
  ROUND(SAFE_DIVIDE(churned_new,active_prev)*100,2) AS pct_churn_new,
  ROUND(SAFE_DIVIDE(churned_new,churned)*100,1) AS pct_churned_new,
  ROUND(SAFE_DIVIDE(churned_recovered,churned)*100,1) AS pct_churned_recovered,
  ROUND(SAFE_DIVIDE(churned_recurrent,churned)*100,1) AS pct_churned_recurrent
FROM metrics WHERE month >= DATE '2025-01-01' AND month < DATE_TRUNC(CURRENT_DATE(),MONTH) ORDER BY SIT_SITE_ID, month