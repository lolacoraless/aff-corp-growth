function crearTabs() {
  var TABS = [
    "behaviour",
    "beh_mtd",
    "beh_pacing",
    "qr_rolling",
    "registrations",
    "reg_mtd",
    "reg_pacing",
    "landing_traffic",
    "landing_pacing",
    "spend_pom",
    "nmv_monthly",
    "nmv_lt_by_status",
    "nmv_weekly",
    "nmv_mtd",
    "nmv_pacing",
    "data_freshness",
    "act1",
    "act2",
    "act_source",
    "act_new_days",
    "churn",
    "churn_comp",
    "churn_mtd",
    "earnings_buckets",
    "retention_by_segment",
    "retention_cohort_curve",
    "link_gen_monthly",
    "link_gen_daily",
    "link_gen_mtd_comp",
    "link_gen_by_segment",
    "link_gen_earnings_by_status",
    "mkt_context",
    "__meta__"
  ];
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var creadas = 0;
  TABS.forEach(function (nombre) {
    var h = ss.getSheetByName(nombre);
    if (!h) { h = ss.insertSheet(nombre); creadas++; }
    // el nodo de Sheets mapea la columna por el header, asi que 'r' va siempre en A1
    h.getRange('A1').setValue('r');
  });
  Logger.log('tabs creadas: ' + creadas + ' | total: ' + TABS.length);
}