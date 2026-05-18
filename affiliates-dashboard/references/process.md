# Proceso de Actualización y Publicación — Dashboard Afiliados

## Actualizar el dashboard (bq_refresh.ps1)

### Pre-requisitos

- VPN corporativa de MELI conectada
- `gcloud` CLI autenticado (`gcloud auth application-default login`)
- PowerShell

### Pasos

```powershell
cd C:\Users\lcorales\Downloads\Claude
.\bq_refresh.ps1
```

El script:
1. Calcula fechas dinámicas (YEST, CUR, PREV, PREV_DAY, M2, M3, W8)
2. Lanza 14 queries en paralelo vía `bq query --format=json`
3. Parsea resultados con `Parse-BQResult`
4. Construye hash `$data` con arrays por site
5. Embebe `window.__PRELOADED__ = {...}` en línea 7 del HTML
6. Guarda HTML actualizado

**Duración típica:** 2-4 minutos

---

## Publicar en Grid

**Doc ID:** `01KRE46H4452DPPVSYM5BKXJ14`
**URL:** `https://grid.adminml.com/d/01KRE46H4452DPPVSYM5BKXJ14/view`

⚠️ **Siempre usar `skip_version_check: true`** para evitar error HTTP 426 de versión mismatch.

```bash
curl -s -X POST "https://grid.melioffice.com/api/v1/engine/run" \
  -F 'config={"skill_version":"3.6.0","skip_version_check":true,"doc_id":"01KRE46H4452DPPVSYM5BKXJ14","title":"Dashboard Afiliados Corps"}' \
  -F "file=@C:/Users/lcorales/Downloads/Claude/affiliates-dashboard-grid.html"
```

**Interpretar respuesta:**
- `ok: true` → publicado, mostrar `view_url`
- `confirmation_required` → re-enviar con `"confirmed": true`
- `disambiguation` → resolver candidatos antes de re-enviar
- HTTP 426 → agregar `skip_version_check: true`

---

## Checklist de actualización completa

```
□ VPN conectada
□ .\bq_refresh.ps1   (esperar ~3 min)
□ Verificar output: "=== DONE ===" sin errores críticos
□ Publicar en Grid con skip_version_check:true
□ Verificar ok:true en respuesta
□ Abrir view_url y revisar datos
□ (Opcional) Redactar y enviar mensaje de pulso en Slack
```

---

## Mensaje de pulso semanal (Slack)

### Canales

| Canal | ID | Uso |
|-------|----|-----|
| affiliates corp | `C05THPGTR89` | Mensaje oficial al equipo |
| Delfina Cadenas (DM) | `U019LKLQGJ2` | Pruebas antes de mandar al canal |

### Estructura del mensaje

```
[Nuevo dashboard disponible → https://grid.adminml.com/d/01KRE46H4452DPPVSYM5BKXJ14/view]

📊 Comportamiento de afiliados | Día X de 31 | [fecha DD/M]
Nota: Todavía no está el 100% de las métricas actualizadas de ayer [DD/M]
Quick Ratio = (new + recuperados) / churners | Rolling 30d: (new_30d + rec_30d) / churned_30d

[Site] | Activos | New | Churners | QR cal.
MLB | X (🟢/🟡/🔴 vs target X) | X (semáforo) | X (semáforo) | X.XX
MLM | ...
MLC | ...
MLA | ...

📈 Quick Ratio Rolling 30d (excl. MLA)
MLB: X.XX | MLM: X.XX | MLC: X.XX

📋 Registros MTD | [mes]
[Site] | Registros | vs Target
MLB | X (🟢/🟡/🔴) | XX% del target
...
Principal offender: [POM/Direct] pesa el XX% y está YY% abajo del pace esperado

⚡ Accionables
- Accionable 1 (ETA DD/M)
- Accionable 2 (ETA TBD / Accionables en base a findings - TBD)
```

### Envío vía Slack MCP

```json
{ "channel": "C05THPGTR89", "text": "[mensaje completo]" }
```

---

## Estructura del HTML — puntos clave

### window.__PRELOADED__

Está en la **línea 7** del HTML entre los marcadores:
```html
<!-- __PRELOADED_START__ -->
<script>window.__PRELOADED__ = {...}</script>
<!-- __PRELOADED_END__ -->
```

`bq_refresh.ps1` reemplaza el bloque completo en cada refresh.

### Funciones principales

| Función | Descripción |
|---------|-------------|
| `renderBehaviourKpis(site)` | Tabla MTD + proyecciones + semáforos |
| `renderBehaviourChart(site)` | Gráfico histórico activos/new/rec/chu/ret |
| `renderQRChart(site)` | QR calendario y rolling |
| `renderRegistrationsChart(site)` | Registros por canal |
| `renderLandingChart(site)` | Visitas landing + línea conversión (negra) |
| `renderNmvChart(site)` | NMV mensual y MTD |

---

## Errores comunes y soluciones

### TDZ (Temporal Dead Zone) crash

**Síntoma:** Todos los gráficos desaparecen. DevTools muestra:
```
ReferenceError: Cannot access 'retMtd' before initialization
```

**Causa:** `const` no hace hoisting. Variable referenciada antes de su declaración.
**Caso conocido:** `retMtd` referenciaba `retMtdBeh` que estaba declarada más abajo.

**Diagnóstico:** DevTools → Console → buscar ReferenceError → identificar variable → reordenar.
**Solución:** Mantener orden correcto (ver SKILL.md → "Orden de declaración de variables").

### "File has been modified since read"

**Síntoma:** Herramienta Edit falla.
**Solución:** Siempre leer el archivo con `Read` antes de cualquier `Edit`.

### Grid HTTP 426 (version mismatch)

**Causa:** El skill local dice versión 3.6.0 pero el servidor está más nuevo.
**Solución:** Incluir `"skip_version_check": true` en el payload. **Siempre.**

### bq_refresh.ps1 falla o tarda demasiado

- Verificar VPN conectada
- Verificar `gcloud auth application-default login` activo
- Las queries corren en paralelo; si una falla el resto continúa
- Revisar errores por query en la salida del script
