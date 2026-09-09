-- Las 5 queries de link_gen escaneaban BT_AFFI_TRACKS por separado (1.081 GB).
-- Aca se escanea UNA vez al grano (site, dia, afiliado) y las 5 salidas derivan de ahi.
WITH eventos AS (
  SELECT SIT_SITE_ID, EVENT_DT, CUS_CUST_ID, COUNT(*) AS n
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
link_events AS (
  SELECT SIT_SITE_ID, DATE_TRUNC(EVENT_DT,MONTH) AS mes, CUS_CUST_ID AS affiliate_id, SUM(n) AS links_cnt
  FROM eventos GROUP BY 1,2,3
),
-- Ventas escaneadas una sola vez para by_segment y earnings_by_status
ventas AS (
  SELECT SIT_SITE_ID, DATE_TRUNC(ORD_CREATED_DT,MONTH) AS month, AFFILIATE_ID
  FROM `meli-bi-data.WHOWNER.BT_AFFI_SALES_ATTRIBUTION_DAILY`
  WHERE ORD_STATUS='paid' AND SIT_SITE_ID IN ('MLB','MLM','MLC','MLA')
    AND SIT_SITE_ID=AFFILIATE_SIT_SITE_ID AND ORD_CREATED_DT >= DATE '2024-01-01'
    AND ORD_CREATED_DT <= CURRENT_DATE('-4')
    AND ((ORD_CREATED_DT >= DATE '2026-04-01' AND NMV_ENIGMA_TOTAL_AMT_LC>0)
      OR (ORD_CREATED_DT < DATE '2026-04-01' AND NMV_TD7DCALIB_TOTAL_AMT_LC>0))
  GROUP BY 1,2,3
),
first_active AS (SELECT SIT_SITE_ID, AFFILIATE_ID, MIN(month) AS first_month FROM ventas GROUP BY 1,2),
curr_segs AS (
  SELECT curr.SIT_SITE_ID, curr.month, curr.AFFILIATE_ID,
    CASE WHEN fa.first_month=curr.month THEN 'new'
         WHEN prev.AFFILIATE_ID IS NOT NULL THEN 'recurrent' ELSE 'recovered' END AS segment
  FROM ventas curr
  LEFT JOIN first_active fa USING(SIT_SITE_ID,AFFILIATE_ID)
  LEFT JOIN ventas prev ON curr.AFFILIATE_ID=prev.AFFILIATE_ID AND curr.SIT_SITE_ID=prev.SIT_SITE_ID
    AND prev.month=DATE_SUB(curr.month,INTERVAL 1 MONTH)
),
churn_segs AS (
  SELECT prev.SIT_SITE_ID, DATE_ADD(prev.month,INTERVAL 1 MONTH) AS month, prev.AFFILIATE_ID, 'churned' AS segment
  FROM ventas prev
  LEFT JOIN ventas curr ON prev.AFFILIATE_ID=curr.AFFILIATE_ID AND prev.SIT_SITE_ID=curr.SIT_SITE_ID
    AND curr.month=DATE_ADD(prev.month,INTERVAL 1 MONTH)
  WHERE curr.AFFILIATE_ID IS NULL
    AND DATE_ADD(prev.month,INTERVAL 1 MONTH) < DATE_TRUNC(CURRENT_DATE(),MONTH)
),
all_segs AS (SELECT * FROM curr_segs UNION ALL SELECT * FROM churn_segs),
first_gen AS (SELECT SIT_SITE_ID, affiliate_id, MIN(mes) AS first_month FROM link_events GROUP BY 1,2),
gen_status AS (
  SELECT c.SIT_SITE_ID, c.mes, c.affiliate_id,
    CASE WHEN f.first_month=c.mes THEN 'new'
         WHEN p.affiliate_id IS NOT NULL THEN 'recurrent' ELSE 'recovered' END AS segment
  FROM link_events c
  JOIN first_gen f ON c.SIT_SITE_ID=f.SIT_SITE_ID AND c.affiliate_id=f.affiliate_id
  LEFT JOIN link_events p ON c.SIT_SITE_ID=p.SIT_SITE_ID AND c.affiliate_id=p.affiliate_id
    AND p.mes=DATE_SUB(c.mes,INTERVAL 1 MONTH)
),
earners AS (SELECT SIT_SITE_ID, month AS mes, AFFILIATE_ID AS affiliate_id FROM ventas WHERE month >= DATE '2025-01-01'),
eb AS (
  SELECT g.SIT_SITE_ID AS sit_site_id, FORMAT_DATE('%Y-%m',g.mes) AS mes, g.segment,
    COUNT(DISTINCT g.affiliate_id) AS generadores,
    COUNT(DISTINCT IF(e.affiliate_id IS NOT NULL,g.affiliate_id,NULL)) AS con_earnings
  FROM gen_status g LEFT JOIN earners e
    ON g.SIT_SITE_ID=e.SIT_SITE_ID AND g.affiliate_id=e.affiliate_id AND g.mes=e.mes
  GROUP BY 1,2,3
  UNION ALL
  SELECT g.SIT_SITE_ID, FORMAT_DATE('%Y-%m',g.mes), 'total',
    COUNT(DISTINCT g.affiliate_id),
    COUNT(DISTINCT IF(e.affiliate_id IS NOT NULL,g.affiliate_id,NULL))
  FROM gen_status g LEFT JOIN earners e
    ON g.SIT_SITE_ID=e.SIT_SITE_ID AND g.affiliate_id=e.affiliate_id AND g.mes=e.mes
  GROUP BY 1,2
)
SELECT 'link_gen_monthly' AS _q, TO_JSON_STRING(t) AS r FROM (
  SELECT FORMAT_DATE('%Y-%m',EVENT_DT) AS mes, SIT_SITE_ID, COUNT(DISTINCT CUS_CUST_ID) AS generadores_links
  FROM eventos GROUP BY 1,2) t
UNION ALL
SELECT 'link_gen_daily', TO_JSON_STRING(t) FROM (
  SELECT EVENT_DT, SIT_SITE_ID, COUNT(DISTINCT CUS_CUST_ID) AS generadores_links
  FROM eventos WHERE EVENT_DT >= DATE_SUB(CURRENT_DATE('-4'), INTERVAL 35 DAY)
  GROUP BY 1,2) t
UNION ALL
SELECT 'link_gen_mtd_comp', TO_JSON_STRING(t) FROM (
  SELECT period, SIT_SITE_ID, COUNT(DISTINCT CUS_CUST_ID) AS generadores_links FROM (
    SELECT 'curr' AS period, SIT_SITE_ID, CUS_CUST_ID FROM eventos
    WHERE EVENT_DT >= DATE_TRUNC(CURRENT_DATE('-4'),MONTH)
    UNION ALL
    SELECT 'prev', SIT_SITE_ID, CUS_CUST_ID FROM eventos
    WHERE EVENT_DT >= DATE_TRUNC(DATE_SUB(CURRENT_DATE('-4'),INTERVAL 1 MONTH),MONTH)
      AND EVENT_DT <= DATE_ADD(DATE_TRUNC(DATE_SUB(CURRENT_DATE('-4'),INTERVAL 1 MONTH),MONTH),
            INTERVAL DATE_DIFF(CURRENT_DATE('-4'),DATE_TRUNC(CURRENT_DATE('-4'),MONTH),DAY) DAY))
  GROUP BY 1,2) t
UNION ALL
SELECT 'link_gen_by_segment', TO_JSON_STRING(t) FROM (
  SELECT s.SIT_SITE_ID AS sit_site_id, FORMAT_DATE('%Y-%m',s.month) AS mes, s.segment,
    ROUND(SAFE_DIVIDE(SUM(COALESCE(le.links_cnt,0)),
      NULLIF(COUNT(DISTINCT IF(le.affiliate_id IS NOT NULL,s.AFFILIATE_ID,NULL)),0)),1) AS links_por_usuario
  FROM all_segs s
  LEFT JOIN link_events le ON s.AFFILIATE_ID=le.affiliate_id AND s.SIT_SITE_ID=le.SIT_SITE_ID AND s.month=le.mes
  WHERE s.month >= DATE '2025-01-01'
  GROUP BY 1,2,3) t
UNION ALL
SELECT 'link_gen_earnings_by_status', TO_JSON_STRING(t) FROM (
  SELECT sit_site_id, mes, segment, generadores, con_earnings,
    ROUND(SAFE_DIVIDE(con_earnings,generadores)*100,1) AS pct_earnings
  FROM eb) t
