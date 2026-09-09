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