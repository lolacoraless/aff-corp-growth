SELECT TO_JSON_STRING(t) AS r
FROM (
WITH monthly_active AS (
  SELECT SIT_SITE_ID, DATE_TRUNC(ORD_CREATED_DT,MONTH) AS month, AFFILIATE_ID
  FROM `meli-bi-data.WHOWNER.BT_AFFI_SALES_ATTRIBUTION_DAILY`
  WHERE ORD_STATUS='paid' AND SIT_SITE_ID IN ('MLB','MLM','MLC','MLA')
    AND SIT_SITE_ID=AFFILIATE_SIT_SITE_ID AND ORD_CREATED_DT >= DATE '2024-01-01'
    AND ORD_CREATED_DT <= CURRENT_DATE('-4')
    AND ((ORD_CREATED_DT >= DATE '2026-04-01' AND NMV_ENIGMA_TOTAL_AMT_LC>0)
      OR (ORD_CREATED_DT<DATE '2026-04-01' AND NMV_TD7DCALIB_TOTAL_AMT_LC>0))
  GROUP BY 1,2,3
),
first_active AS (SELECT SIT_SITE_ID, AFFILIATE_ID, MIN(month) AS first_month FROM monthly_active GROUP BY 1,2),
curr_segs AS (
  SELECT curr.SIT_SITE_ID, curr.month, curr.AFFILIATE_ID,
    CASE WHEN fa.first_month=curr.month THEN 'new'
         WHEN prev.AFFILIATE_ID IS NOT NULL THEN 'recurrent'
         ELSE 'recovered' END AS segment
  FROM monthly_active curr
  LEFT JOIN first_active fa USING(SIT_SITE_ID,AFFILIATE_ID)
  LEFT JOIN monthly_active prev ON curr.AFFILIATE_ID=prev.AFFILIATE_ID AND curr.SIT_SITE_ID=prev.SIT_SITE_ID
    AND prev.month=DATE_SUB(curr.month,INTERVAL 1 MONTH)
),
churn_segs AS (
  SELECT prev.SIT_SITE_ID, DATE_ADD(prev.month,INTERVAL 1 MONTH) AS month, prev.AFFILIATE_ID, 'churned' AS segment
  FROM monthly_active prev
  LEFT JOIN monthly_active curr ON prev.AFFILIATE_ID=curr.AFFILIATE_ID AND prev.SIT_SITE_ID=curr.SIT_SITE_ID
    AND curr.month=DATE_ADD(prev.month,INTERVAL 1 MONTH)
  WHERE curr.AFFILIATE_ID IS NULL
    AND DATE_ADD(prev.month,INTERVAL 1 MONTH) < DATE_TRUNC(CURRENT_DATE(),MONTH)
),
all_segs AS (SELECT * FROM curr_segs UNION ALL SELECT * FROM churn_segs),
link_events AS (
  SELECT SIT_SITE_ID, DATE_TRUNC(EVENT_DT,MONTH) AS month, CUS_CUST_ID, COUNT(*) AS links_cnt
  FROM `meli-bi-data.WHOWNER.BT_AFFI_TRACKS`
  WHERE EVENT_DT >= DATE '2025-01-01' AND EVENT_DT <= CURRENT_DATE('-4')
    AND SIT_SITE_ID IN ('MLB','MLM','MLC','MLA')
    AND ((PATH_NAME='/affiliates/hub/share/select' AND JSON_VALUE(EVENT_DATA,'$.select_value') IN ('copy_link','copy_id'))
      OR PATH_NAME='/affiliates/linkbuilder/v1/generate' OR PATH_NAME='/affiliates/stripe/link'
      OR PATH_NAME IN ('/affiliates/stripe_webview/copy_link','/affiliates/stripe_webview/share_link',
         '/affiliates/stripe_webview/share_code','/affiliates/stripe_webview/copy_code',
         '/affiliates/stripe_webview/share_text_suggestion','/affiliates/stripe_webview/copy_text_suggestion')
      OR PATH_NAME='/share/action')
  GROUP BY 1,2,3
)
SELECT s.SIT_SITE_ID AS sit_site_id, FORMAT_DATE('%Y-%m',s.month) AS mes, s.segment,
  ROUND(SAFE_DIVIDE(SUM(COALESCE(le.links_cnt,0)),
    NULLIF(COUNT(DISTINCT IF(le.CUS_CUST_ID IS NOT NULL,s.AFFILIATE_ID,NULL)),0)),1) AS links_por_usuario
FROM all_segs s
LEFT JOIN link_events le ON s.AFFILIATE_ID=le.CUS_CUST_ID AND s.SIT_SITE_ID=le.SIT_SITE_ID AND s.month=le.month
WHERE s.month >= DATE '2025-01-01'
GROUP BY 1,2,3 ORDER BY mes,sit_site_id,segment
) t