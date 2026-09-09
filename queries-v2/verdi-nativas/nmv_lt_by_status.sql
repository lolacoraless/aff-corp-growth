WITH kam_excl AS (
  SELECT DISTINCT CAST(cus_cust_id_aff AS INT64) AS affiliate_id, sit_site_id
  FROM `meli-bi-data.SBOX_AFILIADOSCOREDATA.MKT_AFFILIATE_TYPE`
  UNION DISTINCT
  SELECT DISTINCT cus_cust_id_aff, sit_site_id
  FROM `meli-bi-data.SBOX_AFILIADOSCOREDATA.MKT_KA_CATEGORIES`
  WHERE segment = 'Potential KAM'
),
monthly_sales AS (
  SELECT s.SIT_SITE_ID, s.AFFILIATE_ID, DATE_TRUNC(s.ORD_CREATED_DT, MONTH) AS mes,
    SUM(CASE WHEN s.ORD_CREATED_DT >= DATE '2026-04-01' THEN s.NMV_ENIGMA_TOTAL_AMT_LC
             ELSE s.NMV_TD7DCALIB_TOTAL_AMT_LC END) AS nmv_aff
  FROM `meli-bi-data.WHOWNER.BT_AFFI_SALES_ATTRIBUTION_DAILY` s
  LEFT JOIN kam_excl e ON s.AFFILIATE_ID = e.affiliate_id AND s.SIT_SITE_ID = e.sit_site_id
  WHERE e.affiliate_id IS NULL
    AND s.AFFILIATE_ID IS NOT NULL AND s.AFFILIATE_ID != 0
    AND s.ORD_STATUS = 'paid' AND s.SIT_SITE_ID = s.AFFILIATE_SIT_SITE_ID
    AND s.ORD_CREATED_DT >= DATE '2025-01-01'
    AND s.SIT_SITE_ID IN ('MLB','MLM','MLC','MLA')
    AND ((s.ORD_CREATED_DT >= DATE '2026-04-01' AND s.NMV_ENIGMA_TOTAL_AMT_LC > 0)
      OR (s.ORD_CREATED_DT < DATE '2026-04-01' AND s.NMV_TD7DCALIB_TOTAL_AMT_LC > 0))
  GROUP BY 1,2,3
),
first_sale AS (
  SELECT SIT_SITE_ID, AFFILIATE_ID, MIN(mes) AS first_month
  FROM monthly_sales GROUP BY 1,2
),
segments AS (
  SELECT c.SIT_SITE_ID, c.AFFILIATE_ID, c.mes, c.nmv_aff,
    CASE WHEN f.first_month = c.mes THEN 'new'
         WHEN p.AFFILIATE_ID IS NULL THEN 'recovered'
         ELSE 'recurrent' END AS segment
  FROM monthly_sales c
  JOIN first_sale f USING (SIT_SITE_ID, AFFILIATE_ID)
  LEFT JOIN monthly_sales p
    ON c.SIT_SITE_ID = p.SIT_SITE_ID AND c.AFFILIATE_ID = p.AFFILIATE_ID
    AND p.mes = DATE_SUB(c.mes, INTERVAL 1 MONTH)
)
SELECT mes, SIT_SITE_ID, segment,
  COUNT(DISTINCT AFFILIATE_ID) AS active_aff,
  SUM(nmv_aff) AS nmv_aff,
  SAFE_DIVIDE(SUM(nmv_aff), COUNT(DISTINCT AFFILIATE_ID)) AS npa
FROM segments
GROUP BY 1,2,3
ORDER BY mes, SIT_SITE_ID, segment