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
$pdDay   = [Math]::Min($now.Day - 1, $prevLast)
$PREV_DAY = (Get-Date -Year $PREV_DT.Year -Month $PREV_DT.Month -Day $pdDay).ToString("yyyy-MM-dd")
$dow = [int]$now.DayOfWeek; $dtm = if($dow -eq 0){6}else{$dow-1}
$W8  = $now.AddDays(-$dtm - 56).ToString("yyyy-MM-dd")
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

# ==== UPLOAD TO GRID =========================================================
Write-Host "Uploading to Grid..." -ForegroundColor Cyan
$config = '{"skill_version":"3.6.0","doc_id":"01KRE46H4452DPPVSYM5BKXJ14","skip_version_check":true}'
$tmpCfg = [IO.Path]::GetTempFileName()
[IO.File]::WriteAllText($tmpCfg, $config)
$gridResp = & "C:\Windows\System32\curl.exe" -s -X POST "https://grid.melioffice.com/api/v1/engine/run" -F "config=<$tmpCfg" -F "file=@$htmlPath"
Remove-Item $tmpCfg -ErrorAction SilentlyContinue

$parsed = $gridResp | ConvertFrom-Json
if ($parsed.ok) {
    Write-Host "Grid upload OK: $($parsed.view_url)" -ForegroundColor Green
} else {
    Write-Host "Grid upload FAILED" -ForegroundColor Red
    Write-Host $gridResp
}


# ==== PACING BACKTEST — actualiza el grid de metodología el 1er run del mes nuevo ====
# Detecta si $PREV (mes recién cerrado) cambió respecto al último backtest corrido.
# Si cambió, re-corre el backtest sobre el mes recién cerrado usando 6 meses históricos.
$pacingStateFile = "C:\Users\lcorales\Downloads\Claude\aff-corp-growth-repo\pacing_last_month.txt"
$pacingHtmlPath  = "C:\Users\lcorales\Downloads\Claude\pacing-analysis-mayo26.html"
$pacingDocId     = "01KSR5A3JWVWGGS9NPC5ZR9XA2"

$lastPacingMonth = if (Test-Path $pacingStateFile) { (Get-Content $pacingStateFile -Raw).Trim() } else { "" }

if ($lastPacingMonth -ne $PREV) {
    Write-Host ""
    Write-Host "=== PACING BACKTEST — nuevo mes detectado ($PREV) ===" -ForegroundColor Magenta

    # Mes target = $PREV (recién cerrado). Histórico = $M2..$M7 (6 meses)
    $targetMonth   = $PREV          # ej. "2026-05-01"
    $targetMonthDT = [DateTime]$targetMonth
    $daysInTarget  = [DateTime]::DaysInMonth($targetMonthDT.Year, $targetMonthDT.Month)
    $targetEnd     = $targetMonthDT.AddMonths(1).AddDays(-1).ToString("yyyy-MM-dd")
    $histStart     = $CUR_DT.AddMonths(-7).ToString("yyyy-MM-dd")  # inicio del rango histórico
    $enigmaDate    = $ENIGMA

    $monthNames = @{
        "01"="Enero";"02"="Febrero";"03"="Marzo";"04"="Abril";"05"="Mayo";"06"="Junio";
        "07"="Julio";"08"="Agosto";"09"="Septiembre";"10"="Octubre";"11"="Noviembre";"12"="Diciembre"
    }
    $targetMonthName = $monthNames[$targetMonthDT.ToString("MM")] + " " + $targetMonthDT.Year
    $histStartDT     = $CUR_DT.AddMonths(-7)
    $histEndDT       = $CUR_DT.AddMonths(-2)
    $histLabel       = ($monthNames[$histStartDT.ToString("MM")].Substring(0,3).ToLower() + "-" + ($histStartDT.Year % 100).ToString("00")) + " a " + ($monthNames[$histEndDT.ToString("MM")].Substring(0,3).ToLower() + "-" + ($histEndDT.Year % 100).ToString("00"))

    # ---- SQL: backtest sobre $targetMonth con 6 meses históricos ($M2..$M7) ----
    $pacingSql = @"
WITH all_sales AS (
  SELECT DISTINCT SIT_SITE_ID, AFFILIATE_ID,
    DATE(ORD_CREATED_DT) AS sale_date,
    DATE_TRUNC(DATE(ORD_CREATED_DT), MONTH) AS sale_month
  FROM ``meli-bi-data.WHOWNER.BT_AFFI_SALES_ATTRIBUTION_DAILY``
  WHERE ORD_STATUS = 'paid'
    AND SIT_SITE_ID = AFFILIATE_SIT_SITE_ID
    AND SIT_SITE_ID IN ('MLB','MLM','MLC','MLA')
    AND ORD_CREATED_DT >= '$histStart'
    AND ORD_CREATED_DT <= '$targetEnd'
    AND ((ORD_CREATED_DT >= '$enigmaDate' AND NMV_ENIGMA_TOTAL_AMT_LC > 0)
      OR (ORD_CREATED_DT < '$enigmaDate' AND NMV_TD7DCALIB_TOTAL_AMT_LC > 0))
),
target_close AS (
  SELECT SIT_SITE_ID, COUNT(DISTINCT AFFILIATE_ID) AS real_close
  FROM all_sales WHERE sale_month = DATE '$targetMonth' GROUP BY 1
),
hist_months AS (
  SELECT DATE '$M2' AS m UNION ALL SELECT DATE '$M3' UNION ALL
  SELECT DATE '$M4' UNION ALL SELECT DATE '$M5' UNION ALL
  SELECT DATE '$M6' UNION ALL SELECT DATE '$M7'
),
hist_close AS (
  SELECT s.SIT_SITE_ID, h.m AS month_start, COUNT(DISTINCT s.AFFILIATE_ID) AS close_total
  FROM all_sales s JOIN hist_months h ON s.sale_month = h.m GROUP BY 1, 2
),
days AS (SELECT day FROM UNNEST(GENERATE_ARRAY(1, $daysInTarget)) AS day),
hist_at_day AS (
  SELECT h.m AS month_start, d.day, s.SIT_SITE_ID,
    COUNT(DISTINCT s.AFFILIATE_ID) AS activos_at_day
  FROM hist_months h CROSS JOIN days d
  JOIN all_sales s ON s.sale_month = h.m AND EXTRACT(DAY FROM s.sale_date) <= d.day
  GROUP BY 1, 2, 3
),
avg_pacing AS (
  SELECT ad.day, ad.SIT_SITE_ID,
    AVG(SAFE_DIVIDE(ad.activos_at_day, cl.close_total)) AS avg_p
  FROM hist_at_day ad
  JOIN hist_close cl ON ad.month_start = cl.month_start AND ad.SIT_SITE_ID = cl.SIT_SITE_ID
  GROUP BY 1, 2
),
target_at_day AS (
  SELECT d.day, s.SIT_SITE_ID, COUNT(DISTINCT s.AFFILIATE_ID) AS activos_target
  FROM days d
  JOIN all_sales s ON s.sale_month = DATE '$targetMonth'
    AND EXTRACT(DAY FROM s.sale_date) <= d.day
  GROUP BY 1, 2
)
SELECT ad.SIT_SITE_ID AS site, ad.day, ad.activos_target,
  ROUND(hr.avg_p, 6) AS avg_p,
  ROUND(SAFE_DIVIDE(ad.activos_target, hr.avg_p)) AS proyeccion,
  tc.real_close
FROM target_at_day ad
JOIN avg_pacing hr ON ad.day = hr.day AND ad.SIT_SITE_ID = hr.SIT_SITE_ID
JOIN target_close tc ON ad.SIT_SITE_ID = tc.SIT_SITE_ID
ORDER BY ad.SIT_SITE_ID, ad.day
"@

    $tmpPacingSql = [IO.Path]::GetTempFileName()
    $enc = New-Object System.Text.UTF8Encoding $false
    [IO.File]::WriteAllText($tmpPacingSql, $pacingSql, $enc)

    Write-Host "  Running pacing backtest query for $targetMonthName..." -ForegroundColor Magenta
    $pacingRaw = & cmd /c "bq query --format=csv --use_legacy_sql=false --quiet --max_rows=500 < `"$tmpPacingSql`"" 2>&1
    [IO.File]::Delete($tmpPacingSql)

    if ($LASTEXITCODE -ne 0 -or $pacingRaw -match '^Error') {
        Write-Host "  Pacing backtest FAILED: $pacingRaw" -ForegroundColor Red
    } else {
        # ---- Parsear CSV y construir JSON ----
        $pacingLines = ($pacingRaw -join "`n").Trim() -split "`n" | Select-Object -Skip 1 | Where-Object { $_ -match '\S' }
        $rawJson = "["
        $first = $true
        foreach ($line in $pacingLines) {
            $cols = $line -split ","
            if ($cols.Count -lt 6) { continue }
            $site    = $cols[0].Trim()
            $dia     = $cols[1].Trim()
            $activos = $cols[2].Trim()
            $avgp    = $cols[3].Trim()
            $proy    = $cols[4].Trim()
            $real    = $cols[5].Trim()
            if (-not $first) { $rawJson += "," }
            $rawJson += "{`"site`":`"$site`",`"dia`":$dia,`"activos_apr`":$activos,`"avg_p`":$avgp,`"proyeccion`":$proy,`"real_mtd`":$real}"
            $first = $false
        }
        $rawJson += "]"

        # ---- Calcular stats por site para cards y headers ----
        $siteStats = @{}
        $rows = $pacingLines | ForEach-Object {
            $c = $_ -split ","
            if ($c.Count -ge 6) { [PSCustomObject]@{ site=$c[0].Trim(); dia=[int]$c[1]; proy=[double]$c[4]; real=[double]$c[5] } }
        }
        foreach ($s in @('MLB','MLM','MLC','MLA')) {
            $sr = $rows | Where-Object { $_.site -eq $s }
            $rc = ($sr | Select-Object -First 1).real
            $d15 = ($sr | Where-Object { $_.dia -eq 15 } | Select-Object -First 1)
            $d27 = ($sr | Where-Object { $_.dia -eq 27 } | Select-Object -First 1)
            if (-not $d15) { $d15 = ($sr | Select-Object -Last 1) }
            if (-not $d27) { $d27 = ($sr | Select-Object -Last 1) }
            $e15 = if ($rc -gt 0) { [Math]::Round(($d15.proy - $rc)/$rc*100,1) } else { 0 }
            $e27 = if ($rc -gt 0) { [Math]::Round(($d27.proy - $rc)/$rc*100,1) } else { 0 }
            $fmtN = { param($n) if($n -ge 1e6){"{0:N2}M"-f($n/1e6)}elseif($n -ge 1e3){"{0:N0}K"-f($n/1e3)}else{"{0:N0}"-f$n} }
            $siteStats[$s] = @{
                real = $rc
                realFmt = (& $fmtN $rc)
                d15proy = $d15.proy; d15err = $e15
                d27proy = $d27.proy; d27err = $e27
                d15fmt = (& $fmtN $d15.proy)
                d27fmt = (& $fmtN $d27.proy)
            }
        }

        function errColor($e) { if ($e -lt 0) { '#16a34a' } else { '#dc2626' } }
        function errSign($e) { if ($e -ge 0) { "+$e%" } else { "$e%" } }
        function errSignFmt($e) { if ($e -ge 0) { "+${e}%" } else { "${e}%" } }
        function badgeClass($e15, $e27) {
            if ([Math]::Abs($e15) -le 3 -or [Math]::Abs($e27) -le 1) { "badge-green" } else { "badge-yellow" }
        }
        function badgeText($site, $e15, $e27) {
            if ([Math]::Abs($e15) -le 3) { "Muy preciso desde D15" }
            elseif ([Math]::Abs($e27) -le 2) { "Converge al cierre" }
            else { "Error moderado, converge al mes" }
        }

        $ss = $siteStats
        $flags = @{ MLB='🇧🇷'; MLM='🇲🇽'; MLC='🇨🇱'; MLA='🇦🇷' }
        $names = @{ MLB='Brasil'; MLM='México'; MLC='Chile'; MLA='Argentina' }
        $colors = @{ MLB='mlb'; MLM='mlm'; MLC='mlc'; MLA='mla' }

        # ---- Generar HTML ----
        $todayStr = (Get-Date).ToString("dd MMM yyyy")
        $pacingHtml = @"
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Pacing Analysis — Backtest $targetMonthName</title>
<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></`+`script>
<style>
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
body{font-family:system-ui,-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:#F8FAFC;color:#1e293b;line-height:1.5}
.page-wrapper{max-width:1100px;margin:0 auto;padding:32px 20px 60px}
.page-header{margin-bottom:28px}.page-header h1{font-size:1.75rem;font-weight:700;color:#0f172a;margin-bottom:4px}
.page-header p{color:#64748b;font-size:.95rem}
.banner{background:#f0fdf4;border:1px solid #86efac;border-radius:10px;padding:14px 18px;margin-bottom:28px;display:flex;align-items:flex-start;gap:10px;font-size:.9rem;color:#14532d}
.banner-icon{font-size:1.1rem;flex-shrink:0;margin-top:1px}
.section-title{font-size:1.25rem;font-weight:700;color:#0f172a;margin-bottom:18px;padding-bottom:8px;border-bottom:2px solid #e2e8f0;display:flex;align-items:center;gap:8px}
.card{background:white;border-radius:12px;box-shadow:0 1px 4px rgba(0,0,0,.06),0 0 0 1px rgba(0,0,0,.04);padding:24px;margin-bottom:20px}
.card h3{font-size:1rem;font-weight:700;color:#0f172a;margin-bottom:16px}
.steps{display:flex;gap:16px;flex-wrap:wrap}
.step{flex:1;min-width:220px;background:#F8FAFC;border:1px solid #e2e8f0;border-radius:10px;padding:18px;display:flex;flex-direction:column;gap:10px}
.step-icon{font-size:1.8rem}.step-num{font-size:.7rem;font-weight:700;text-transform:uppercase;letter-spacing:.08em;color:#64748b}
.step-text{font-size:.92rem;color:#334155;font-weight:500}
.chart-container{position:relative;width:100%}.chart-container canvas{max-height:320px}
.site-section{margin-bottom:36px}
.site-card-header{border-radius:12px 12px 0 0;padding:18px 24px;display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:10px}
.site-card-header.mlb{background:linear-gradient(135deg,#dcfce7 0%,#bbf7d0 100%);border-bottom:2px solid #16a34a}
.site-card-header.mlm{background:linear-gradient(135deg,#fee2e2 0%,#fecaca 100%);border-bottom:2px solid #dc2626}
.site-card-header.mlc{background:linear-gradient(135deg,#dbeafe 0%,#bfdbfe 100%);border-bottom:2px solid #2563eb}
.site-card-header.mla{background:linear-gradient(135deg,#cffafe 0%,#a5f3fc 100%);border-bottom:2px solid #0891b2}
.site-title{font-size:1.15rem;font-weight:700;color:#0f172a;display:flex;align-items:center;gap:8px}
.site-meta{font-size:.82rem;color:#475569;display:flex;align-items:center;gap:12px;flex-wrap:wrap}
.site-meta span{display:flex;align-items:center;gap:4px}
.badge{padding:3px 10px;border-radius:20px;font-size:.78rem;font-weight:700}
.badge-green{background:#dcfce7;color:#166534}.badge-yellow{background:#fef9c3;color:#854d0e}
.site-card-body{background:white;border-radius:0 0 12px 12px;box-shadow:0 1px 4px rgba(0,0,0,.06),0 0 0 1px rgba(0,0,0,.04);padding:24px}
.insight-table{width:100%;border-collapse:collapse;font-size:.82rem;margin-top:18px}
.insight-table th{background:#f8fafc;padding:7px 12px;font-size:.78rem;color:#64748b;border-bottom:1px solid #e2e8f0;text-align:left}
.insight-table td{padding:7px 12px;border-bottom:1px solid #f1f5f9;font-size:.82rem}
.insight-label{font-size:.7rem;font-weight:700;text-transform:uppercase;letter-spacing:.06em;color:#94a3b8}
.trend-over{color:#dc2626;font-weight:600}.trend-ok{color:#16a34a;font-weight:600}.trend-neutral{color:#0891b2;font-weight:600}
.summary-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:14px;margin-bottom:28px}
.summary-card{background:white;border-radius:10px;box-shadow:0 1px 3px rgba(0,0,0,.06),0 0 0 1px rgba(0,0,0,.04);padding:16px 18px;border-left:4px solid}
.summary-card.mlb{border-color:#16a34a}.summary-card.mlm{border-color:#dc2626}.summary-card.mlc{border-color:#2563eb}.summary-card.mla{border-color:#0891b2}
.summary-card .sc-site{font-size:.72rem;font-weight:700;text-transform:uppercase;letter-spacing:.08em;color:#94a3b8;margin-bottom:4px}
.summary-card .sc-real{font-size:1.3rem;font-weight:800;color:#0f172a}
.summary-card .sc-label{font-size:.78rem;color:#64748b;margin-bottom:8px}
.summary-card .sc-proy{font-size:.82rem;color:#475569;line-height:1.6}
hr.section-sep{border:none;border-top:2px solid #e2e8f0;margin:36px 0}
</style>
</head>
<body>
<div class="page-wrapper">
<div class="page-header">
  <h1>📊 Backtest Pacing — Afiliados $targetMonthName</h1>
  <p>Validacion del modelo sobre mes cerrado · Ventana historica: 6 meses ($histLabel) · Generado $todayStr</p>
</div>
<div class="banner">
  <span class="banner-icon">✅</span>
  <div><strong>Backtest sobre mes cerrado:</strong> Se proyecta el cierre de <strong>$targetMonthName</strong> usando avgPacing calculado sobre los <strong>6 meses previos cerrados ($histLabel)</strong>. La proyeccion se compara contra el cierre real del mes.</div>
</div>
<div class="summary-grid">
  <div class="summary-card mlb"><div class="sc-site">🇧🇷 MLB</div><div class="sc-real">$($ss['MLB']['realFmt'])</div><div class="sc-label">Cierre real $targetMonthName</div><div class="sc-proy">D15: <strong>$($ss['MLB']['d15fmt'])</strong> · Error <span style="color:$(errColor $ss['MLB']['d15err'])">$(errSignFmt $ss['MLB']['d15err'])</span><br>D27: <strong>$($ss['MLB']['d27fmt'])</strong> · Error <span style="color:$(errColor $ss['MLB']['d27err'])">$(errSignFmt $ss['MLB']['d27err'])</span></div></div>
  <div class="summary-card mlm"><div class="sc-site">🇲🇽 MLM</div><div class="sc-real">$($ss['MLM']['realFmt'])</div><div class="sc-label">Cierre real $targetMonthName</div><div class="sc-proy">D15: <strong>$($ss['MLM']['d15fmt'])</strong> · Error <span style="color:$(errColor $ss['MLM']['d15err'])">$(errSignFmt $ss['MLM']['d15err'])</span><br>D27: <strong>$($ss['MLM']['d27fmt'])</strong> · Error <span style="color:$(errColor $ss['MLM']['d27err'])">$(errSignFmt $ss['MLM']['d27err'])</span></div></div>
  <div class="summary-card mlc"><div class="sc-site">🇨🇱 MLC</div><div class="sc-real">$($ss['MLC']['realFmt'])</div><div class="sc-label">Cierre real $targetMonthName</div><div class="sc-proy">D15: <strong>$($ss['MLC']['d15fmt'])</strong> · Error <span style="color:$(errColor $ss['MLC']['d15err'])">$(errSignFmt $ss['MLC']['d15err'])</span><br>D27: <strong>$($ss['MLC']['d27fmt'])</strong> · Error <span style="color:$(errColor $ss['MLC']['d27err'])">$(errSignFmt $ss['MLC']['d27err'])</span></div></div>
  <div class="summary-card mla"><div class="sc-site">🇦🇷 MLA</div><div class="sc-real">$($ss['MLA']['realFmt'])</div><div class="sc-label">Cierre real $targetMonthName</div><div class="sc-proy">D15: <strong>$($ss['MLA']['d15fmt'])</strong> · Error <span style="color:$(errColor $ss['MLA']['d15err'])">$(errSignFmt $ss['MLA']['d15err'])</span><br>D27: <strong>$($ss['MLA']['d27fmt'])</strong> · Error <span style="color:$(errColor $ss['MLA']['d27err'])">$(errSignFmt $ss['MLA']['d27err'])</span></div></div>
</div>
<div class="section-title">🧮 Modelo: Proyeccion = MTD ÷ avgPacing</div>
<div class="card">
  <h3>Formula de pacing (6 meses)</h3>
  <div class="steps">
    <div class="step"><div class="step-icon">🗂️</div><div class="step-num">Paso 1</div><div class="step-text">Se toman los <strong>ultimos 6 meses cerrados</strong> y se calcula cuantos afiliados activos tuvo cada uno al cierre</div></div>
    <div class="step"><div class="step-icon">%</div><div class="step-num">Paso 2</div><div class="step-text">Para cada mes y dia D: ratio = (activos al dia D) / (cierre total). Se promedian los 6 ratios → <strong>avgPacing al dia D</strong></div></div>
    <div class="step"><div class="step-icon">➗</div><div class="step-num">Paso 3</div><div class="step-text">Proyeccion = MTD_D / avgPacing_D. Captura patrones de aceleracion/desaceleracion intra-mes.</div></div>
  </div>
</div>
<div class="card">
  <h3>avgPacing por site — $histLabel</h3>
  <p style="font-size:.875rem;color:#64748b;margin-bottom:16px">% del cierre que ya estaba activo al dia D, promediado sobre 6 meses. Esta curva divide el MTD para proyectar el cierre.</p>
  <div class="chart-container"><canvas id="chartAvgPacing"></canvas></div>
</div>
<hr class="section-sep">
<div class="section-title">📈 Backtest $targetMonthName — Proyeccion diaria vs Cierre real</div>
$(foreach ($s in @('MLB','MLM','MLC','MLA')) {
"<div class='site-section' id='site-$s'><div class='site-card-header $($colors[$s])'><div class='site-title'>$($flags[$s]) $s — $($names[$s])</div><div class='site-meta'><span>Cierre real: <strong>$($ss[$s]['realFmt'])</strong></span><span>Proy. D15: <strong>$($ss[$s]['d15fmt'])</strong> ($(errSignFmt $ss[$s]['d15err']))</span><span>Proy. D27: <strong>$($ss[$s]['d27fmt'])</strong> ($(errSignFmt $ss[$s]['d27err']))</span><span class='badge $(badgeClass $ss[$s]['d15err'] $ss[$s]['d27err'])'>$(badgeText $s $ss[$s]['d15err'] $ss[$s]['d27err'])</span></div></div><div class='site-card-body'><div class='chart-container'><canvas id='chart$s'></canvas></div><table class='insight-table'><thead><tr><th>Periodo</th><th>Proy. media</th><th>Error medio</th><th>Tendencia</th></tr></thead><tbody id='insight$s'></tbody></table></div></div>"
})
</div>
<script>
const RAW=$rawJson;
function fmtNum(n){if(n>=1e6)return(n/1e6).toFixed(2)+'M';if(n>=1e3)return Math.round(n/1e3)+'K';return Math.round(n).toString();}
function fmtPct(n){return(n>=0?'+':'')+n.toFixed(1)+'%';}
function pctError(p,r){return((p-r)/r)*100;}
function getBySite(s){return RAW.filter(d=>d.site===s).sort((a,b)=>a.dia-b.dia);}
const SC={MLB:'#16a34a',MLM:'#dc2626',MLC:'#2563eb',MLA:'#0891b2'};
const DAYS=Array.from({length:$daysInTarget},(_,i)=>i+1);
(function(){
  const ds=['MLB','MLM','MLC','MLA'].map(site=>({label:site,data:getBySite(site).map(d=>+(d.avg_p*100).toFixed(2)),borderColor:SC[site],backgroundColor:SC[site]+'18',borderWidth:2.5,pointRadius:3,tension:0.35,fill:false}));
  new Chart(document.getElementById('chartAvgPacing'),{type:'line',data:{labels:DAYS,datasets:ds},options:{responsive:true,interaction:{mode:'index',intersect:false},plugins:{legend:{position:'top',labels:{font:{size:12},padding:16}},tooltip:{callbacks:{label:c=>` `+c.dataset.label+`: `+c.parsed.y.toFixed(1)+`%`}}},scales:{x:{title:{display:true,text:'Dia del mes',color:'#64748b'},grid:{color:'#f1f5f9'},ticks:{color:'#64748b'}},y:{min:0,max:100,grid:{color:'#f1f5f9'},ticks:{color:'#64748b',callback:v=>v+'%'}}}}});
})();
function buildChart(site,cid){
  const data=getBySite(site),real=data[0].real_mtd,color=SC[site],pv=data.map(d=>d.proyeccion);
  const ds=[{label:'_a',data:pv.map(v=>v>real?v:real),borderWidth:0,pointRadius:0,fill:{target:1,above:'rgba(220,38,38,0.10)',below:'rgba(0,0,0,0)'},tension:0.35,borderColor:'transparent',backgroundColor:'transparent'},{label:'Cierre real',data:Array($daysInTarget).fill(real),borderColor:'#0f172a',borderWidth:2,borderDash:[6,4],pointRadius:0,fill:false,tension:0},{label:'_b',data:pv.map(v=>v<real?v:real),borderWidth:0,pointRadius:0,fill:{target:1,above:'rgba(0,0,0,0)',below:'rgba(22,163,74,0.12)'},tension:0.35,borderColor:'transparent',backgroundColor:'transparent'},{label:'Proyeccion cierre',data:pv,borderColor:color,backgroundColor:color+'22',borderWidth:2.5,pointRadius:c=>c.dataIndex===$($daysInTarget-1)?6:3,pointBackgroundColor:color,tension:0.35,fill:false}];
  const av=[...pv,real];
  new Chart(document.getElementById(cid),{type:'line',data:{labels:DAYS,datasets:ds},options:{responsive:true,interaction:{mode:'index',intersect:false},plugins:{legend:{labels:{filter:i=>!i.text.startsWith('_'),font:{size:12},padding:16}},tooltip:{filter:i=>!i.dataset.label.startsWith('_'),callbacks:{label:c=>{if(c.dataset.label==='Cierre real')return ` Cierre real: `+fmtNum(c.parsed.y);return ` Proyeccion: `+fmtNum(c.parsed.y)+` (error: `+fmtPct(pctError(c.parsed.y,real))+`)`;}}}},scales:{x:{title:{display:true,text:'Dia del mes',color:'#64748b'},grid:{color:'#f1f5f9'},ticks:{color:'#64748b'}},y:{min:Math.min(...av)*0.92,max:Math.max(...av)*1.06,grid:{color:'#f1f5f9'},ticks:{color:'#64748b',callback:v=>fmtNum(v)}}}}});
}
['MLB','MLM','MLC','MLA'].forEach(s=>buildChart(s,'chart'+s));
function buildInsight(site,tid){
  const data=getBySite(site),real=data[0].real_mtd;
  const periods=[{label:'D1-D7',from:1,to:7},{label:'D8-D14',from:8,to:14},{label:'D15-D'+$daysInTarget,from:15,to:$daysInTarget}];
  const tbody=document.getElementById(tid);tbody.innerHTML='';
  periods.forEach(p=>{
    const sl=data.filter(d=>d.dia>=p.from&&d.dia<=p.to);
    const avgP=sl.reduce((s,d)=>s+d.proyeccion,0)/sl.length;
    const avgE=sl.reduce((s,d)=>s+pctError(d.proyeccion,real),0)/sl.length;
    const f=pctError(sl[0].proyeccion,real),l=pctError(sl[sl.length-1].proyeccion,real);
    let t,tc;
    if(Math.abs(avgE)<5){t='Estable / preciso';tc='trend-ok';}
    else if(avgE>15){t='Sobreestimo fuerte';tc='trend-over';}
    else if(avgE>5){t=l<f?'Convergiendo':'Sobreestimo';tc=l<f?'trend-neutral':'trend-over';}
    else if(avgE<-5){t=l>f?'Subestimo (mejorando)':'Subestimo';tc='trend-neutral';}
    else{t='Cercano al real';tc='trend-ok';}
    const tr=document.createElement('tr');
    tr.innerHTML=`<td><span class="insight-label">`+p.label+`</span></td><td>`+fmtNum(Math.round(avgP))+`</td><td style="font-weight:600;color:`+(avgE>0?'#dc2626':'#16a34a')+`">`+fmtPct(avgE)+`</td><td class="`+tc+`">`+t+`</td>`;
    tbody.appendChild(tr);
  });
}
['MLB','MLM','MLC','MLA'].forEach(s=>buildInsight(s,'insight'+s));
</script></body></html>
"@

        # ---- Escribir y subir ----
        [IO.File]::WriteAllText($pacingHtmlPath, $pacingHtml, [Text.Encoding]::UTF8)
        Write-Host "  Pacing HTML generated ($([Math]::Round($pacingHtml.Length/1024,0)) KB)." -ForegroundColor Magenta

        $pacingCfg = "{`"skill_version`":`"3.6.0`",`"skip_version_check`":true,`"doc_id`":`"$pacingDocId`",`"title`":`"Backtest Pacing - Afiliados $targetMonthName`"}"
        $tmpPCfg = [IO.Path]::GetTempFileName()
        [IO.File]::WriteAllText($tmpPCfg, $pacingCfg)
        $pResp = & "C:\Windows\System32\curl.exe" -s -X POST "https://grid.melioffice.com/api/v1/engine/run" -F "config=<$tmpPCfg" -F "file=@$pacingHtmlPath"
        Remove-Item $tmpPCfg -ErrorAction SilentlyContinue
        $pParsed = $pResp | ConvertFrom-Json
        if ($pParsed.ok) {
            Write-Host "  Pacing Grid upload OK: $($pParsed.view_url)" -ForegroundColor Green
            Set-Content -Path $pacingStateFile -Value $PREV -Encoding ASCII
        } else {
            Write-Host "  Pacing Grid upload FAILED" -ForegroundColor Red
            Write-Host $pResp
        }
    }
} else {
    Write-Host "  Pacing backtest up to date (last: $lastPacingMonth)." -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "=== DONE in ${totalSec}s ===" -ForegroundColor Cyan
