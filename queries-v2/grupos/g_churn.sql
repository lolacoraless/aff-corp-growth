SELECT 'churn' AS _q, TO_JSON_STRING(t) AS r FROM (
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
) t
UNION ALL
SELECT 'churn_comp' AS _q, TO_JSON_STRING(t) AS r FROM (
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
) t
UNION ALL
SELECT 'churn_mtd' AS _q, TO_JSON_STRING(t) AS r FROM (
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
UNION ALL
SELECT 'earnings_buckets' AS _q, TO_JSON_STRING(t) AS r FROM (
WITH kam_excl AS (
  SELECT DISTINCT CAST(cus_cust_id_aff AS INT64) AS affiliate_id, sit_site_id
  FROM `meli-bi-data.SBOX_AFILIADOSCOREDATA.MKT_AFFILIATE_TYPE`
  UNION DISTINCT
  SELECT DISTINCT AFFILIATE_ID, SIT_SITE_ID
  FROM `meli-bi-data.WHOWNER.LK_AFFI_AFFILIATES_KA`
  WHERE AFFILIATE_SEGMENT = 'Potential KAM' AND END_DT IS NULL
),
monthly_active AS (
  SELECT s.SIT_SITE_ID, DATE_TRUNC(s.ORD_CREATED_DT, MONTH) AS month, s.AFFILIATE_ID
  FROM `meli-bi-data.WHOWNER.BT_AFFI_SALES_ATTRIBUTION_DAILY` s
  LEFT JOIN kam_excl e ON s.AFFILIATE_ID = e.affiliate_id AND s.SIT_SITE_ID = e.sit_site_id
  WHERE e.affiliate_id IS NULL
    AND s.ORD_STATUS = 'paid' AND s.SIT_SITE_ID IN ('MLB','MLM','MLC','MLA')
    AND s.SIT_SITE_ID = s.AFFILIATE_SIT_SITE_ID
    AND s.ORD_CREATED_DT >= DATE '2024-01-01'
    AND s.ORD_CREATED_DT < DATE_TRUNC(CURRENT_DATE(), MONTH)
    AND ((s.ORD_CREATED_DT >= DATE '2026-04-01' AND s.NMV_ENIGMA_TOTAL_AMT_LC > 0)
      OR (s.ORD_CREATED_DT < DATE '2026-04-01' AND s.NMV_TD7DCALIB_TOTAL_AMT_LC > 0))
  GROUP BY 1,2,3
),
churners AS (
  SELECT prev.SIT_SITE_ID, prev.AFFILIATE_ID,
    prev.month AS last_active_month,
    DATE_ADD(prev.month, INTERVAL 1 MONTH) AS churn_month
  FROM monthly_active prev
  LEFT JOIN monthly_active curr
    ON prev.AFFILIATE_ID = curr.AFFILIATE_ID AND prev.SIT_SITE_ID = curr.SIT_SITE_ID
    AND curr.month = DATE_ADD(prev.month, INTERVAL 1 MONTH)
  WHERE curr.AFFILIATE_ID IS NULL
    AND DATE_ADD(prev.month, INTERVAL 1 MONTH) >= DATE '2025-01-01'
    AND DATE_ADD(prev.month, INTERVAL 1 MONTH) < DATE_TRUNC(CURRENT_DATE(), MONTH)
),
monthly_earnings AS (
  SELECT SIT_SITE_ID, AFFILIATE_ID, DATE_TRUNC(ORD_CREATED_DT, MONTH) AS month,
    SUM(EARNINGS_TOTAL_AMT_LC) AS earnings
  FROM `meli-bi-data.WHOWNER.BT_AFFI_SALES_ATTRIBUTION_DAILY`
  WHERE SIT_SITE_ID IN ('MLB','MLM','MLC','MLA')
    AND SIT_SITE_ID = AFFILIATE_SIT_SITE_ID
    AND IS_PAYABLE_FLAG = TRUE
  GROUP BY 1,2,3
),
churner_earnings AS (
  SELECT c.SIT_SITE_ID, c.churn_month, c.AFFILIATE_ID,
    COALESCE(SUM(IF(me.month <= c.last_active_month, me.earnings, 0)), 0) AS earnings_lt
  FROM churners c
  LEFT JOIN monthly_earnings me
    ON me.SIT_SITE_ID = c.SIT_SITE_ID AND me.AFFILIATE_ID = c.AFFILIATE_ID
  GROUP BY 1,2,3
),
bucketed AS (
  SELECT SIT_SITE_ID, churn_month,
    CASE
      WHEN SIT_SITE_ID = 'MLA' THEN CASE
        WHEN earnings_lt <= 0     THEN 0
        WHEN earnings_lt < 30000  THEN 1
        WHEN earnings_lt < 50000  THEN 2
        WHEN earnings_lt < 100000 THEN 3
        ELSE 4 END
      WHEN SIT_SITE_ID = 'MLM' THEN CASE
        WHEN earnings_lt <= 0   THEN 0
        WHEN earnings_lt < 100  THEN 1
        WHEN earnings_lt < 300  THEN 2
        WHEN earnings_lt < 600  THEN 3
        ELSE 4 END
      WHEN SIT_SITE_ID = 'MLC' THEN CASE
        WHEN earnings_lt <= 0     THEN 0
        WHEN earnings_lt < 20000  THEN 1
        WHEN earnings_lt < 50000  THEN 2
        WHEN earnings_lt < 100000 THEN 3
        ELSE 4 END
      WHEN SIT_SITE_ID = 'MLB' THEN CASE
        WHEN earnings_lt <= 0  THEN 0
        WHEN earnings_lt < 30  THEN 1
        WHEN earnings_lt < 100 THEN 2
        WHEN earnings_lt < 200 THEN 3
        WHEN earnings_lt < 500 THEN 4
        ELSE 5 END
    END AS bucket_idx
  FROM churner_earnings
)
SELECT SIT_SITE_ID AS sit_site_id,
  FORMAT_DATE('%Y-%m', churn_month) AS mes,
  bucket_idx, COUNT(*) AS users
FROM bucketed
GROUP BY 1,2,3
ORDER BY 1,2,3
) t