---
name: affiliates-closing
description: >
  Genera reportes del programa de Afiliados de MercadoLibre en dos modos.
  MODO MENSUAL: cuando el usuario pida "cierre de [mes]", "mes cerrado", "cerrar [mes]",
  "reporte mensual afiliados", "dame el cierre" o similar al inicio de mes — genera la
  tabla de métricas detallada (13 KPIs, 3 meses, semáforos) + mensaje de Slack listo para
  copiar con insights narrativos por país.
  MODO SEMANAL MTD: cuando pida "MTD afiliados", "cómo vamos", "seguimiento semanal",
  "resultados MTD", "actualización semanal", "qué dice el MTD" o similar — genera la
  tabla MTD + mensaje de Slack con highlights por país.
  Activar siempre que se mencione cierre, MTD, o seguimiento del programa de afiliados,
  incluso si el usuario no lo pide explícitamente con ese nombre.
---

# Affiliates Closing Report

## Fuente de datos y configuración

**Fuente de datos:** la resuelve `scripts/data_source.py`, que importan los dos extractores.

1. **Google Sheet** (fuente viva) — `14GoBnB6GgnUYsCBY_nx82DUL2hZEmFXbDR4dByketqc`.
   Lo escribe Verdi Flows a las 10, 12 y 14 hs. Una tab por familia de queries,
   con cada fila serializada por `TO_JSON_STRING`. Se lee por la API de Grid,
   asi que **requiere VPN de MELI**.
2. **HTML local** (respaldo) — `C:\Users\lcorales\Downloads\Claude\affiliates-dashboard-grid.html`.
   Solo se actualiza cuando alguien corre `bq_refresh.ps1` a mano, asi que puede
   estar dias atrasado.

Los scripts intentan el Sheet primero y caen al HTML si no responde. **Siempre
imprimen de donde salieron los datos y de cuando son**, en la primera linea:

```
[fuente] Google Sheet (Verdi, se actualiza 10/12/14 hs) - snapshot 2026-09-11 15:24:37 UTC
```

Si dice `HTML local`, avisarlo en el reporte: los numeros pueden no ser de hoy.

**Orden de sites (siempre este orden):** MLB → MLM → MLC → MLA

**URL del dashboard:** `https://grid.adminml.com/d/01KRE46H4452DPPVSYM5BKXJ14/view`

**Scripts de extracción** (en `scripts/` relativo a esta skill):
- `data_source.py` — resuelve la fuente (Sheet → HTML). No se corre solo, lo importan los otros dos
- `extract_monthly.py` — cierre mensual
- `extract_mtd.py` — seguimiento MTD

---

## Detección de modo

| Señal | Modo |
|-------|------|
| "cierre de [mes]", "mes cerrado", "cerrar [mes]", "reporte mensual" | **MENSUAL** |
| "MTD", "cómo vamos", "seguimiento semanal", "resultados MTD" | **SEMANAL MTD** |

Si ambiguo: "¿Querés el cierre del mes o el seguimiento MTD?"

---

## MODO 1: CIERRE MENSUAL

### Paso 1 — Extraer datos

Correr el script (desde el directorio de la skill):
```bash
python scripts/extract_monthly.py
```

El script emite tres secciones:
1. **TABLA DETALLADA** — 13 métricas × 3 meses con columnas M1/M0, M2/M1, M2/M0 y semáforos
2. **BLOQUE SLACK (1) Main KPIs** — tabla compacta lista para pegar, M-1 vs M0
3. **DATOS PARA INSIGHTS** — valores raw de drivers (new, recurrentes, recovered, churn, NMV share, QR, registros) con deltas M-1→M0

### Paso 2 — Generar la tabla detallada

Presentar la tabla exactamente como sale del script (sección 1). No modificarla, solo mostrarla tal cual.

### Paso 3 — Armar el mensaje de Slack

Construir el mensaje completo sin enviarlo. Usar el template de abajo, rellenando con los valores del script.

#### Template Slack — Cierre mensual

```
[Afiliados | Cierre {Mes} {Año}]
Hola team, les comparto el cierre de {mes}.
TLDR: {ver reglas TLDR abajo}

(1) Main KPIs

{bloque compacto de la sección 2 del script, tal cual}

{línea QR de la sección 2 del script, tal cual}

(2) Insights
{narrativa por site — ver reglas de insights abajo}

Registros: {párrafo de registros — ver reglas abajo}

Dashboard completo → https://grid.adminml.com/d/01KRE46H4452DPPVSYM5BKXJ14/view
```

**Reglas del TLDR:**
- Una frase por site, en orden MLB → MLM → MLC → MLA
- Incluir: dirección de activos (cantidad absoluta o Δ%), el driver principal, y QR si es notable
- Cerrar con una observación cross-site (ej: "QR > 1 en 3 de 4 sites")
- Tono: directo, datos primero, sin adjetivos genéricos como "excelente" o "preocupante"
- Ejemplo: "MLB supera 1.21M activos (+7.3%), MLM suma +5.8% con recurrentes acelerando y MLC crece +30% (QR 1.54). MLA retrocede en todos los indicadores (−25% activos, QR 0.69). QR mensual > 1 en 3 de 4 sites."

**Reglas de insights por site:**
- Orden: MLB → MLM → MLC → MLA
- Arrancar con el headline del site (ej: "MLC lidera el crecimiento:", "MLA retrocede en todos los segmentos:")
- Incluir los drivers en este orden: activos Δ%, QR valor, NMV share Δpp si es relevante, luego descomponer: recurrentes Δ%, new Δ%, recovered Δ%, churn Δ%
- Conectar causa-efecto: explicar POR QUÉ el QR subió/bajó en base a los componentes (new+recovered vs inactive)
- Si hay tensión entre indicadores (activos caen pero NMV share sube), mencionarlo y especular brevemente sobre la causa (ej: "posible purga de calidad")
- Cada site: 2-3 oraciones densas, sin bullets
- Usar signo − (no guion -) para negativos

**Párrafo de Registros:**
- Una oración por canal (Direct y POM) describiendo el patrón cross-sites
- Mencionar outliers: qué site sube / cuál baja más, y si el Spend POM explica el movimiento de POM
- Ejemplo: "Registros: Direct baja en MLB (−6%) y MLC (−12%); plano en MLM y MLA. POM sube en MLM (+14%) y MLC (+21%), y cae en MLA (−12%) y MLB (−24%)."

---

## MODO 2: SEMANAL MTD

### Paso 1 — Extraer datos

Correr el script:
```bash
python scripts/extract_mtd.py
```

El script emite cuatro secciones:
1. **SCHEMA DISCOVERY** — estructura de las tablas MTD (necesario la primera vez)
2. **EXTRACCIÓN MTD** — valores brutos por site de todos los campos disponibles
3. **BLOQUE SLACK (1) KPIs MTD** — tabla tentativa y línea QR Rolling (validar contra sección 2)
4. **Churn MTD por site** — datos de churn disponibles

### Paso 2 — Validar y completar la tabla

Leer la sección 2 (valores brutos) para verificar que los campos usados en la sección 3 son correctos. Si hay discrepancias (campo incorrecto, valor 0 donde no debería), corregirlos manualmente usando los valores de la sección 2.

Para el **día del mes**: tomarlo del campo de freshness o de los datos disponibles (generalmente `dt_to` del qr_rolling o similar).

Para la **comparación vs mismo período mes anterior**: usar el campo `prev_*` o `lm_*` (last month) que aparezca en beh_mtd/nmv_mtd. Si no existe, indicarlo como "sin dato comparable" en lugar de inventar.

### Paso 3 — Armar el mensaje de Slack

```
[Afiliados | Resultados MTD · D{N}/{total_dias} ({pct}% del mes)]
Hola team, les comparto los resultados MTD al día {N} de {total_dias} ({pct}% del mes).
TLDR: {ver reglas TLDR abajo}

(1) KPIs

```
NMV Share   Δ vs {mes_ant} D1-{N}   Activos MTD      Δ
{tabla por site, alineada con espacios fijos}
QR Rolling 30d ({fecha_inicio}–{fecha_fin}): MLB X.XX · MLM X.XX · MLC X.XX · MLA X.XX
```

(2) Highlights

* {site}: {highlight en 1-2 oraciones con drivers}

Dashboard → https://grid.adminml.com/d/01KRE46H4452DPPVSYM5BKXJ14/view
```

**Reglas del TLDR semanal:**
- Una frase por site con la dirección principal (activos MTD Δ) y el dato más relevante (share, QR, o lo que más destaque)
- Cerrar con una observación cross-site si aplica

**Reglas de highlights (sección 2):**
- Bullets, uno por site, orden MLB → MLM → MLC → MLA
- Estructura: dirección de activos + driver principal + canal de registros más notable + churn si hay movimiento
- Conectar: si Direct cae, mencionar el motivo probable (inversión, CPR, etc.) si hay datos de spend o contexto disponible
- Ejemplo: "MLB: activos +7.6% MoM impulsados por recurrentes (+20.9%) y recuperados; new flat (−0.3%) con Direct cayendo y POM compensando (+25%). Churn sube +6.6%."
- Si un site tiene dinámica mixta (activos caen pero share sube), mencionarlo en el bullet

---

## Notas técnicas importantes

- **QR calendario vs QR rolling**: el script usa `quick_ratio` del behaviour MENSUAL (QR calendario = (new+recovered)/inactive del mes). El QR Rolling 30d es distinto y viene de `qr_rolling`. No confundirlos.
- **NMV share**: campo `share_ts` en `nmv_monthly` / `nmv_mtd`, seg `'all'`. LT = `'lt'`, KA = `'nlt'`.
- **Registrations**: tabla usa `site_id` (no `sit_site_id`) y campo `month` como entero (1-12).
  Desde la v2 viene pre-agregada en BQ con una columna `grain` (`month` | `week`).
  Al sumar por mes hay que filtrar `grain == 'month'`: las filas semanales traen
  `year`/`month` en null, rompen el `int()` y desvirtuan el total.
- **Churn %**: calcular como `churned / active_prev * 100` desde la tabla `churn`.
- **Spend POM**: campo `cost_lc` en moneda local del site.
- **Semáforos**: umbral ±3% sobre cambio relativo. Churn es reversed (baja = 🟢). QR es higher-is-better.
