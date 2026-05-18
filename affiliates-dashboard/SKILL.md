---
name: affiliates-dashboard
description: >
  Skill para trabajar con el dashboard corporativo de Afiliados de MercadoLibre —
  actualizar datos (bq_refresh.ps1), modificar el HTML standalone, publicar en Grid,
  calcular métricas de behaviour/QR/registros/landing, escribir queries BigQuery, y
  enviar el mensaje semanal de pulso por Slack.
  Usar este skill siempre que la conversación mencione: dashboard de afiliados, bq_refresh,
  métricas de behaviour, QR rolling, activos, proyecciones, landing traffic, registros por canal,
  publicar en Grid el dashboard, mensaje de pulso semanal, o cualquier KPI operativo del programa.
---

# Dashboard Corporativo de Afiliados

## Archivos del proyecto

| Archivo | Ruta |
|---------|------|
| HTML del dashboard | `C:\Users\lcorales\Downloads\Claude\affiliates-dashboard-grid.html` |
| Script de refresh | `C:\Users\lcorales\Downloads\Claude\bq_refresh.ps1` |
| Doc en Grid | ID `01KRE46H4452DPPVSYM5BKXJ14` |

## Arquitectura

```
bq_refresh.ps1
  ├── 14 queries BigQuery en paralelo (bq query --format=json)
  ├── Parse-BQResult → hash $data por site
  └── inyecta window.__PRELOADED__ en línea 7 del HTML

affiliates-dashboard-grid.html
  ├── Lee window.__PRELOADED__ al arrancar
  ├── DATA[site] → monSrc (arrays paralelos por métrica)
  └── Chart.js para gráficos
```

Flujo: `$data` → `window.__PRELOADED__` → `DATA[site]` → `monSrc`
- `monSrc.active/new/rec/chu/ret/qr` = arrays de valores mensuales
- `.at(-1)` = mes actual (parcial si en curso), `.at(-2)` = mes anterior cerrado

## Claves del snapshot __PRELOADED__

| Clave | Fuente | Descripción |
|-------|--------|-------------|
| `behaviour` | MKT_AFFILIATE_BEHAVIOUR | Serie histórica completa |
| `beh_mtd` | BT_AFFI_SALES_ATTRIBUTION_DAILY | MTD actual vs mismo período mes anterior |
| `qr_rolling` | BT_AFFI_SALES_ATTRIBUTION_DAILY | QR rolling 30d |
| `registrations` | AFFILIATE_REGISTRATION_CHANNEL | Registros por canal |
| `reg_mtd` | AFFILIATE_REGISTRATION_CHANNEL | Registros MTD vs previo |
| `landing_traffic` | MKT_REGISTRATION_JOURNEY | Visitas landing por origen |
| `spend_pom` | BT_COST_GOOGLE/FACEBOOK/TIKTOK_DAILY | Gasto POM diario |
| `nmv_monthly/weekly/mtd` | BT_SC_TOTAL_SITE_AFILIADOS | NMV del canal |
| `act1/act2` | varios | Activación 30/90 días por cohorte |
| `churn/churn_comp/churn_mtd` | BT_AFFI_SALES_ATTRIBUTION_DAILY | Churn histórico y MTD |

## Discriminador actMtdBeh — lógica crítica

```javascript
const actMtdBeh = monSrc.active?.at(-1) ?? null;
// actMtdBeh != null → BEHAVIOUR tiene fila MONTH del mes en curso → usar monSrc.X.at(-1)
// actMtdBeh == null → tabla sin datos del mes actual → usar beh_mtd
const newMtdBeh = actMtdBeh != null ? (monSrc.new?.at(-1) ?? null) : (mtd.new ?? null);
const recMtdBeh = actMtdBeh != null ? (monSrc.rec?.at(-1) ?? null) : (mtd.rec ?? null);
const chuMtdBeh = actMtdBeh != null ? (monSrc.chu?.at(-1) ?? null) : (mtd.chu ?? null);
const retMtdBeh = actMtdBeh != null ? (monSrc.ret?.at(-1) ?? null) : null;
// beh_mtd siempre se usa para prev.* (mismo período mes anterior)
```

## Orden de declaración de variables (evitar TDZ crash)

1. closedQrs, aprQr, prevQr
2. allMonths, retWithIdx, lastRet, lastRetLbl
3. activeArr, actMtdBeh  ← DISCRIMINADOR — todo lo demás depende de este
4. closedActiveItems, lastActive, lastActiveLbl
5. activeTot, pActiveNew, pActiveRec
6. newMtdBeh, recMtdBeh, chuMtdBeh, retMtdBeh  ← dependen de actMtdBeh
7. retMtd, retPrevMtd, aprRetClose, retProj     ← dependen de retMtdBeh
8. currMonQr                                     ← depende de newMtdBeh/recMtdBeh/chuMtdBeh
9. aprNewClose, aprRecClose, aprChuClose

## Proyecciones

`GROWTH_TARGET = 0.10` (10% sobre cierre mes anterior)

| Métrica | Método |
|---------|--------|
| New, Recuperados, Inactivos | Lineal: MTD / DAYS_ELAPSED × DAYS_IN_MONTH |
| Total Activos | Ratio-pace: actMtdBeh × lastActive / prevActMtd |
| Recurrentes | Ratio-pace: retMtd × aprRetClose / retPrevMtd |
| Quick Ratio | No se proyecta |

Target: positivas = cierre anterior × 1.10 / Inactivos = cierre anterior × 0.90
Semáforo: 🟢 ≥100% | 🟡 90-99% | 🔴 <90% (invertido para Inactivos)

Ver detalle completo: `references/dashboard-logic.md`

## Proceso de actualización

1. VPN + `.\bq_refresh.ps1` (~3 min, requiere gcloud autenticado)
2. Grid: curl con `doc_id: 01KRE46H4452DPPVSYM5BKXJ14` + `skip_version_check: true` (siempre)

Ver checklist completo: `references/process.md`

## Queries BigQuery

Ver todas: `references/queries.md`

Tablas principales:
- `MKT_AFFILIATE_BEHAVIOUR` (SBOX_AFILIADOSCOREDATA) — source of truth behaviour
- `BT_AFFI_SALES_ATTRIBUTION_DAILY` (WHOWNER) — MTD, QR rolling, churn
- `AFFILIATE_REGISTRATION_CHANNEL` (SBOX_AFILIADOSCOREDATA) — registros
- `MKT_REGISTRATION_JOURNEY` (SBOX_AFILIADOSCOREDATA) — visitas landing
- `BT_SC_TOTAL_SITE_AFILIADOS` (WHOWNER) — NMV del canal

## Reglas de negocio

- MLA excluido del QR rolling (lanzamiento masivo marzo 2026: QR=64.86 artificial)
- Churn inicio de mes artificialmente alto — no alertar en primeros 7-10 días
- NMV: usar NMV_AFF (Enigma desde 01/04/2026) o NMV_TD7DCALIB antes. NUNCA GMV_*
- One month wonders ≠ churn de nuevos (one month wonders solo se confirma retrospectivamente)
- LC vs TD7D: modelos distintos. LC = comisionamiento; TD7D = medición interna (deprecado)

## Slack — pulso semanal

Canal oficial: `C05THPGTR89` (affiliates corp) | Pruebas: `U019LKLQGJ2` (Delfina Cadenas)
Ver estructura del mensaje: `references/process.md`
