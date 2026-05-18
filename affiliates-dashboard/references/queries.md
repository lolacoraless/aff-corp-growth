# Queries BigQuery — Dashboard Afiliados

Todas las queries están implementadas en `bq_refresh.ps1` y se ejecutan en paralelo.

## Placeholders de fecha

| Placeholder | Valor |
|-------------|-------|
| `${D.HIST}` | 2025-01-01 |
| `${D.DEEP}` | 2024-01-01 |
| `${D.ENIGMA}` | 2026-04-01 (inicio modelo Enigma) |
| `${D.YEST}` | Ayer |
| `${D.CUR}` | Primer día del mes actual |
| `${D.PREV}` | Primer día del mes anterior |
| `${D.PREV_DAY}` | Mismo día del mes anterior (MTD apples-to-apples) |
| `${D.M2}` | Primer día de hace 2 meses |
| `${D.W8}` | Inicio ventana 8 semanas (lunes hace 8 semanas) |

---

## 1. behaviour — Source of truth

**Tabla:** `meli-bi-data.SBOX_AFILIADOSCOREDATA.MKT_AFFILIATE_BEHAVIOUR`

Columnas pre-calculadas: `active_aff`, `retained_aff` (recurrentes), `recovered_aff`, `new_aff`, `churned_aff`, `quick_ratio`

`churned_aff` es **backward-looking** (salieron ESTE mes). Abril 2026 tiene QR válido porque churned_aff = quienes no vendieron en abril (ya sabemos).

**MLA:** lanzamiento masivo marzo 2026 (56K nuevos, 878 churners → QR=64.86). Excluir de gráficos QR hasta base estable.

```sql
SELECT sit_site_id, dt, period, active_aff,
  retained_aff AS recurrent, recovered_aff AS recovered,
  new_aff, churned_aff AS inactive,
  SAFE_DIVIDE(new_aff + recovered_aff, churned_aff) AS quick_ratio
FROM `meli-bi-data.SBOX_AFILIADOSCOREDATA.MKT_AFFILIATE_BEHAVIOUR`
WHERE period IN ('MONTH','WEEK')
  AND sit_site_id IN ('MLB','MLM','MLC','MLA')
  AND dt >= '${D.HIST}'
ORDER BY sit_site_id, period, dt
```

---

## 2. beh_mtd — MTD custom (curr y prev)

**Tabla:** `meli-bi-data.WHOWNER.BT_AFFI_SALES_ATTRIBUTION_DAILY`

Calcula MTD actual (`curr`) vs mismo período mes anterior (`prev`). Se usa para `prev.*` (deltas) incluso cuando `actMtdBeh != null`.

Lógica:
- `curr_7d`: afiliados con venta entre `D.CUR` y `D.YEST`
- `prev_7d`: afiliados con venta entre `D.PREV` y `D.PREV_DAY`
- `apr_full`: afiliados con venta en `D.PREV` (mes anterior completo)
- `mar_full`: afiliados con venta en `D.M2`

Clasifica cada afiliado como: `new_aff` (first_month = mes actual), `recovered_aff` (historial pero ausente mes ant), `churned_aff` (en mes ant pero no en curr).

---

## 3. qr_rolling — Quick Ratio Rolling 30 días

**Tabla:** `meli-bi-data.WHOWNER.BT_AFFI_SALES_ATTRIBUTION_DAILY`

**QR Rolling = (new_30d + recovered_30d) / churned_30d** sobre ventana deslizante.

- `win_curr`: últimos 30 días (D.YEST-29 → D.YEST)
- `win_prev`: 30 días previos (D.YEST-59 → D.YEST-30)
- `new_30d`: vendieron en curr Y es su first_date en ese período
- `recovered_30d`: vendieron en curr, NO en prev, first_date anterior a la ventana
- `churned_30d`: vendieron en prev pero NO en curr

MLA excluido del gráfico.

---

## 4. registrations — Serie histórica registros

**Tabla:** `meli-bi-data.SBOX_AFILIADOSCOREDATA.AFFILIATE_REGISTRATION_CHANNEL`

```sql
SELECT ds, site_id, origen, origen_grouped,
  COUNT(origen) AS users,
  EXTRACT(YEAR FROM DATE(ds)) AS YEAR,
  EXTRACT(MONTH FROM DATE(ds)) AS MONTH,
  EXTRACT(ISOWEEK FROM DATE(ds)) AS ISOWEEK
FROM `meli-bi-data.SBOX_AFILIADOSCOREDATA.AFFILIATE_REGISTRATION_CHANNEL`
WHERE ds >= '${D.HIST}'
GROUP BY ALL ORDER BY 1, 2, 3
```

`origen_grouped`: POM-Facebook, POM-TikTok, POM-Google, Direct, E&G, etc.

---

## 5. reg_mtd — Registros MTD vs previo

```sql
SELECT site_id,
  COUNTIF(ds >= '${D.CUR}' AND ds <= '${D.YEST}') AS curr_mtd,
  COUNTIF(ds >= '${D.PREV}' AND ds <= '${D.PREV_DAY}') AS prev_mtd,
  origen_grouped
FROM `meli-bi-data.SBOX_AFILIADOSCOREDATA.AFFILIATE_REGISTRATION_CHANNEL`
WHERE ds >= '${D.PREV}' AND ds <= '${D.YEST}'
GROUP BY ALL
```

---

## 6. landing_traffic — Visitas a la landing

**Tabla:** `meli-bi-data.SBOX_AFILIADOSCOREDATA.MKT_REGISTRATION_JOURNEY`
**Filtro:** `page = 'landing'`

Canal clasificado vía `campaign` (POM) y `fragment` JSON (Direct).

```sql
SELECT site, ds,
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
  COUNT(user_id) AS qty_users_conect
FROM `meli-bi-data.SBOX_AFILIADOSCOREDATA.MKT_REGISTRATION_JOURNEY`
WHERE page = 'landing' AND ds >= '${D.HIST}'
GROUP BY ALL
```

Métricas: `visitas` = page views, `qty_users` = únicos (incl. no logueados), `qty_users_conect` = logueados.
Cruzar con `registrations` para calcular conversión landing → registro por canal.

---

## 7. spend_pom

**Tablas:** `SBOX_MARKETING.BT_COST_GOOGLE/FACEBOOK/TIKTOK_DAILY`

`SITE_ID` se deriva de `CAMPAIGN_NAME` con `REGEXP_CONTAINS(CAMPAIGN_NAME, 'MLB_')` etc.

---

## 8. nmv_monthly / nmv_weekly / nmv_mtd

**Tabla:** `meli-bi-data.WHOWNER.BT_SC_TOTAL_SITE_AFILIADOS`

Regla de modelo:
```sql
CASE
  WHEN DT >= '2026-04-01' THEN NMV_AFF   -- Enigma (vigente)
  ELSE NMV_TD7D                            -- Time Decay 7D (deprecado)
END
```

**Nunca usar:** `GMV_*`, `TGMV`, `ORDERS_TD7D`.

---

## 9. churn / churn_comp / churn_mtd

**Tabla:** `meli-bi-data.WHOWNER.BT_AFFI_SALES_ATTRIBUTION_DAILY`

Filtros **siempre requeridos:**
```sql
AND ORD_STATUS = 'paid'
AND SIT_SITE_ID = AFFILIATE_SIT_SITE_ID
AND SIT_SITE_ID IN ('MLB','MLM','MLC','MLA')
AND ((ORD_CREATED_DT >= '2026-04-01' AND NMV_ENIGMA_TOTAL_AMT_LC > 0)
  OR (ORD_CREATED_DT < '2026-04-01' AND NMV_TD7DCALIB_TOTAL_AMT_LC > 0))
```

---

## 10. act1 / act2 — Activación por cohorte

**Tablas:** `AFFILIATE_AFFILIATE` + `AFFILIATE_REGISTRATION_CHANNEL` + `BT_AFFI_SALES_ATTRIBUTION_DAILY`

Mide % de registros por cohorte que activaron en 30/90 días.

Segmentos:
- 01 — Activaron en 7d o menos
- 02 — Activaron entre 8d y 15d
- 03 — Activaron entre 16d y 30d
- 04 — Activaron entre 31d y 45d
- 05 — Activaron en 46d o más
- 06 — No activaron

---

## Notas de desarrollo

- `DT` en `BT_SC_AFFILIATE_BASE` es DATETIME → usar `CAST(DT AS DATE)` para filtrar
- `VERTICAL` (AFFILIATE_BASE) vs `VERTIC` (TOTAL_SITE_AFILIADOS) — nombres distintos
- `NMV_AFF` no es aditivo con `NMV_LC` — son métricas para propósitos distintos
- Valores en moneda local — NO comparar NMV entre sites sin conversión a USD
