-- Para M-1 a M-6: visitas a landing acumuladas al d?a D del mes vs cierre total
-- Pacing ratio = visitas_at_day / visitas_full ? base para proyecci?n 6 meses
SELECT
  site,
  FORMAT_DATE('%Y-%m-%d', DATE_TRUNC(DATE(ds), MONTH)) AS month_start,
  CASE
    WHEN site = 'MLC' AND ds <= '2026-09-08'
     AND JSON_EXTRACT_SCALAR(fragment, '$.origin') = 'search_mp'        THEN 'Direct-SugestsMP'
    WHEN JSON_EXTRACT_SCALAR(fragment, '$.origin') = 'quickaccess'      THEN 'Direct-QuickAccess'
    WHEN JSON_EXTRACT_SCALAR(fragment, '$.origin') = 'appmenu'          THEN 'Direct-Appmenu'
    WHEN JSON_EXTRACT_SCALAR(fragment, '$.origin') = 'share_vpp_banner' THEN 'Direct-VppShare'
    WHEN JSON_EXTRACT_SCALAR(fragment, '$.origin') = 'home_discovery'   THEN 'Direct-HomeDiscovery'
    WHEN JSON_EXTRACT_SCALAR(fragment, '$.origin') = 'search_mp'        THEN 'Direct-SearchMP'
    WHEN JSON_EXTRACT_SCALAR(fragment, '$.origin') = 'appmenu_mp'       THEN 'Direct-AppmenuMP'
    WHEN JSON_EXTRACT_SCALAR(fragment, '$.origin') = 'sugestions_mp'    THEN 'Direct-SugestsMP'
    WHEN REGEXP_CONTAINS(campaign, r"_FB")                              THEN 'POM-Facebook'
    WHEN REGEXP_CONTAINS(campaign, r"_TIKTOK_")                         THEN 'POM-TikTok'
    WHEN REGEXP_CONTAINS(campaign, r"PUSH")                             THEN 'E&G-Push'
    WHEN REGEXP_CONTAINS(campaign, r"MAIL")                             THEN 'E&G-Mail'
    WHEN REGEXP_CONTAINS(campaign, r"_G_")                              THEN 'POM-Google'
    WHEN REGEXP_CONTAINS(campaign, r"AFF-AFF")                          THEN 'E&G'
    ELSE 'Direct'
  END AS origen,
  COUNTIF(EXTRACT(DAY FROM DATE(ds)) <= (EXTRACT(DAY FROM CURRENT_DATE('America/Argentina/Buenos_Aires')) - 1)) AS visitas_at_day,
  COUNT(*) AS visitas_full
FROM `meli-bi-data.SBOX_AFILIADOSCOREDATA.MKT_REGISTRATION_JOURNEY`
WHERE page = 'landing'
  AND ds >= DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH), INTERVAL 6 MONTH)
  AND ds < DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH)
  AND (
    ds < '2026-04-01'
    OR path = '/splinter/landing'
    OR (path = '/sbc/site-merch/landing' AND ds >= '2026-08-01')
  )
GROUP BY site, month_start, origen
ORDER BY site, month_start, origen