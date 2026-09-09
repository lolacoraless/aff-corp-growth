SELECT TO_JSON_STRING(t) AS r
FROM (
WITH link_events AS (
  SELECT SIT_SITE_ID, DATE_TRUNC(EVENT_DT, MONTH) AS mes, CUS_CUST_ID AS affiliate_id
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
),
first_gen AS (
  SELECT SIT_SITE_ID, affiliate_id, MIN(mes) AS first_month
  FROM link_events GROUP BY 1,2
),
gen_status AS (
  SELECT c.SIT_SITE_ID, c.mes, c.affiliate_id,
    CASE WHEN f.first_month = c.mes THEN 'new'
         WHEN p.affiliate_id IS NOT NULL THEN 'recurrent'
         ELSE 'recovered' END AS segment
  FROM link_events c
  JOIN first_gen f ON c.SIT_SITE_ID = f.SIT_SITE_ID AND c.affiliate_id = f.affiliate_id
  LEFT JOIN link_events p ON c.SIT_SITE_ID = p.SIT_SITE_ID AND c.affiliate_id = p.affiliate_id
    AND p.mes = DATE_SUB(c.mes, INTERVAL 1 MONTH)
),
earners AS (
  SELECT SIT_SITE_ID, DATE_TRUNC(ORD_CREATED_DT, MONTH) AS mes, AFFILIATE_ID AS affiliate_id
  FROM `meli-bi-data.WHOWNER.BT_AFFI_SALES_ATTRIBUTION_DAILY`
  WHERE ORD_STATUS = 'paid' AND SIT_SITE_ID IN ('MLB','MLM','MLC','MLA')
    AND SIT_SITE_ID = AFFILIATE_SIT_SITE_ID
    AND ORD_CREATED_DT >= DATE '2025-01-01' AND ORD_CREATED_DT <= CURRENT_DATE('-4')
    AND ((ORD_CREATED_DT >= DATE '2026-04-01' AND NMV_ENIGMA_TOTAL_AMT_LC > 0)
      OR (ORD_CREATED_DT < DATE '2026-04-01' AND NMV_TD7DCALIB_TOTAL_AMT_LC > 0))
  GROUP BY 1,2,3
),
by_status AS (
  SELECT g.SIT_SITE_ID AS sit_site_id, FORMAT_DATE('%Y-%m', g.mes) AS mes, g.segment,
    COUNT(DISTINCT g.affiliate_id) AS generadores,
    COUNT(DISTINCT IF(e.affiliate_id IS NOT NULL, g.affiliate_id, NULL)) AS con_earnings
  FROM gen_status g
  LEFT JOIN earners e ON g.SIT_SITE_ID = e.SIT_SITE_ID AND g.affiliate_id = e.affiliate_id AND g.mes = e.mes
  GROUP BY 1,2,3
),
total AS (
  SELECT g.SIT_SITE_ID AS sit_site_id, FORMAT_DATE('%Y-%m', g.mes) AS mes, 'total' AS segment,
    COUNT(DISTINCT g.affiliate_id) AS generadores,
    COUNT(DISTINCT IF(e.affiliate_id IS NOT NULL, g.affiliate_id, NULL)) AS con_earnings
  FROM gen_status g
  LEFT JOIN earners e ON g.SIT_SITE_ID = e.SIT_SITE_ID AND g.affiliate_id = e.affiliate_id AND g.mes = e.mes
  GROUP BY 1,2
)
SELECT sit_site_id, mes, segment, generadores, con_earnings,
  ROUND(SAFE_DIVIDE(con_earnings, generadores) * 100, 1) AS pct_earnings
FROM by_status
UNION ALL
SELECT sit_site_id, mes, segment, generadores, con_earnings,
  ROUND(SAFE_DIVIDE(con_earnings, generadores) * 100, 1) AS pct_earnings
FROM total
ORDER BY mes, sit_site_id, segment
) t