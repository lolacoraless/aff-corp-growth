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
    if not rows:
        rows = []
    data[k] = rows
    if len(rows) == 0:
        vacias.append(k)

# Un token vencido hace que TODAS vuelvan vacias. Sin este guard se pisa el
# snapshot bueno con 32 listas vacias y el dashboard queda en blanco.
if len(vacias) >= len(KEYS) / 2.0:
    raise Exception('ABORTADO: ' + str(len(vacias)) + '/' + str(len(KEYS)) +
                    ' queries vacias. Vacias: ' + ', '.join(vacias))

# zoneinfo no esta permitido en el sandbox, asi que el offset de Buenos Aires va a mano.
ahora_utc = datetime.datetime.utcnow()
ahora_ba = ahora_utc - datetime.timedelta(hours=3)

snapshot = {
    "savedAt": ahora_utc.strftime('%Y-%m-%dT%H:%M:%S.000Z'),
    "savedAtDisplay": ahora_ba.strftime('%d/%m/%Y %H:%M'),
    "data": data,
}

# Sin default=str a proposito: si alguna fila no es serializable queremos que
# reviente aca y no que se escriba "<objeto>" en el Sheet sin que nadie lo note.
snapshot_json = json.dumps(snapshot, separators=(',', ':'))

filas = {}
for k in KEYS:
    filas[k] = len(data[k])

return {
    "snapshotJson": snapshot_json,
    "kb": len(snapshot_json) // 1024,
    "vacias": vacias,
    "filas": filas,
}
