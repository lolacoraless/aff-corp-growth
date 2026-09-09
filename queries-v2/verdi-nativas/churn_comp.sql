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
churners AS (
  SELECT prev.SIT_SITE_ID,
    DATE_ADD(prev.month,INTERVAL 1 MONTH) AS churn_month,
    DATE_DIFF(prev.month,fa.first_month,MONTH)+1 AS months_active
  FROM monthly_active prev
  LEFT JOIN monthly_active curr
    ON prev.AFFILIATE_ID=curr.AFFILIATE_ID AND prev.SIT_SITE_ID=curr.SIT_SITE_ID
    AND curr.month=DATE_ADD(prev.month,INTERVAL 1 MONTH)
  JOIN first_active fa
    ON fa.SIT_SITE_ID=prev.SIT_SITE_ID AND fa.AFFILIATE_ID=prev.AFFILIATE_ID
  WHERE curr.AFFILIATE_ID IS NULL
)
SELECT churn_month AS month, SIT_SITE_ID, COUNT(*) AS total_churned,
  ROUND(COUNTIF(months_active=1)/COUNT(*)*100,1) AS pct_omw,
  ROUND(COUNTIF(months_active BETWEEN 2 AND 3)/COUNT(*)*100,1) AS pct_early,
  ROUND(COUNTIF(months_active BETWEEN 4 AND 6)/COUNT(*)*100,1) AS pct_mid,
  ROUND(COUNTIF(months_active>=7)/COUNT(*)*100,1) AS pct_established
FROM churners WHERE churn_month >= DATE '2025-01-01' AND churn_month < DATE_TRUNC(CURRENT_DATE(),MONTH) GROUP BY 1,2 ORDER BY 1,2