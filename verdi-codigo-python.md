# Código para los 2 nodos VerdiCode — versión Python

Según la doc del sandbox, el modo Python usa `_('NombreNodo')` en vez de `$('NombreNodo')`,
y se devuelve con `return`. Límites: 5 segundos y ~20 MB.

Con el payload ya reducido a ~0,67 MB (unas 5.000 filas entre las 32 queries) ambos
nodos quedan holgados dentro de esos límites.

---

## Nodo 1 — `Armar snapshot`

```python
import json
import datetime

KEYS = ["behaviour","beh_mtd","beh_pacing","qr_rolling","registrations","reg_mtd",
        "reg_pacing","landing_traffic","landing_pacing","spend_pom","nmv_monthly",
        "nmv_lt_by_status","nmv_weekly","nmv_mtd","nmv_pacing","data_freshness",
        "act1","act2","act_source","act_new_days","churn","churn_comp","churn_mtd",
        "earnings_buckets","retention_by_segment","retention_cohort_curve",
        "link_gen_monthly","link_gen_daily","link_gen_mtd_comp","link_gen_by_segment",
        "link_gen_earnings_by_status","mkt_context"]

data = {}
vacias = []
for k in KEYS:
    try:
        rows = _('agg_' + k).first().json.data
    except Exception:
        rows = None
    rows = rows if rows else []
    data[k] = rows
    if len(rows) == 0:
        vacias.append(k)

# Un token vencido hace que TODAS vuelvan vacias. Sin este guard se pisa el
# snapshot bueno con 32 listas vacias y el dashboard queda en blanco.
if len(vacias) >= len(KEYS) / 2.0:
    raise Exception('ABORTADO: ' + str(len(vacias)) + '/' + str(len(KEYS)) +
                    ' queries vacias. No se escribe el Sheet. Vacias: ' + ', '.join(vacias))

# zoneinfo no esta permitido en el sandbox: el offset de Buenos Aires va a mano.
ahora_utc = datetime.datetime.utcnow()
ahora_ba  = ahora_utc - datetime.timedelta(hours=3)

snapshot = {
    "savedAt": ahora_utc.strftime('%Y-%m-%dT%H:%M:%S.000Z'),
    "savedAtDisplay": ahora_ba.strftime('%d/%m/%Y %H:%M'),
    "data": data,
}
snapshot_json = json.dumps(snapshot, separators=(',', ':'), default=str)

return {
    "snapshotJson": snapshot_json,
    "kb": len(snapshot_json) // 1024,
    "vacias": vacias,
    "filas": dict([(k, len(data[k])) for k in KEYS]),
}
```

---

## Nodo 2 — `Chunkear`

```python
# Una celda de Sheets aguanta 50.000 caracteres; cortamos en 40.000 por margen.
CHUNK = 40000
SENTINELA = '~'   # un pedazo que arranque con = o + lo tomaria como formula

texto = _('Armar snapshot').first().json.snapshotJson

items = []
i = 0
while i < len(texto):
    items.append({"snapshot": SENTINELA + texto[i:i + CHUNK]})
    i += CHUNK

if len(items) == 0:
    raise Exception('snapshot vacio, no hay nada para escribir')

return items
```

---

## Si el nodo resulta ser JavaScript

Está en `verdi-codigo-snapshot.js` y `verdi-codigo-chunkear.js`.
La diferencia es `$('Nodo')` en vez de `_('Nodo')`.
