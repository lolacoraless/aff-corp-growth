SELECT FORMAT_DATE('%Y-%m',EVENT_DT) AS mes, SIT_SITE_ID, COUNT(DISTINCT CUS_CUST_ID) AS generadores_links
FROM `meli-bi-data.WHOWNER.BT_AFFI_TRACKS`
WHERE EVENT_DT >= DATE '2025-01-01' AND EVENT_DT <= CURRENT_DATE('-4')
  AND SIT_SITE_ID IN ('MLB','MLM','MLC','MLA')
  AND ((PATH_NAME='/affiliates/hub/share/select' AND JSON_VALUE(EVENT_DATA,'$.select_value') IN ('copy_link','copy_id'))
    OR PATH_NAME='/affiliates/linkbuilder/v1/generate' OR PATH_NAME='/affiliates/stripe/link'
    OR PATH_NAME IN ('/affiliates/stripe_webview/copy_link','/affiliates/stripe_webview/share_link',
       '/affiliates/stripe_webview/share_code','/affiliates/stripe_webview/copy_code',
       '/affiliates/stripe_webview/share_text_suggestion','/affiliates/stripe_webview/copy_text_suggestion')
    OR PATH_NAME='/share/action')
GROUP BY mes, SIT_SITE_ID ORDER BY mes, SIT_SITE_ID