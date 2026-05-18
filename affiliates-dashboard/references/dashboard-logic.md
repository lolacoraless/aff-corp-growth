# Lógica del Dashboard — Proyecciones, KPIs y Semáforos

## Constante global

```javascript
const GROWTH_TARGET = 0.10;  // 10% sobre cierre mes anterior
```

---

## Construcción de monSrc

```javascript
const monSrc = {
  active: DATA[site].beh.mon.map(r => r.active_aff),
  new:    DATA[site].beh.mon.map(r => r.new_aff),
  rec:    DATA[site].beh.mon.map(r => r.recovered_aff),
  chu:    DATA[site].beh.mon.map(r => r.inactive_aff),   // churned
  ret:    DATA[site].beh.mon.map(r => r.recurrent_aff),
  qr:     DATA[site].beh.mon.map(r => r.quick_ratio),
};
// .at(-1) = mes actual (parcial si en curso)
// .at(-2) = mes anterior cerrado
// .slice(0,-1) = todos los meses cerrados
```

---

## Discriminador actMtdBeh

```javascript
const actMtdBeh = monSrc.active?.at(-1) ?? null;
```

- `actMtdBeh !== null` → `MKT_AFFILIATE_BEHAVIOUR` ya tiene la fila MONTH del mes en curso → usar `monSrc.X.at(-1)` para todos los valores MTD
- `actMtdBeh === null` → tabla no tiene el mes actual → usar `beh_mtd` (query custom)

`beh_mtd` siempre se usa para `prev.*` (mismo período mes anterior) independientemente del estado de `actMtdBeh`.

---

## Proyecciones

### Total Activos — Ratio-pace

```javascript
const lastActive  = closedActiveItems.at(-1)?.v ?? null;  // cierre mes anterior
const prevActMtd  = mtd.act ?? null;                      // activos mismo período mes ant (beh_mtd)
const actMtdVal   = actMtdBeh ?? activeTot;

const actProj   = (actMtdVal && prevActMtd > 0 && lastActive)
  ? Math.round(actMtdVal * lastActive / prevActMtd) : null;
const actTarget = lastActive ? Math.round(lastActive * (1 + GROWTH_TARGET)) : null;
```

### Recurrentes — Ratio-pace

```javascript
const aprRetClose = monSrc.ret?.filter(v=>v!=null).at(-2) ?? null; // cierre mes anterior
const retPrevMtd  = prev.act ? Math.max(0, prev.act - (prev.new||0) - (prev.rec||0)) : null;

const retProj   = (retMtd && retPrevMtd > 0 && aprRetClose)
  ? Math.round(retMtd * aprRetClose / retPrevMtd) : null;
const retTarget = aprRetClose ? Math.round(aprRetClose * (1 + GROWTH_TARGET)) : null;
```

### New, Recuperados — Extrapolación lineal

```javascript
const newProj   = (newMtdBeh && DAYS_ELAPSED > 0)
  ? Math.round(newMtdBeh / DAYS_ELAPSED * DAYS_IN_MONTH) : null;
const newTarget = aprNewClose ? Math.round(aprNewClose * (1 + GROWTH_TARGET)) : null;

const recProj   = (recMtdBeh && DAYS_ELAPSED > 0)
  ? Math.round(recMtdBeh / DAYS_ELAPSED * DAYS_IN_MONTH) : null;
const recTarget = aprRecClose ? Math.round(aprRecClose * (1 + GROWTH_TARGET)) : null;
```

### Inactivos — Lineal, target invertido

```javascript
const chuProj   = (chuMtdBeh && DAYS_ELAPSED > 0)
  ? Math.round(chuMtdBeh / DAYS_ELAPSED * DAYS_IN_MONTH) : null;
const chuTarget = aprChuClose ? Math.round(aprChuClose * (1 - GROWTH_TARGET)) : null;
// target = cierre anterior × 0.90 (queremos bajar)
```

### Quick Ratio — NO SE PROYECTA

```javascript
const currMonQr = (newMtdBeh && recMtdBeh && chuMtdBeh > 0)
  ? +((newMtdBeh + recMtdBeh) / chuMtdBeh).toFixed(2) : null;
```

**Por qué no se proyecta:** el denominador (churned) es artificialmente bajo a inicio de mes porque los afiliados del mes anterior aún no tuvieron tiempo de re-vender. Proyectarlo daría un QR inflado/engañoso.

---

## Sistema de semáforos

```javascript
// Métricas positivas (activos, new, rec, ret):
function semaphore(proj, target) {
  if (!proj || !target) return '';
  const pct = proj / target;
  if (pct >= 1.00) return '🟢';
  if (pct >= 0.90) return '🟡';
  return '🔴';
}

// Inactivos (invertido — queremos menos churners):
function semaphoreInverted(proj, target) {
  if (!proj || !target) return '';
  if (proj <= target)        return '🟢';   // proyectamos menos churners que target
  if (proj <= target * 1.10) return '🟡';
  return '🔴';
}
```

---

## Footnote de proyecciones

Aparece debajo de la tabla de behaviour KPIs:

```
Cómo se calcula la proyección
· New, Recuperados e Inactivos: extrapolación lineal (MTD ÷ días_transcurridos × días_del_mes).
  Target = cierre mes anterior ±10%.
· Total Activos y Recurrentes: ratio-pace (valor_MTD × cierre_mes_anterior ÷ mismo_período_mes_anterior).
  Target = cierre mes anterior +10%.
· Quick Ratio: no se proyecta — denominador artificialmente bajo a inicio de mes.
· Las proyecciones asumen que el mix de países y canales se mantiene igual al mes anterior.
  A inicio de mes (< 5 días) la proyección es poco confiable.
```

---

## Consideraciones clave

### Churn a inicio de mes

Siempre alto artificialmente en los primeros 7-10 días. **No alertar churn standalone** en ese período. Usar QR Rolling 30d como indicador más robusto de salud del ecosistema.

### One month wonders vs Churn de nuevos

- **One month wonders**: afiliados cuya historia completa es exactamente un mes. Solo confirmable retrospectivamente (2 meses después).
- **Churn de nuevos**: afiliados de M-1 que no vendieron en M. Medible el mes siguiente, sin retrospectiva.
- Son conceptos **distintos**, no intercambiables.

### MLA en QR

Lanzamiento masivo marzo 2026 (56K nuevos, 878 churners → QR=64.86 artificial). Excluir MLA de gráficos QR hasta tener ≥3-4 meses de base estable (estimado jul/ago 2026).

---

## NMV — Modelo de atribución

```sql
-- Siempre usar este CASE para elegir la columna correcta:
CASE
  WHEN ORD_CREATED_DT >= '2026-04-01' THEN NMV_ENIGMA_TOTAL_AMT_LC  -- Enigma (vigente)
  ELSE NMV_TD7DCALIB_TOTAL_AMT_LC                                     -- TD7D (deprecado)
END AS NMV
```

- **Enigma** (desde 01/04/2026): modelo actual para medir NMV incremental del canal
- **TD7D** (hasta 31/03/2026): deprecado. Distribuía crédito entre touchpoints 7 días
- **LC (Last Click 24H)**: modelo de comisionamiento (distinto a ambos). Condiciones: (1) compra dentro de 24h del clic, (2) último clic antes de comprar fue en el link del afiliado

**LC ≠ TD7D ≠ Enigma** — tres métricas distintas para propósitos distintos.

---

## Landing — Tasa de conversión

```javascript
// Línea de conversión total en el gráfico:
tDatasets.push({
  label: '% Conversión →',
  data: cvData, type: 'line', yAxisID: 'ycv',
  borderColor: '#000000',         // negro
  backgroundColor: 'transparent',
  borderWidth: 2, pointRadius: 3, tension: .4, order: 1,
});
```

---

## Colores del dashboard

```javascript
const PALETTE = {
  active:     '#1a73e8',  // azul
  new:        '#34a853',  // verde
  rec:        '#f9ab00',  // ámbar
  churn:      '#ea4335',  // rojo
  ret:        '#9c27b0',  // púrpura
  qr:         '#00bcd4',  // cyan
  conversion: '#000000',  // negro (línea conversión landing)
};
```
