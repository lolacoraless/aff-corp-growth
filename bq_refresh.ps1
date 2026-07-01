$ErrorActionPreference = "Continue"
$ProgressPreference    = "SilentlyContinue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ==== DATES ==================================================================
$now     = Get-Date
$HIST    = "2025-01-01"; $DEEP = "2024-01-01"; $ENIGMA = "2026-04-01"
$YEST    = $now.AddDays(-1).ToString("yyyy-MM-dd")
$CUR_DT  = Get-Date -Year $now.Year -Month $now.Month -Day 1
$CUR     = $CUR_DT.ToString("yyyy-MM-dd")
$PREV_DT = $CUR_DT.AddMonths(-1)
$PREV    = $PREV_DT.ToString("yyyy-MM-dd")
$M2      = $CUR_DT.AddMonths(-2).ToString("yyyy-MM-dd")
$M3      = $CUR_DT.AddMonths(-3).ToString("yyyy-MM-dd")
$M4      = $CUR_DT.AddMonths(-4).ToString("yyyy-MM-dd")
$M5      = $CUR_DT.AddMonths(-5).ToString("yyyy-MM-dd")
$M6      = $CUR_DT.AddMonths(-6).ToString("yyyy-MM-dd")
$M7      = $CUR_DT.AddMonths(-7).ToString("yyyy-MM-dd")
$DAY_OF_MONTH = ($now.Day - 1)   # día de ayer dentro del mes (cutoff pacing)
$prevLast = [DateTime]::DaysInMonth($PREV_DT.Year, $PREV_DT.Month)
$pdDay   = [Math]::Max(1, [Math]::Min($now.Day - 1, $prevLast))
$PREV_DAY = (Get-Date -Year $PREV_DT.Year -Month $PREV_DT.Month -Day $pdDay).ToString("yyyy-MM-dd")
$dow = [int]$now.DayOfWeek; $dtm = if($dow -eq 0){6}else{$dow-1}
$W8  = $now.AddDays(-$dtm - 84).ToString("yyyy-MM-dd")  # 12 semanas atras (7x12=84)
# Registros: AFFILIATE_REGISTRATION_CHANNEL actualiza ~15:00h
# Antes de las 15h el dia de ayer no esta en la tabla — usar D-2 para mantener periodos simetricos
$REG_OFFSET   = if ($now.Hour -ge 15) { 1 } else { 2 }
$YEST_REG     = $now.AddDays(-$REG_OFFSET).ToString("yyyy-MM-dd")
$pdDayReg     = [Math]::Min(([DateTime]$YEST_REG).Day, $prevLast)
$PREV_DAY_REG = (Get-Date -Year $PREV_DT.Year -Month $PREV_DT.Month -Day $pdDayReg).ToString("yyyy-MM-dd")

Write-Host ""
Write-Host "=== AFFILIATES DASHBOARD - BQ REFRESH ===" -ForegroundColor Cyan
Write-Host "YEST=$YEST  CUR=$CUR  PREV=$PREV  PREV_DAY=$PREV_DAY  M2=$M2  M3=$M3  M4=$M4  M5=$M5  M6=$M6  DAY=$DAY_OF_MONTH  W8=$W8"
Write-Host ""

# ==== DATE SUBSTITUTION ======================================================
function d($s) {
    $r = $s
    $r = $r.Replace('${D.HIST}',     $HIST)
    $r = $r.Replace('${D.DEEP}',     $DEEP)
    $r = $r.Replace('${D.ENIGMA}',   $ENIGMA)
    $r = $r.Replace('${D.YEST}',     $YEST)
    $r = $r.Replace('${D.CUR}',      $CUR)
    $r = $r.Replace('${D.PREV}',     $PREV)
    $r = $r.Replace('${D.PREV_DAY}', $PREV_DAY)
    $r = $r.Replace('${D.M2}',           $M2)
    $r = $r.Replace('${D.M3}',           $M3)
    $r = $r.Replace('${D.M4}',           $M4)
    $r = $r.Replace('${D.M5}',           $M5)
    $r = $r.Replace('${D.M6}',           $M6)
    $r = $r.Replace('${D.M7}',           $M7)
    $r = $r.Replace('${D.DAY_OF_MONTH}', [string]$DAY_OF_MONTH)
    $r = $r.Replace('${D.W8}',           $W8)
    $r = $r.Replace('${D.YEST_REG}',     $YEST_REG)
    $r = $r.Replace('${D.PREV_DAY_REG}', $PREV_DAY_REG)
    return $r
}

# ==== SQL MAP (all 17 queries, date-substituted before parallel launch) ======
$sqlMap = [ordered]@{}

$sqlMap["behaviour"] = d @'
SELECT sit_site_id, dt, period, active_aff,
  retained_aff AS recurrent, recovered_aff AS recovered,
  new_aff, churned_aff AS inactive,
  SAFE_DIVIDE(new_aff + recovered_aff, churned_aff) AS quick_ratio
FROM `meli-bi-data.SBOX_AFILIADOSCOREDATA.MKT_AFFILIATE_BEHAVIOUR`
WHERE period IN ('MONTH','WEEK')
  AND sit_site_id IN ('MLB','MLM','MLC','MLA')
  AND dt >= '${D.HIST}'
ORDER BY sit_site_id, period, dt
'@

$sqlMap["beh_mtd"] = d @'
WITH all_sales AS (
  SELECT SIT_SITE_ID, AFFILIATE_ID, DATE_TRUNC(ORD_CREATED_DT, MONTH) AS sale_month
  FROM `meli-bi-data.WHOWNER.BT_AFFI_SALES_ATTRIBUTION_DAILY`
  WHERE ORD_STATUS = 'paid' AND SIT_SITE_ID = AFFILIATE_SIT_SITE_ID
    AND SIT_SITE_ID IN ('MLB','MLM','MLC','MLA')
    AND ORD_CREATED_DT >= '${D.DEEP}'
    AND ((ORD_CREATED_DT >= '${D.ENIGMA}' AND NMV_ENIGMA_TOTAL_AMT_LC > 0)
      OR (ORD_CREATED_DT < '${D.ENIGMA}' AND NMV_TD7DCALIB_TOTAL_AMT_LC > 0))
  GROUP BY 1,2,3
),
first_sale AS (SELECT SIT_SITE_ID, AFFILIATE_ID, MIN(sale_month) AS first_month FROM all_sales GROUP BY 1,2),
curr_7d AS (
  SELECT DISTINCT SIT_SITE_ID, AFFILIATE_ID
  FROM `meli-bi-data.WHOWNER.BT_AFFI_SALES_ATTRIBUTION_DAILY`
  WHERE ORD_CREATED_DT BETWEEN '${D.CUR}' AND '${D.YEST}'
    AND ORD_STATUS = 'paid' AND SIT_SITE_ID = AFFILIATE_SIT_SITE_ID
    AND SIT_SITE_ID IN ('MLB','MLM','MLC','MLA') AND NMV_ENIGMA_TOTAL_AMT_LC > 0
),
prev_7d AS (
  SELECT DISTINCT SIT_SITE_ID, AFFILIATE_ID
  FROM `meli-bi-data.WHOWNER.BT_AFFI_SALES_ATTRIBUTION_DAILY`
  WHERE ORD_CREATED_DT BETWEEN '${D.PREV}' AND '${D.PREV_DAY}'
    AND ORD_STATUS = 'paid' AND SIT_SITE_ID = AFFILIATE_SIT_SITE_ID
    AND SIT_SITE_ID IN ('MLB','MLM','MLC','MLA') AND NMV_ENIGMA_TOTAL_AMT_LC > 0
),
apr_full AS (SELECT DISTINCT SIT_SITE_ID, AFFILIATE_ID FROM all_sales WHERE sale_month = '${D.PREV}'),
mar_full AS (SELECT DISTINCT SIT_SITE_ID, AFFILIATE_ID FROM all_sales WHERE sale_month = '${D.M2}'),
curr_flow AS (
  SELECT c.SIT_SITE_ID,
    COUNT(DISTINCT c.AFFILIATE_ID) AS active_aff,
    COUNT(DISTINCT IF(f.first_month = '${D.CUR}', c.AFFILIATE_ID, NULL)) AS new_aff,
    COUNT(DISTINCT IF(f.first_month < '${D.CUR}' AND a.AFFILIATE_ID IS NULL, c.AFFILIATE_ID, NULL)) AS recovered_aff
  FROM curr_7d c LEFT JOIN first_sale f USING (SIT_SITE_ID, AFFILIATE_ID)
  LEFT JOIN apr_full a USING (SIT_SITE_ID, AFFILIATE_ID) GROUP BY 1
),
curr_churn AS (
  SELECT a.SIT_SITE_ID, COUNT(DISTINCT IF(c.AFFILIATE_ID IS NULL, a.AFFILIATE_ID, NULL)) AS churned_aff
  FROM apr_full a LEFT JOIN curr_7d c USING (SIT_SITE_ID, AFFILIATE_ID) GROUP BY 1
),
prev_flow AS (
  SELECT p.SIT_SITE_ID,
    COUNT(DISTINCT p.AFFILIATE_ID) AS active_aff,
    COUNT(DISTINCT IF(f.first_month = '${D.PREV}', p.AFFILIATE_ID, NULL)) AS new_aff,
    COUNT(DISTINCT IF(f.first_month < '${D.PREV}' AND m.AFFILIATE_ID IS NULL, p.AFFILIATE_ID, NULL)) AS recovered_aff
  FROM prev_7d p LEFT JOIN first_sale f USING (SIT_SITE_ID, AFFILIATE_ID)
  LEFT JOIN mar_full m USING (SIT_SITE_ID, AFFILIATE_ID) GROUP BY 1
),
prev_churn AS (
  SELECT m.SIT_SITE_ID, COUNT(DISTINCT IF(p.AFFILIATE_ID IS NULL, m.AFFILIATE_ID, NULL)) AS churned_aff
  FROM mar_full m LEFT JOIN prev_7d p USING (SIT_SITE_ID, AFFILIATE_ID) GROUP BY 1
)
SELECT cf.SIT_SITE_ID, 'curr' AS period, cf.active_aff, cf.new_aff, cf.recovered_aff, cc.churned_aff
FROM curr_flow cf JOIN curr_churn cc USING (SIT_SITE_ID)
UNION ALL
SELECT pf.SIT_SITE_ID, 'prev' AS period, pf.active_aff, pf.new_aff, pf.recovered_aff, pc.churned_aff
FROM prev_flow pf JOIN prev_churn pc USING (SIT_SITE_ID)
'@

$sqlMap["beh_pacing"] = d @'
-- Para M-2 a M-6: cuántos afiliados activos/new/rec/ret/chu había al día D de ese mes
-- (mismo día del mes que ayer) — usado para calcular pacing histórico de proyecciones
WITH all_sales AS (
  SELECT DISTINCT SIT_SITE_ID, AFFILIATE_ID,
    DATE(ORD_CREATED_DT) AS sale_date,
    DATE_TRUNC(ORD_CREATED_DT, MONTH) AS sale_month
  FROM `meli-bi-data.WHOWNER.BT_AFFI_SALES_ATTRIBUTION_DAILY`
  WHERE ORD_STATUS = 'paid'
    AND SIT_SITE_ID = AFFILIATE_SIT_SITE_ID
    AND SIT_SITE_ID IN ('MLB','MLM','MLC','MLA')
    AND ORD_CREATED_DT >= '${D.M7}'
    AND ORD_CREATED_DT < '${D.CUR}'
    AND ((ORD_CREATED_DT >= '${D.ENIGMA}' AND NMV_ENIGMA_TOTAL_AMT_LC > 0)
      OR (ORD_CREATED_DT < '${D.ENIGMA}' AND NMV_TD7DCALIB_TOTAL_AMT_LC > 0))
),
first_ever AS (
  SELECT SIT_SITE_ID, AFFILIATE_ID,
    DATE_TRUNC(MIN(ORD_CREATED_DT), MONTH) AS first_month
  FROM `meli-bi-data.WHOWNER.BT_AFFI_SALES_ATTRIBUTION_DAILY`
  WHERE ORD_STATUS = 'paid'
    AND SIT_SITE_ID = AFFILIATE_SIT_SITE_ID
    AND SIT_SITE_ID IN ('MLB','MLM','MLC','MLA')
    AND ORD_CREATED_DT >= '${D.DEEP}'
    AND ((ORD_CREATED_DT >= '${D.ENIGMA}' AND NMV_ENIGMA_TOTAL_AMT_LC > 0)
      OR (ORD_CREATED_DT < '${D.ENIGMA}' AND NMV_TD7DCALIB_TOTAL_AMT_LC > 0))
  GROUP BY 1,2
),
monthly_full AS (
  SELECT SIT_SITE_ID, AFFILIATE_ID, sale_month
  FROM all_sales GROUP BY 1,2,3
),
target_months AS (
  SELECT DATE('${D.M2}') AS m UNION ALL
  SELECT DATE('${D.M3}') UNION ALL
  SELECT DATE('${D.M4}') UNION ALL
  SELECT DATE('${D.M5}') UNION ALL
  SELECT DATE('${D.M6}')
),
-- Afiliados activos de día 1 al día D de cada mes objetivo
at_day AS (
  SELECT s.SIT_SITE_ID, t.m AS month_start, s.AFFILIATE_ID
  FROM all_sales s
  JOIN target_months t ON s.sale_month = t.m
  WHERE EXTRACT(DAY FROM s.sale_date) <= ${D.DAY_OF_MONTH}
  GROUP BY 1,2,3
),
-- Afiliados del mes anterior (para clasificación new/rec/ret/chu)
prev_full AS (
  SELECT mf.SIT_SITE_ID, DATE_ADD(mf.sale_month, INTERVAL 1 MONTH) AS target_month, mf.AFFILIATE_ID
  FROM monthly_full mf
  WHERE mf.sale_month IN (
    DATE_SUB(DATE('${D.M2}'), INTERVAL 1 MONTH),
    DATE_SUB(DATE('${D.M3}'), INTERVAL 1 MONTH),
    DATE_SUB(DATE('${D.M4}'), INTERVAL 1 MONTH),
    DATE_SUB(DATE('${D.M5}'), INTERVAL 1 MONTH),
    DATE_SUB(DATE('${D.M6}'), INTERVAL 1 MONTH)
  )
),
-- Churned al día D: en mes anterior completo pero NO en at_day
churned AS (
  SELECT pf.SIT_SITE_ID, pf.target_month AS month_start, pf.AFFILIATE_ID
  FROM prev_full pf
  LEFT JOIN at_day a ON a.SIT_SITE_ID = pf.SIT_SITE_ID
    AND a.month_start = pf.target_month AND a.AFFILIATE_ID = pf.AFFILIATE_ID
  WHERE a.AFFILIATE_ID IS NULL
),
active_counts AS (
  SELECT a.SIT_SITE_ID AS site, a.month_start,
    COUNT(DISTINCT a.AFFILIATE_ID) AS active_at_day,
    COUNT(DISTINCT IF(fe.first_month = a.month_start, a.AFFILIATE_ID, NULL)) AS new_at_day,
    COUNT(DISTINCT IF(fe.first_month < a.month_start AND pf.AFFILIATE_ID IS NULL, a.AFFILIATE_ID, NULL)) AS recovered_at_day,
    COUNT(DISTINCT IF(fe.first_month < a.month_start AND pf.AFFILIATE_ID IS NOT NULL, a.AFFILIATE_ID, NULL)) AS recurrent_at_day
  FROM at_day a
  LEFT JOIN first_ever fe USING (SIT_SITE_ID, AFFILIATE_ID)
  LEFT JOIN prev_full pf ON pf.SIT_SITE_ID = a.SIT_SITE_ID
    AND pf.target_month = a.month_start AND pf.AFFILIATE_ID = a.AFFILIATE_ID
  GROUP BY site, month_start
),
churn_counts AS (
  SELECT SIT_SITE_ID AS site, month_start,
    COUNT(DISTINCT AFFILIATE_ID) AS churned_at_day
  FROM churned GROUP BY 1,2
)
SELECT
  ac.site, FORMAT_DATE('%Y-%m-%d', ac.month_start) AS month_start,
  ac.active_at_day, ac.new_at_day, ac.recovered_at_day, ac.recurrent_at_day,
  COALESCE(cc.churned_at_day, 0) AS churned_at_day
FROM active_counts ac
LEFT JOIN churn_counts cc USING (site, month_start)
ORDER BY site, month_start
'@

$sqlMap["qr_rolling"] = d @'
WITH all_sales AS (
  SELECT SIT_SITE_ID, AFFILIATE_ID, DATE(ORD_CREATED_DT) AS sale_date
  FROM `meli-bi-data.WHOWNER.BT_AFFI_SALES_ATTRIBUTION_DAILY`
  WHERE ORD_STATUS = 'paid' AND SIT_SITE_ID = AFFILIATE_SIT_SITE_ID
    AND SIT_SITE_ID IN ('MLB','MLM','MLC','MLA')
    AND ORD_CREATED_DT >= DATE_SUB('${D.YEST}', INTERVAL 61 DAY)
    AND ((ORD_CREATED_DT >= '${D.ENIGMA}' AND NMV_ENIGMA_TOTAL_AMT_LC > 0)
      OR (ORD_CREATED_DT < '${D.ENIGMA}' AND NMV_TD7DCALIB_TOTAL_AMT_LC > 0))
  GROUP BY 1,2,3
),
first_ever AS (
  SELECT SIT_SITE_ID, AFFILIATE_ID, MIN(DATE(ORD_CREATED_DT)) AS first_date
  FROM `meli-bi-data.WHOWNER.BT_AFFI_SALES_ATTRIBUTION_DAILY`
  WHERE ORD_STATUS = 'paid' AND SIT_SITE_ID = AFFILIATE_SIT_SITE_ID
    AND SIT_SITE_ID IN ('MLB','MLM','MLC','MLA') AND ORD_CREATED_DT >= '${D.DEEP}'
    AND ((ORD_CREATED_DT >= '${D.ENIGMA}' AND NMV_ENIGMA_TOTAL_AMT_LC > 0)
      OR (ORD_CREATED_DT < '${D.ENIGMA}' AND NMV_TD7DCALIB_TOTAL_AMT_LC > 0))
  GROUP BY 1,2
),
win_curr AS (SELECT DISTINCT SIT_SITE_ID, AFFILIATE_ID FROM all_sales
  WHERE sale_date BETWEEN DATE_SUB('${D.YEST}', INTERVAL 29 DAY) AND '${D.YEST}'),
win_prev AS (SELECT DISTINCT SIT_SITE_ID, AFFILIATE_ID FROM all_sales
  WHERE sale_date BETWEEN DATE_SUB('${D.YEST}', INTERVAL 59 DAY) AND DATE_SUB('${D.YEST}', INTERVAL 30 DAY)),
affiliates AS (
  SELECT SIT_SITE_ID, AFFILIATE_ID FROM win_curr
  UNION DISTINCT
  SELECT SIT_SITE_ID, AFFILIATE_ID FROM win_prev
)
SELECT a.SIT_SITE_ID,
  FORMAT_DATE('%Y-%m-%d', DATE_SUB('${D.YEST}', INTERVAL 29 DAY)) AS window_start,
  '${D.YEST}' AS window_end,
  COUNT(DISTINCT IF(c.AFFILIATE_ID IS NOT NULL AND f.first_date >= DATE_SUB('${D.YEST}', INTERVAL 29 DAY), a.AFFILIATE_ID, NULL)) AS new_30d,
  COUNT(DISTINCT IF(c.AFFILIATE_ID IS NOT NULL AND p.AFFILIATE_ID IS NULL AND (f.first_date IS NULL OR f.first_date < DATE_SUB('${D.YEST}', INTERVAL 59 DAY)), a.AFFILIATE_ID, NULL)) AS recovered_30d,
  COUNT(DISTINCT IF(p.AFFILIATE_ID IS NOT NULL AND c.AFFILIATE_ID IS NULL, a.AFFILIATE_ID, NULL)) AS churned_30d,
  COUNT(DISTINCT c.AFFILIATE_ID) AS active_30d
FROM affiliates a
LEFT JOIN win_curr c USING (SIT_SITE_ID, AFFILIATE_ID)
LEFT JOIN win_prev p USING (SIT_SITE_ID, AFFILIATE_ID)
LEFT JOIN first_ever f USING (SIT_SITE_ID, AFFILIATE_ID)
GROUP BY 1,2,3
'@

$sqlMap["registrations"] = d @'
SELECT ds, site_id, origen, origen_grouped,
  COUNT(*) AS users,
  EXTRACT(YEAR    FROM DATE(ds)) AS year,
  EXTRACT(QUARTER FROM DATE(ds)) AS quarter,
  EXTRACT(MONTH   FROM DATE(ds)) AS month,
  EXTRACT(ISOWEEK FROM DATE(ds)) AS isoweek
FROM `meli-bi-data.SBOX_AFILIADOSCOREDATA.AFFILIATE_REGISTRATION_CHANNEL`
WHERE DATE(ds) >= '${D.HIST}' AND site_id IN ('MLB','MLM','MLC','MLA')
GROUP BY ALL ORDER BY 1,2,3
'@

$sqlMap["reg_mtd"] = d @'
-- Tabla actualiza ~15:00h → YEST_REG = D-2 antes de las 15h, D-1 despues
-- Garantiza periodos simetricos: misma cantidad de dias en curr y prev
SELECT site_id, origen, origen_grouped, COUNT(*) AS users, 'curr' AS period
FROM `meli-bi-data.SBOX_AFILIADOSCOREDATA.AFFILIATE_REGISTRATION_CHANNEL`
WHERE DATE(ds) BETWEEN '${D.CUR}' AND '${D.YEST_REG}'
  AND site_id IN ('MLB','MLM','MLC','MLA')
GROUP BY ALL
UNION ALL
SELECT site_id, origen, origen_grouped, COUNT(*) AS users, 'prev' AS period
FROM `meli-bi-data.SBOX_AFILIADOSCOREDATA.AFFILIATE_REGISTRATION_CHANNEL`
WHERE DATE(ds) BETWEEN '${D.PREV}' AND '${D.PREV_DAY_REG}'
  AND site_id IN ('MLB','MLM','MLC','MLA')
GROUP BY ALL
'@

$sqlMap["reg_pacing"] = d @'
-- Para M-1 a M-6: registros acumulados al día D del mes vs cierre total
-- Pacing ratio = reg_at_day / reg_full → base para proyección 6 meses
SELECT
  site_id AS site,
  FORMAT_DATE('%Y-%m-%d', DATE_TRUNC(DATE(ds), MONTH)) AS month_start,
  origen_grouped,
  COUNTIF(EXTRACT(DAY FROM DATE(ds)) <= ${D.DAY_OF_MONTH}) AS reg_at_day,
  COUNT(*) AS reg_full
FROM `meli-bi-data.SBOX_AFILIADOSCOREDATA.AFFILIATE_REGISTRATION_CHANNEL`
WHERE DATE(ds) >= '${D.M6}'
  AND DATE(ds) < '${D.CUR}'
  AND site_id IN ('MLB','MLM','MLC','MLA')
GROUP BY site, month_start, origen_grouped
ORDER BY site, month_start, origen_grouped
'@

$sqlMap["landing_traffic"] = d @'
SELECT
  site,
  ds,
  CASE
    WHEN REGEXP_CONTAINS(campaign, r"_FB")           THEN "POM-Facebook"
    WHEN REGEXP_CONTAINS(campaign, r"_TIKTOK_")      THEN "POM-TikTok"
    WHEN REGEXP_CONTAINS(campaign, r"PUSH")          THEN "E&G-Push"
    WHEN REGEXP_CONTAINS(campaign, r"MAIL")          THEN "E&G-Mail"
    WHEN REGEXP_CONTAINS(campaign, r"_G_")           THEN "POM-Google"
    WHEN REGEXP_CONTAINS(campaign, r"AFF-AFF")       THEN "E&G"
    WHEN JSON_EXTRACT_SCALAR(fragment, '$.origin') = 'appmenu'          THEN 'Direct-Appmenu'
    WHEN JSON_EXTRACT_SCALAR(fragment, '$.origin') = 'quickaccess'      THEN 'Direct-QuickAccess'
    WHEN JSON_EXTRACT_SCALAR(fragment, '$.origin') = 'share_vpp_banner' THEN 'Direct-VppShare'
    ELSE "Direct"
  END AS origen,
  COUNT(*) AS visitas,
  COUNT(DISTINCT uid) AS qty_users,
  COUNT(user_id) AS qty_users_loggedin
FROM `meli-bi-data.SBOX_AFILIADOSCOREDATA.MKT_REGISTRATION_JOURNEY` b
WHERE page = 'landing'
  AND ds >= '${D.HIST}'
  AND (ds < '2026-04-01' OR path = '/splinter/landing')
GROUP BY ALL
'@

$sqlMap["landing_pacing"] = d @'
-- Para M-1 a M-6: visitas a landing acumuladas al día D del mes vs cierre total
-- Pacing ratio = visitas_at_day / visitas_full → base para proyección 6 meses
SELECT
  site,
  FORMAT_DATE('%Y-%m-%d', DATE_TRUNC(DATE(ds), MONTH)) AS month_start,
  CASE
    WHEN REGEXP_CONTAINS(campaign, r"_FB")           THEN "POM-Facebook"
    WHEN REGEXP_CONTAINS(campaign, r"_TIKTOK_")      THEN "POM-TikTok"
    WHEN REGEXP_CONTAINS(campaign, r"PUSH")          THEN "E&G-Push"
    WHEN REGEXP_CONTAINS(campaign, r"MAIL")          THEN "E&G-Mail"
    WHEN REGEXP_CONTAINS(campaign, r"_G_")           THEN "POM-Google"
    WHEN REGEXP_CONTAINS(campaign, r"AFF-AFF")       THEN "E&G"
    WHEN JSON_EXTRACT_SCALAR(fragment, '$.origin') = 'appmenu'          THEN 'Direct-Appmenu'
    WHEN JSON_EXTRACT_SCALAR(fragment, '$.origin') = 'quickaccess'      THEN 'Direct-QuickAccess'
    WHEN JSON_EXTRACT_SCALAR(fragment, '$.origin') = 'share_vpp_banner' THEN 'Direct-VppShare'
    ELSE "Direct"
  END AS origen,
  COUNTIF(EXTRACT(DAY FROM DATE(ds)) <= ${D.DAY_OF_MONTH}) AS visitas_at_day,
  COUNT(*) AS visitas_full
FROM `meli-bi-data.SBOX_AFILIADOSCOREDATA.MKT_REGISTRATION_JOURNEY`
WHERE page = 'landing'
  AND ds >= '${D.M6}'
  AND ds < '${D.CUR}'
GROUP BY site, month_start, origen
ORDER BY site, month_start, origen
'@

$sqlMap["spend_pom"] = d @'
WITH raw AS (
  SELECT
    CASE WHEN REGEXP_CONTAINS(CAMPAIGN_NAME,'MLB_') THEN 'MLB'
         WHEN REGEXP_CONTAINS(CAMPAIGN_NAME,'MLM_') THEN 'MLM'
         WHEN REGEXP_CONTAINS(CAMPAIGN_NAME,'MLA_') THEN 'MLA'
         WHEN REGEXP_CONTAINS(CAMPAIGN_NAME,'MLC_') THEN 'MLC' END AS site_id,
    DATE_TRUNC(tim_day, MONTH) AS month_id, COST_LC
  FROM `meli-bi-data.SBOX_MARKETING.BT_COST_GOOGLE_DAILY`
  WHERE account_id IN (5569824421,8633263195,2507743500,2902742417)
    AND tim_day >= '${D.HIST}'
  UNION ALL
  SELECT
    CASE WHEN REGEXP_CONTAINS(CAMPAIGN_NAME,'MLB_') THEN 'MLB'
         WHEN REGEXP_CONTAINS(CAMPAIGN_NAME,'MLM_') THEN 'MLM'
         WHEN REGEXP_CONTAINS(CAMPAIGN_NAME,'MLA_') THEN 'MLA'
         WHEN REGEXP_CONTAINS(CAMPAIGN_NAME,'MLC_') THEN 'MLC' END AS site_id,
    DATE_TRUNC(TIM_DAY, MONTH) AS month_id, COST_LC
  FROM `meli-bi-data.SBOX_MARKETING.BT_COST_FACEBOOK_DAILY`
  WHERE account_id IN (993018982140477,389685073604722,720409463494481,978457163701915,1049740082792804)
    AND TIM_DAY >= '${D.HIST}'
  UNION ALL
  SELECT
    CASE WHEN REGEXP_CONTAINS(CAMPAIGN_NAME,'MLB_') THEN 'MLB'
         WHEN REGEXP_CONTAINS(CAMPAIGN_NAME,'MLM_') THEN 'MLM'
         WHEN REGEXP_CONTAINS(CAMPAIGN_NAME,'MLA_') THEN 'MLA'
         WHEN REGEXP_CONTAINS(CAMPAIGN_NAME,'MLC_') THEN 'MLC' END AS site_id,
    DATE_TRUNC(EVENT_DATE, MONTH) AS month_id, SPEND_LC AS COST_LC
  FROM `meli-bi-data.SBOX_MARKETING.BT_COST_TIKTOK_DAILY`
  WHERE advertiser_id IN (7296191154461114370,7356731484117663745,7520663504987226129)
    AND EVENT_DATE >= '${D.HIST}'
)
SELECT site_id, month_id,
  IF(month_id = '${D.CUR}', 'mtd', 'hist') AS period,
  ROUND(SUM(COST_LC),2) AS cost_lc
FROM raw WHERE site_id IN ('MLB','MLM','MLC','MLA')
GROUP BY 1,2,3 ORDER BY site_id, month_id
'@

$sqlMap["nmv_monthly"] = d @'
WITH ts AS (
  SELECT DATE_TRUNC(DT,MONTH) AS mes, SIT_SITE_ID,
    SUM(NMV_AFF) AS nmv_aff_total, SUM(NMV_TS) AS nmv_ts
  FROM `meli-bi-data.WHOWNER.BT_SC_TOTAL_SITE_AFILIADOS`
  WHERE DT >= '${D.HIST}' AND SIT_SITE_ID IN ('MLB','MLM','MLC','MLA') GROUP BY 1,2
),
beh AS (
  SELECT dt AS mes, sit_site_id, active_aff
  FROM `meli-bi-data.SBOX_AFILIADOSCOREDATA.MKT_AFFILIATE_BEHAVIOUR`
  WHERE period = 'MONTH' AND sit_site_id IN ('MLB','MLM','MLC','MLA') AND dt >= '${D.HIST}'
),
seg AS (
  SELECT DATE_TRUNC(CAST(DT AS DATE),MONTH) AS mes, SIT_SITE_ID,
    CASE WHEN SEGMENT='Key Accounts' THEN 'ka'
         WHEN SEGMENT='Long Tail'    THEN 'lt' END AS seg,
    SUM(NMV_AFF) AS nmv_aff
  FROM `meli-bi-data.WHOWNER.BT_SC_AFFILIATE_BASE`
  WHERE CAST(DT AS DATE) >= '${D.HIST}' AND SIT_SITE_ID IN ('MLB','MLM','MLC','MLA')
  GROUP BY 1,2,3 HAVING seg IS NOT NULL
)
SELECT s.mes, s.SIT_SITE_ID, s.seg, s.nmv_aff, t.nmv_ts,
  SAFE_DIVIDE(s.nmv_aff,t.nmv_ts) AS share_ts,
  b.active_aff, SAFE_DIVIDE(s.nmv_aff,b.active_aff) AS npa
FROM seg s JOIN ts t USING(mes,SIT_SITE_ID) JOIN beh b USING(mes,SIT_SITE_ID)
UNION ALL
SELECT t.mes, t.SIT_SITE_ID, 'all' AS seg, t.nmv_aff_total AS nmv_aff, t.nmv_ts,
  SAFE_DIVIDE(t.nmv_aff_total,t.nmv_ts) AS share_ts,
  b.active_aff, SAFE_DIVIDE(t.nmv_aff_total,b.active_aff) AS npa
FROM ts t JOIN beh b USING(mes,SIT_SITE_ID)
ORDER BY mes, SIT_SITE_ID, seg
'@

$sqlMap["nmv_weekly"] = d @'
WITH ts AS (
  SELECT EXTRACT(YEAR FROM DT) AS yr, EXTRACT(ISOWEEK FROM DT) AS wk,
    SIT_SITE_ID, SUM(NMV_AFF) AS nmv_aff_total, SUM(NMV_TS) AS nmv_ts
  FROM `meli-bi-data.WHOWNER.BT_SC_TOTAL_SITE_AFILIADOS`
  WHERE DT >= '${D.W8}' AND DT < '${D.CUR}'
    AND SIT_SITE_ID IN ('MLB','MLM','MLC','MLA') GROUP BY 1,2,3
),
beh AS (
  SELECT EXTRACT(YEAR FROM dt) AS yr, EXTRACT(ISOWEEK FROM dt) AS wk,
    sit_site_id, active_aff
  FROM `meli-bi-data.SBOX_AFILIADOSCOREDATA.MKT_AFFILIATE_BEHAVIOUR`
  WHERE period = 'WEEK' AND sit_site_id IN ('MLB','MLM','MLC','MLA') AND dt >= '${D.W8}'
)
SELECT t.yr, t.wk, t.SIT_SITE_ID, 'all' AS seg,
  t.nmv_aff_total AS nmv_aff, t.nmv_ts,
  SAFE_DIVIDE(t.nmv_aff_total,t.nmv_ts) AS share_ts,
  b.active_aff, SAFE_DIVIDE(t.nmv_aff_total,b.active_aff) AS npa
FROM ts t LEFT JOIN beh b USING(yr,wk,SIT_SITE_ID)
ORDER BY yr, wk, SIT_SITE_ID
'@

$sqlMap["nmv_mtd"] = d @'
WITH total AS (
  SELECT SIT_SITE_ID,
    SUM(CASE WHEN DT BETWEEN '${D.CUR}' AND '${D.YEST}' THEN NMV_AFF ELSE 0 END) AS nmv_curr,
    SUM(CASE WHEN DT BETWEEN '${D.CUR}' AND '${D.YEST}' THEN NMV_TS  ELSE 0 END) AS ts_curr,
    SUM(CASE WHEN DT BETWEEN '${D.PREV}' AND '${D.PREV_DAY}' THEN NMV_AFF ELSE 0 END) AS nmv_prev,
    SUM(CASE WHEN DT BETWEEN '${D.PREV}' AND '${D.PREV_DAY}' THEN NMV_TS  ELSE 0 END) AS ts_prev
  FROM `meli-bi-data.WHOWNER.BT_SC_TOTAL_SITE_AFILIADOS`
  WHERE DT >= '${D.PREV}' AND SIT_SITE_ID IN ('MLB','MLM','MLC','MLA') GROUP BY 1
),
lt AS (
  SELECT SIT_SITE_ID,
    SUM(CASE WHEN CAST(DT AS DATE) BETWEEN '${D.CUR}' AND '${D.YEST}' THEN NMV_AFF ELSE 0 END) AS lt_nmv_curr,
    SUM(CASE WHEN CAST(DT AS DATE) BETWEEN '${D.PREV}' AND '${D.PREV_DAY}' THEN NMV_AFF ELSE 0 END) AS lt_nmv_prev
  FROM `meli-bi-data.WHOWNER.BT_SC_AFFILIATE_BASE`
  WHERE CAST(DT AS DATE) >= '${D.PREV}'
    AND SIT_SITE_ID IN ('MLB','MLM','MLC','MLA') AND SEGMENT='Long Tail' GROUP BY 1
)
SELECT t.SIT_SITE_ID, t.nmv_curr, t.ts_curr, t.nmv_prev, t.ts_prev,
  l.lt_nmv_curr, l.lt_nmv_prev
FROM total t LEFT JOIN lt l USING(SIT_SITE_ID)
'@

$sqlMap["nmv_pacing"] = d @'
-- Para M-1 a M-6: NMV acumulado al día D del mes vs cierre total
-- Pacing ratio = nmv_at_day / nmv_full → base para proyección 6 meses
SELECT
  SIT_SITE_ID AS site,
  FORMAT_DATE('%Y-%m-%d', DATE_TRUNC(DT, MONTH)) AS month_start,
  SUM(CASE WHEN EXTRACT(DAY FROM DT) <= ${D.DAY_OF_MONTH} THEN NMV_AFF ELSE 0 END) AS nmv_at_day,
  SUM(NMV_AFF) AS nmv_full
FROM `meli-bi-data.WHOWNER.BT_SC_TOTAL_SITE_AFILIADOS`
WHERE SIT_SITE_ID IN ('MLB','MLM','MLC','MLA')
  AND DT >= '${D.M6}'
  AND DT < '${D.CUR}'
GROUP BY site, month_start
ORDER BY site, month_start
'@

$sqlMap["data_freshness"] = d @'
-- MAX fecha disponible por tabla fuente — para el tag "Datos cerrados hasta el X inclusive"
SELECT 'total_site'    AS tbl, FORMAT_DATE('%Y-%m-%d', MAX(DT)) AS max_dt
FROM `meli-bi-data.WHOWNER.BT_SC_TOTAL_SITE_AFILIADOS`
WHERE SIT_SITE_ID IN ('MLB','MLM','MLC','MLA')
UNION ALL
SELECT 'affiliate_base' AS tbl, FORMAT_DATE('%Y-%m-%d', MAX(CAST(DT AS DATE))) AS max_dt
FROM `meli-bi-data.WHOWNER.BT_SC_AFFILIATE_BASE`
WHERE SIT_SITE_ID IN ('MLB','MLM','MLC','MLA')
UNION ALL
SELECT 'attr_daily'    AS tbl, FORMAT_DATE('%Y-%m-%d', MAX(DATE(ORD_CREATED_DT))) AS max_dt
FROM `meli-bi-data.WHOWNER.BT_AFFI_SALES_ATTRIBUTION_DAILY`
WHERE SIT_SITE_ID IN ('MLB','MLM','MLC','MLA')
  AND ORD_STATUS = 'paid' AND SIT_SITE_ID = AFFILIATE_SIT_SITE_ID
UNION ALL
SELECT 'registrations' AS tbl, FORMAT_DATE('%Y-%m-%d', MAX(DATE(ds))) AS max_dt
FROM `meli-bi-data.SBOX_AFILIADOSCOREDATA.AFFILIATE_REGISTRATION_CHANNEL`
WHERE site_id IN ('MLB','MLM','MLC','MLA')
UNION ALL
SELECT 'landing'       AS tbl, FORMAT_DATE('%Y-%m-%d', MAX(DATE(ds))) AS max_dt
FROM `meli-bi-data.SBOX_AFILIADOSCOREDATA.MKT_REGISTRATION_JOURNEY`
WHERE page = 'landing'
'@

$sqlMap["act1"] = d @'
WITH register AS (
  SELECT USER_ID, SITE_ID, DATE_TRUNC(DATE(DATE_REGISTER),MONTH) AS mes_reg
  FROM `meli-bi-data.SBOX_AFILIADOSCOREDATA.AFFILIATE_AFFILIATE`
  WHERE DATE_REGISTER >= '${D.HIST}' AND SITE_ID IN ('MLB','MLM','MLC','MLA')
),
first_sale AS (
  SELECT SIT_SITE_ID, AFFILIATE_ID,
    DATE_TRUNC(MIN(ORD_CREATED_DT),MONTH) AS mes_primera_venta
  FROM `meli-bi-data.WHOWNER.BT_AFFI_SALES_ATTRIBUTION_DAILY`
  WHERE SIT_SITE_ID IN ('MLB','MLM','MLC','MLA') AND ORD_STATUS='paid'
    AND SIT_SITE_ID=AFFILIATE_SIT_SITE_ID AND ORD_CREATED_DT >= '${D.HIST}'
    AND ((ORD_CREATED_DT >= '${D.ENIGMA}' AND NMV_ENIGMA_TOTAL_AMT_LC>0)
      OR (ORD_CREATED_DT<'${D.ENIGMA}' AND NMV_TD7DCALIB_TOTAL_AMT_LC>0))
  GROUP BY 1,2
)
SELECT r.SITE_ID, r.mes_reg,
  COUNT(DISTINCT r.USER_ID) AS total_registros,
  COUNT(DISTINCT IF(f.mes_primera_venta=r.mes_reg, r.USER_ID, NULL)) AS activaron_mismo_mes,
  ROUND(SAFE_DIVIDE(COUNT(DISTINCT IF(f.mes_primera_venta=r.mes_reg,r.USER_ID,NULL)),
    COUNT(DISTINCT r.USER_ID))*100,1) AS pct_activaron
FROM register r
LEFT JOIN first_sale f ON r.USER_ID=f.AFFILIATE_ID AND r.SITE_ID=f.SIT_SITE_ID
GROUP BY 1,2 ORDER BY SITE_ID, mes_reg
'@

$sqlMap["act2"] = d @'
WITH register AS (
  SELECT USER_ID, SITE_ID, DATE_TRUNC(DATE(DATE_REGISTER),MONTH) AS mes_reg,
    DATE(TIMESTAMP_SUB(TIMESTAMP(DATE_REGISTER), INTERVAL 4 HOUR)) AS date_reg_adj
  FROM `meli-bi-data.SBOX_AFILIADOSCOREDATA.AFFILIATE_AFFILIATE`
  WHERE DATE_REGISTER >= '${D.HIST}' AND SITE_ID IN ('MLB','MLM','MLC','MLA')
),
first_sale AS (
  SELECT SIT_SITE_ID, AFFILIATE_ID, MIN(ORD_CREATED_DT) AS first_sale_dt
  FROM `meli-bi-data.WHOWNER.BT_AFFI_SALES_ATTRIBUTION_DAILY`
  WHERE SIT_SITE_ID IN ('MLB','MLM','MLC','MLA') AND ORD_STATUS='paid'
    AND SIT_SITE_ID=AFFILIATE_SIT_SITE_ID AND ORD_CREATED_DT >= '${D.HIST}'
    AND ((ORD_CREATED_DT >= '${D.ENIGMA}' AND NMV_ENIGMA_TOTAL_AMT_LC>0)
      OR (ORD_CREATED_DT<'${D.ENIGMA}' AND NMV_TD7DCALIB_TOTAL_AMT_LC>0))
  GROUP BY 1,2
),
seg AS (
  SELECT r.SITE_ID, r.mes_reg,
    CASE WHEN f.first_sale_dt IS NULL THEN 'no_act'
         WHEN DATE_DIFF(f.first_sale_dt,r.date_reg_adj,DAY)<=7  THEN 'd7'
         WHEN DATE_DIFF(f.first_sale_dt,r.date_reg_adj,DAY)<=15 THEN 'd15'
         WHEN DATE_DIFF(f.first_sale_dt,r.date_reg_adj,DAY)<=30 THEN 'd30'
         WHEN DATE_DIFF(f.first_sale_dt,r.date_reg_adj,DAY)<=45 THEN 'd45'
         ELSE 'd46p' END AS cohort
  FROM register r
  LEFT JOIN first_sale f ON r.USER_ID=f.AFFILIATE_ID AND r.SITE_ID=f.SIT_SITE_ID
)
SELECT SITE_ID, mes_reg, COUNT(*) AS total,
  ROUND(COUNTIF(cohort='d7') /COUNT(*)*100,1) AS pct_d7,
  ROUND(COUNTIF(cohort='d15')/COUNT(*)*100,1) AS pct_d15,
  ROUND(COUNTIF(cohort='d30')/COUNT(*)*100,1) AS pct_d30,
  ROUND(COUNTIF(cohort='d45')/COUNT(*)*100,1) AS pct_d45,
  ROUND(COUNTIF(cohort='d46p')/COUNT(*)*100,1) AS pct_d46p,
  ROUND(COUNTIF(cohort='no_act')/COUNT(*)*100,1) AS pct_no_act
FROM seg GROUP BY 1,2 ORDER BY SITE_ID, mes_reg
'@

$sqlMap["churn"] = d @'
WITH monthly_active AS (
  SELECT SIT_SITE_ID, DATE_TRUNC(ORD_CREATED_DT,MONTH) AS month, AFFILIATE_ID
  FROM `meli-bi-data.WHOWNER.BT_AFFI_SALES_ATTRIBUTION_DAILY`
  WHERE ORD_STATUS='paid' AND SIT_SITE_ID IN ('MLB','MLM','MLC','MLA')
    AND SIT_SITE_ID=AFFILIATE_SIT_SITE_ID AND ORD_CREATED_DT >= '${D.DEEP}'
    AND ((ORD_CREATED_DT >= '${D.ENIGMA}' AND NMV_ENIGMA_TOTAL_AMT_LC>0)
      OR (ORD_CREATED_DT<'${D.ENIGMA}' AND NMV_TD7DCALIB_TOTAL_AMT_LC>0))
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
    COUNTIF(prev.is_new) AS new_prev,
    COUNT(DISTINCT IF(curr.AFFILIATE_ID IS NULL,prev.AFFILIATE_ID,NULL)) AS churned,
    COUNT(DISTINCT IF(curr.AFFILIATE_ID IS NULL AND prev.is_new,prev.AFFILIATE_ID,NULL)) AS churned_new
  FROM flagged prev
  LEFT JOIN monthly_active curr
    ON prev.AFFILIATE_ID=curr.AFFILIATE_ID AND prev.SIT_SITE_ID=curr.SIT_SITE_ID
    AND curr.month=DATE_ADD(prev.month,INTERVAL 1 MONTH)
  GROUP BY 1,2
)
SELECT month, SIT_SITE_ID, active_prev, churned, churned_new,
  ROUND(SAFE_DIVIDE(churned_new,active_prev)*100,2) AS pct_churn_new
FROM metrics WHERE month >= '${D.HIST}' ORDER BY SIT_SITE_ID, month
'@

$sqlMap["churn_comp"] = d @'
WITH monthly_active AS (
  SELECT SIT_SITE_ID, DATE_TRUNC(ORD_CREATED_DT,MONTH) AS month, AFFILIATE_ID
  FROM `meli-bi-data.WHOWNER.BT_AFFI_SALES_ATTRIBUTION_DAILY`
  WHERE ORD_STATUS='paid' AND SIT_SITE_ID IN ('MLB','MLM','MLC','MLA')
    AND SIT_SITE_ID=AFFILIATE_SIT_SITE_ID AND ORD_CREATED_DT >= '${D.DEEP}'
    AND ((ORD_CREATED_DT >= '${D.ENIGMA}' AND NMV_ENIGMA_TOTAL_AMT_LC>0)
      OR (ORD_CREATED_DT<'${D.ENIGMA}' AND NMV_TD7DCALIB_TOTAL_AMT_LC>0))
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
FROM churners WHERE churn_month >= '${D.HIST}' GROUP BY 1,2 ORDER BY 1,2
'@

$sqlMap["churn_mtd"] = d @'
WITH window_sales AS (
  SELECT SIT_SITE_ID, AFFILIATE_ID,
    MAX(CASE WHEN DATE(ORD_CREATED_DT) BETWEEN '${D.CUR}' AND '${D.YEST}' THEN 1 ELSE 0 END) AS in_curr,
    MAX(CASE WHEN DATE(ORD_CREATED_DT) BETWEEN '${D.PREV}' AND '${D.PREV_DAY}' THEN 1 ELSE 0 END) AS in_prev,
    MAX(CASE WHEN DATE_TRUNC(ORD_CREATED_DT,MONTH)='${D.PREV}' THEN 1 ELSE 0 END) AS in_apr_full,
    MAX(CASE WHEN DATE_TRUNC(ORD_CREATED_DT,MONTH)='${D.M2}' THEN 1 ELSE 0 END) AS in_mar_full,
    MIN(DATE_TRUNC(ORD_CREATED_DT,MONTH)) AS first_month,
    COUNT(DISTINCT CASE WHEN DATE_TRUNC(ORD_CREATED_DT,MONTH)<='${D.PREV}'
      THEN DATE_TRUNC(ORD_CREATED_DT,MONTH) END) AS months_hist
  FROM `meli-bi-data.WHOWNER.BT_AFFI_SALES_ATTRIBUTION_DAILY`
  WHERE ORD_STATUS='paid' AND SIT_SITE_ID=AFFILIATE_SIT_SITE_ID
    AND SIT_SITE_ID IN ('MLB','MLM','MLC','MLA') AND ORD_CREATED_DT >= '${D.DEEP}'
    AND ((ORD_CREATED_DT >= '${D.ENIGMA}' AND NMV_ENIGMA_TOTAL_AMT_LC>0)
      OR (ORD_CREATED_DT<'${D.ENIGMA}' AND NMV_TD7DCALIB_TOTAL_AMT_LC>0))
  GROUP BY 1,2
)
SELECT SIT_SITE_ID,
  COUNT(DISTINCT IF(in_curr=0 AND first_month='${D.PREV}' AND in_apr_full=1,AFFILIATE_ID,NULL)) AS curr_churned_new,
  COUNT(DISTINCT IF(in_apr_full=1,AFFILIATE_ID,NULL)) AS apr_active_base,
  ROUND(SAFE_DIVIDE(
    COUNT(DISTINCT IF(in_curr=0 AND first_month='${D.PREV}' AND in_apr_full=1,AFFILIATE_ID,NULL)),
    COUNT(DISTINCT IF(in_apr_full=1,AFFILIATE_ID,NULL)))*100,2) AS pct_churn_new_curr,
  COUNT(DISTINCT IF(in_prev=0 AND first_month='${D.M2}' AND in_mar_full=1,AFFILIATE_ID,NULL)) AS prev_churned_new,
  COUNT(DISTINCT IF(in_mar_full=1,AFFILIATE_ID,NULL)) AS mar_active_base,
  ROUND(SAFE_DIVIDE(
    COUNT(DISTINCT IF(in_prev=0 AND first_month='${D.M2}' AND in_mar_full=1,AFFILIATE_ID,NULL)),
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
'@

# ==== LAUNCH ALL 17 JOBS IN PARALLEL =========================================
Write-Host "Launching $($sqlMap.Count) queries in parallel via bq CLI..." -ForegroundColor Cyan
$startTime = Get-Date

$jobBlock = {
    param([string]$sql, [string]$name)
    try {
        $tmp = [IO.Path]::GetTempFileName()
        $enc = New-Object System.Text.UTF8Encoding $false
        [IO.File]::WriteAllText($tmp, $sql, $enc)
        $raw = & cmd /c "bq query --format=json --use_legacy_sql=false --quiet --max_rows=500000 < `"$tmp`"" 2>&1
        [IO.File]::Delete($tmp)
        $ok = ($LASTEXITCODE -eq 0)
        $jsonStr = if ($ok) { ($raw -join '') } else { '[]' }
        $errStr  = if (-not $ok) { ($raw -join ' ') } else { '' }
        return [PSCustomObject]@{ name=$name; ok=$ok; json=$jsonStr; error=$errStr }
    } catch {
        return [PSCustomObject]@{ name=$name; ok=$false; json='[]'; error=$_.Exception.Message }
    }
}

$jobs = @{}
foreach ($kv in $sqlMap.GetEnumerator()) {
    $jobs[$kv.Key] = Start-Job -Name $kv.Key -ScriptBlock $jobBlock -ArgumentList $kv.Value, $kv.Key
}
Write-Host "All $($jobs.Count) jobs launched — waiting for results..."

# Collect results as each job finishes
$rawResults = @{}
$jobs.Values | Wait-Job | ForEach-Object {
    $r = Receive-Job $_
    $sec = [Math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
    $status = if ($r.ok) { "OK  " } else { "FAIL" }
    $detail = if ($r.ok) { "$([Math]::Round($r.json.Length/1024,0)) KB" } else { $r.error.Substring(0,[Math]::Min(80,$r.error.Length)) }
    Write-Host "  [${sec}s] $status $($r.name) — $detail"
    $rawResults[$r.name] = $r
    Remove-Job $_ -Force
}

$totalSec = [Math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
Write-Host ""
Write-Host "All queries done in ${totalSec}s" -ForegroundColor Cyan

# ==== PARSE BQ JSON (strings -> numbers where possible) ======================
function Parse-BQResult([string]$jsonStr) {
    if (-not $jsonStr -or $jsonStr -eq '[]' -or $jsonStr -eq '') { return ,@() }
    try {
        $rows = $jsonStr | ConvertFrom-Json
        if (-not $rows) { return ,@() }
        if ($rows -isnot [System.Array]) { $rows = @($rows) }
        $out = $rows | ForEach-Object {
            $obj = [ordered]@{}
            $_.PSObject.Properties | ForEach-Object {
                $v = $_.Value
                $n = 0.0
                $key = $_.Name.ToLower()   # normalizar a minúsculas: BQ puede devolver SIT_SITE_ID etc.
                if ($null -ne $v -and "$v" -ne '' -and
                    [double]::TryParse("$v",
                        [System.Globalization.NumberStyles]::Any,
                        [System.Globalization.CultureInfo]::InvariantCulture,
                        [ref]$n)) {
                    $obj[$key] = $n
                } else {
                    $obj[$key] = $v
                }
            }
            [PSCustomObject]$obj
        }
        return ,$out
    } catch {
        Write-Host "  Parse error ($($_.Exception.Message))" -ForegroundColor Yellow
        return ,@()
    }
}

# ==== BUILD SNAPSHOT =========================================================
Write-Host "Building snapshot..." -ForegroundColor Cyan

$tsNow   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
$dispNow = (Get-Date).ToString("dd/MM/yyyy hh:mm tt").Replace("AM","a. m.").Replace("PM","p. m.")

$data = [ordered]@{
    behaviour     = (Parse-BQResult $rawResults["behaviour"].json)
    beh_mtd       = (Parse-BQResult $rawResults["beh_mtd"].json)
    beh_pacing    = (Parse-BQResult $rawResults["beh_pacing"].json)
    qr_rolling    = (Parse-BQResult $rawResults["qr_rolling"].json)
    registrations = (Parse-BQResult $rawResults["registrations"].json)
    reg_mtd         = (Parse-BQResult $rawResults["reg_mtd"].json)
    reg_pacing      = (Parse-BQResult $rawResults["reg_pacing"].json)
    landing_traffic = (Parse-BQResult $rawResults["landing_traffic"].json)
    landing_pacing  = (Parse-BQResult $rawResults["landing_pacing"].json)
    spend_pom       = (Parse-BQResult $rawResults["spend_pom"].json)
    nmv_monthly   = (Parse-BQResult $rawResults["nmv_monthly"].json)
    nmv_weekly    = (Parse-BQResult $rawResults["nmv_weekly"].json)
    nmv_mtd       = (Parse-BQResult $rawResults["nmv_mtd"].json)
    nmv_pacing      = (Parse-BQResult $rawResults["nmv_pacing"].json)
    data_freshness  = (Parse-BQResult $rawResults["data_freshness"].json)
    act1            = (Parse-BQResult $rawResults["act1"].json)
    act2          = (Parse-BQResult $rawResults["act2"].json)
    churn         = (Parse-BQResult $rawResults["churn"].json)
    churn_comp    = (Parse-BQResult $rawResults["churn_comp"].json)
    churn_mtd     = (Parse-BQResult $rawResults["churn_mtd"].json)
}

$snapshot = [ordered]@{ savedAt=$tsNow; savedAtDisplay=$dispNow; data=$data }
$snapshotJson = $snapshot | ConvertTo-Json -Depth 20 -Compress
$kb = [Math]::Round($snapshotJson.Length / 1024, 1)
Write-Host "Snapshot: ${kb} KB"
$data.GetEnumerator() | ForEach-Object {
    $cnt = if ($_.Value) { @($_.Value).Count } else { 0 }
    Write-Host "  $($_.Key.PadRight(14)) $cnt rows"
}

# ==== INJECT INTO HTML =======================================================
Write-Host ""
Write-Host "Injecting into HTML..." -ForegroundColor Cyan
$htmlPath = "C:\Users\lcorales\Downloads\Claude\affiliates-dashboard-grid.html"
$html = [IO.File]::ReadAllText($htmlPath, [Text.Encoding]::UTF8)
$newTag = "<script>window.__PRELOADED__ = $snapshotJson;</script>"
$html = [Text.RegularExpressions.Regex]::Replace(
    $html,
    '<script>window\.__PRELOADED__[^<]*</script>|<!-- PRELOADED_SNAPSHOT_HERE -->',
    $newTag
)
[IO.File]::WriteAllText($htmlPath, $html, [Text.Encoding]::UTF8)
Write-Host "HTML updated ($([Math]::Round(($html.Length)/1024,0)) KB)."

# ==== UPLOAD TO GRID (presigned 3-step flow para archivos grandes) ============
Write-Host "Uploading to Grid..." -ForegroundColor Cyan
# Multipart directo con timeout extendido (presigned proxy tenia bug en backend storage)
$cfg = '{"skill_version":"3.6.3","doc_id":"01KRE46H4452DPPVSYM5BKXJ14"}'
$tmpCfg = [IO.Path]::GetTempFileName()
[IO.File]::WriteAllText($tmpCfg, $cfg, [System.Text.Encoding]::ASCII)
$gridResp = & "C:\Windows\System32\curl.exe" -s --max-time 300 -X POST "https://grid.melioffice.com/api/v1/engine/run" -F "config=<$tmpCfg" -F "file=@$htmlPath"
Remove-Item $tmpCfg -ErrorAction SilentlyContinue
$parsed = $gridResp | ConvertFrom-Json
if ($parsed.ok) {
    Write-Host "Grid upload OK: $($parsed.view_url)" -ForegroundColor Green
} else {
    Write-Host "Grid upload FAILED" -ForegroundColor Red
    Write-Host $gridResp
}

# ==== PACING BACKTEST AUTO-UPDATE ============================================
# Trigger: primer corrida del mes con >= 2 dias habiles transcurridos
$pacingStateFile = "C:\Users\lcorales\Downloads\Claude\aff-corp-growth-repo\pacing_last_month.txt"
$pacingHtmlPath  = "C:\Users\lcorales\Downloads\Claude\pacing-analysis-mayo26.html"
$pacingDocId     = "01KSR5A3JWVWGGS9NPC5ZR9XA2"

$lastPacingMonth = if (Test-Path $pacingStateFile) { (Get-Content $pacingStateFile -Raw).Trim() } else { "" }

# Contar dias habiles transcurridos desde el 1 del mes actual
$bizDays = 0
$checkD = $CUR_DT
while ($checkD -lt $now.Date) {
    if ($checkD.DayOfWeek -ne [DayOfWeek]::Saturday -and $checkD.DayOfWeek -ne [DayOfWeek]::Sunday) {
        $bizDays++
    }
    $checkD = $checkD.AddDays(1)
}

if ($lastPacingMonth -ne $PREV -and $bizDays -ge 2) {
    Write-Host ""
    Write-Host "=== PACING BACKTEST — actualizando con $($PREV_DT.ToString('MMMM yyyy')) cerrado ===" -ForegroundColor Magenta
    Write-Host "  Dias habiles desde el 1/$($CUR_DT.Month): $bizDays (>= 2 — trigger OK)"

    # Query: activos MTD acumulados dia a dia para 6 meses hist + mes objetivo (PREV)
    $hist1 = $CUR_DT.AddMonths(-7).ToString("yyyy-MM-dd")  # 7 meses atras = inicio hist
    $hist6 = $PREV  # mes objetivo = M-1

    $pacingSql = @"
WITH primera_venta AS (
  SELECT
    SIT_SITE_ID,
    DATE_TRUNC(DATE(ORD_CREATED_DT), MONTH) AS mes,
    AFFILIATE_ID,
    MIN(EXTRACT(DAY FROM DATE(ORD_CREATED_DT))) AS primer_dia
  FROM ``meli-bi-data.WHOWNER.BT_AFFI_SALES_ATTRIBUTION_DAILY``
  WHERE DATE(ORD_CREATED_DT) BETWEEN '$hist1' AND '$($PREV_DT.AddMonths(1).AddDays(-1).ToString("yyyy-MM-dd"))'
    AND ORD_STATUS = 'paid'
    AND SIT_SITE_ID = AFFILIATE_SIT_SITE_ID
    AND SIT_SITE_ID IN ('MLB','MLM','MLC','MLA')
    AND CASE WHEN DATE(ORD_CREATED_DT) >= '$ENIGMA' THEN NMV_ENIGMA_TOTAL_AMT_LC
             ELSE NMV_TD7DCALIB_TOTAL_AMT_LC END > 0
  GROUP BY 1,2,3
),
nuevos_por_dia AS (
  SELECT SIT_SITE_ID, mes, primer_dia AS dia, COUNT(*) AS nuevos
  FROM primera_venta GROUP BY 1,2,3
)
SELECT
  SIT_SITE_ID,
  FORMAT_DATE('%Y-%m-%d', mes) AS mes,
  dia,
  SUM(nuevos) OVER (PARTITION BY SIT_SITE_ID, mes ORDER BY dia) AS activos_mtd
FROM nuevos_por_dia
ORDER BY SIT_SITE_ID, mes, dia
"@

    $tmpPacingSql = [IO.Path]::GetTempFileName() + ".sql"
    [System.IO.File]::WriteAllText($tmpPacingSql, $pacingSql, [System.Text.Encoding]::ASCII)
    Write-Host "  Corriendo BQ pacing..."
    $pacingCsv = & cmd /c "bq query --use_legacy_sql=false --format=csv --max_rows=3000 --project_id=meli-bi-data --label=origin:affiliates-pacing-backtest < `"$tmpPacingSql`"" 2>&1
    Remove-Item $tmpPacingSql -ErrorAction SilentlyContinue

    $pacingRows = $pacingCsv | Where-Object { $_ -match "^(MLB|MLM|MLC|MLA)" }
    Write-Host "  BQ rows: $($pacingRows.Count)"

    if ($pacingRows.Count -gt 100) {
        # Procesar: armar estructura por site y mes
        $byMes = @{}
        $pacingRows | ForEach-Object {
            $parts = $_ -split ","
            $site = $parts[0]; $mes = $parts[1]; $dia = [int]$parts[2]; $activos = [int]$parts[3]
            if (-not $byMes["$site|$mes"]) { $byMes["$site|$mes"] = @() }
            $byMes["$site|$mes"] += [PSCustomObject]@{ dia = $dia; activos = $activos }
        }

        # Identificar meses historicos y mes objetivo
        $meses = $pacingRows | ForEach-Object { ($_ -split ",")[1] } | Sort-Object -Unique
        $mesObjetivo = $PREV  # 2026-05-01
        $mesHist = $meses | Where-Object { $_ -ne $mesObjetivo }

        # Para cada site: calcular avgPacing por dia y proyeccion
        $rawJson = @()
        $siteCloses = @{}
        $SITES = @("MLB","MLM","MLC","MLA")
        foreach ($site in $SITES) {
            # Real close = max dia del mes objetivo
            $objRows = $byMes["$site|$mesObjetivo"]
            if (-not $objRows) { continue }
            $realClose = ($objRows | Sort-Object dia | Select-Object -Last 1).activos
            $siteCloses[$site] = $realClose

            # Calculates para cada dia del mes objetivo
            $maxDia = ($objRows | Measure-Object -Property dia -Maximum).Maximum
            for ($d = 1; $d -le $maxDia; $d++) {
                $actObj = ($objRows | Where-Object { $_.dia -eq $d }).activos
                if ($null -eq $actObj) { $actObj = 0 }

                # avgPacing = promedio de (activos_at_d / close) sobre meses historicos
                $ratios = @()
                foreach ($mh in $mesHist) {
                    $mhRows = $byMes["$site|$mh"]
                    if (-not $mhRows) { continue }
                    $closeH = ($mhRows | Sort-Object dia | Select-Object -Last 1).activos
                    if ($closeH -le 0) { continue }
                    $actH = ($mhRows | Where-Object { $_.dia -le $d } | Sort-Object dia | Select-Object -Last 1).activos
                    if ($null -eq $actH) { $actH = 0 }
                    $ratios += [double]$actH / [double]$closeH
                }
                $avgP = if ($ratios.Count -gt 0) { ($ratios | Measure-Object -Average).Average } else { 0 }
                $proy = if ($avgP -gt 0) { [math]::Round($actObj / $avgP) } else { 0 }

                $rawJson += "{`"site`":`"$site`",`"dia`":$d,`"activos_may`":$actObj,`"avg_p`":$([math]::Round($avgP,6)),`"proyeccion`":$proy,`"real_mtd`":$realClose}"
            }
        }

        # Cargar HTML actual y reemplazar el bloque RAW
        $pacingHtml = [IO.File]::ReadAllText($pacingHtmlPath, [Text.Encoding]::UTF8)
        $rawBlock = "const RAW = [`n" + ($rawJson -join ",`n") + "`n];"
        $pacingHtml = $pacingHtml -replace 'const RAW = \[[\s\S]*?\];', $rawBlock

        # Actualizar referencias de mes objetivo
        $prevMonthName = $PREV_DT.ToString("MMMM yyyy")  # ej. "mayo 2026"
        $DAYS_IN_MONTH = [DateTime]::DaysInMonth($PREV_DT.Year, $PREV_DT.Month)
        $pacingHtml = $pacingHtml -replace 'const DAYS = Array\.from\(\{length:\d+\}', "const DAYS = Array.from({length:$DAYS_IN_MONTH}"

        [IO.File]::WriteAllText($pacingHtmlPath, $pacingHtml, [Text.Encoding]::UTF8)
        Write-Host "  HTML actualizado."

        # Upload a Grid
        $pacingCfg = "{`"skill_version`":`"3.6.0`",`"doc_id`":`"$pacingDocId`",`"skip_version_check`":true}"
        $tmpPacingCfg = [IO.Path]::GetTempFileName()
        [IO.File]::WriteAllText($tmpPacingCfg, $pacingCfg, [System.Text.Encoding]::ASCII)
        $pacingResp = & "C:\Windows\System32\curl.exe" -s --max-time 300 -X POST "https://grid.melioffice.com/api/v1/engine/run" -F "config=<$tmpPacingCfg" -F "file=@$pacingHtmlPath"
        Remove-Item $tmpPacingCfg -ErrorAction SilentlyContinue
        $pacingParsed = $pacingResp | ConvertFrom-Json
        if ($pacingParsed.ok) {
            Write-Host "  Pacing Grid OK: $($pacingParsed.view_url)" -ForegroundColor Green
            Set-Content -Path $pacingStateFile -Value $PREV -Encoding ASCII
        } else {
            Write-Host "  Pacing Grid FAILED: $($pacingParsed.error)" -ForegroundColor Red
        }
    } else {
        Write-Host "  BQ pacing returned too few rows — skip update." -ForegroundColor Yellow
    }
} else {
    if ($lastPacingMonth -eq $PREV) {
        Write-Host "  Pacing backtest up to date (last: $lastPacingMonth)." -ForegroundColor DarkGray
    } else {
        Write-Host "  Pacing: esperando $([math]::Max(0, 2 - $bizDays)) dia(s) habil(es) mas (hoy: $bizDays de 2)." -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host "=== DONE in ${totalSec}s ===" -ForegroundColor Cyan
