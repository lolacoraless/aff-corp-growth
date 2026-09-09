
const KEYS = ["behaviour", "beh_mtd", "beh_pacing", "qr_rolling", "registrations", "reg_mtd", "reg_pacing", "landing_traffic", "landing_pacing", "spend_pom", "nmv_monthly", "nmv_lt_by_status", "nmv_weekly", "nmv_mtd", "nmv_pacing", "data_freshness", "act1", "act2", "act_source", "act_new_days", "churn", "churn_comp", "churn_mtd", "earnings_buckets", "retention_by_segment", "retention_cohort_curve", "link_gen_monthly", "link_gen_daily", "link_gen_mtd_comp", "link_gen_by_segment", "link_gen_earnings_by_status", "mkt_context"];
const data = {}, vacias = [];
for (const k of KEYS) {
  let rows = [];
  try { rows = $('agg_' + k).first().json.data || []; } catch (e) { rows = []; }
  data[k] = rows;
  if (!rows.length) vacias.push(k);
}
if (vacias.length >= KEYS.length / 2) {
  throw new Error('ABORTADO: ' + vacias.length + '/' + KEYS.length +
                  ' queries vacias. No se escribe el Sheet. Vacias: ' + vacias.join(', '));
}
const now = new Date();
const snapshotJson = JSON.stringify({
  savedAt: now.toISOString(),
  savedAtDisplay: now.toLocaleString('es-AR', { timeZone: 'America/Argentina/Buenos_Aires' }),
  data,
});
return [{ json: { snapshotJson, kb: Math.round(snapshotJson.length/1024), vacias,
                  filas: Object.fromEntries(KEYS.map(k => [k, data[k].length])) } }];