SELECT 'landing_traffic' AS _q, TO_JSON_STRING(t) AS r FROM (
-- landing_traffic v2: mes + semana + MTD pre-agregados.
WITH base AS (
  SELECT site, ds,
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
    uid, user_id
  FROM `meli-bi-data.SBOX_AFILIADOSCOREDATA.MKT_REGISTRATION_JOURNEY`
  WHERE page = 'landing'
    AND ds >= DATE '2025-01-01'
    AND ( ds < '2026-04-01'
       OR path = '/splinter/landing'
       OR (path = '/sbc/site-merch/landing' AND ds >= '2026-08-01') )
),
-- El browser sumaba los COUNT(DISTINCT uid) DIARIOS. Para no mover el numero,
-- calculamos el distinto por dia y despues sumamos, en vez de distinct del mes.
diario AS (
  SELECT site, ds, origen,
    COUNT(*) AS visitas,
    COUNT(DISTINCT uid) AS qty_users,
    COUNT(user_id) AS qty_users_loggedin
  FROM base GROUP BY 1,2,3
)
SELECT 'month' AS grain,
  FORMAT_DATE('%Y-%m-%d', DATE_TRUNC(ds, MONTH)) AS ds, site, origen,
  SUM(visitas) AS visitas, SUM(qty_users) AS qty_users, SUM(qty_users_loggedin) AS qty_users_loggedin
FROM diario GROUP BY 1,2,3,4
UNION ALL
SELECT 'week',
  FORMAT_DATE('%Y-%m-%d', DATE_ADD(DATE_SUB(CURRENT_DATE('America/Argentina/Buenos_Aires'), INTERVAL MOD(EXTRACT(DAYOFWEEK FROM CURRENT_DATE('America/Argentina/Buenos_Aires')) + 5, 7) + 84 DAY),
      INTERVAL DIV(DATE_DIFF(ds, DATE_SUB(CURRENT_DATE('America/Argentina/Buenos_Aires'), INTERVAL MOD(EXTRACT(DAYOFWEEK FROM CURRENT_DATE('America/Argentina/Buenos_Aires')) + 5, 7) + 84 DAY), DAY), 7) * 7 DAY)),
  site, origen, SUM(visitas), SUM(qty_users), SUM(qty_users_loggedin)
FROM diario WHERE DATE_DIFF(ds, DATE_SUB(CURRENT_DATE('America/Argentina/Buenos_Aires'), INTERVAL MOD(EXTRACT(DAYOFWEEK FROM CURRENT_DATE('America/Argentina/Buenos_Aires')) + 5, 7) + 84 DAY), DAY) BETWEEN 0 AND 83
GROUP BY 1,2,3,4
UNION ALL
SELECT 'mtd_curr', FORMAT_DATE('%Y-%m-%d', DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH)), site, origen, SUM(visitas), SUM(qty_users), SUM(qty_users_loggedin)
FROM diario WHERE ds BETWEEN DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH) AND DATE_SUB(CURRENT_DATE('America/Argentina/Buenos_Aires'), INTERVAL 1 DAY) GROUP BY 1,2,3,4
UNION ALL
SELECT 'mtd_prev', FORMAT_DATE('%Y-%m-%d', DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH), INTERVAL 1 MONTH)), site, origen, SUM(visitas), SUM(qty_users), SUM(qty_users_loggedin)
FROM diario WHERE ds BETWEEN DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH), INTERVAL 1 MONTH) AND DATE_ADD(DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH), INTERVAL 1 MONTH), INTERVAL GREATEST(1, LEAST(EXTRACT(DAY FROM CURRENT_DATE('America/Argentina/Buenos_Aires')) - 1, EXTRACT(DAY FROM LAST_DAY(DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Argentina/Buenos_Aires'), MONTH), INTERVAL 1 MONTH))))) - 1 DAY) GROUP BY 1,2,3,4
ORDER BY 1,3,2,4
) t
UNION ALL
SELECT 'landing_pacing' AS _q, TO_JSON_STRING(t) AS r FROM (
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
) t