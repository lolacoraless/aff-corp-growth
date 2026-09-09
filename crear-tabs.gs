function crearTabs() {
  var TABS = ["g_behaviour", "g_registros", "g_landing", "g_nmv", "g_activacion", "g_churn", "g_retencion", "g_varios", "g_linkgen", "g_meta"];
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var n = 0;
  TABS.forEach(function (t) {
    var h = ss.getSheetByName(t);
    if (!h) { h = ss.insertSheet(t); n++; }
    h.getRange('A1').setValue('_q');
    h.getRange('B1').setValue('r');
  });
  Logger.log('creadas: ' + n + ' | total: ' + TABS.length);
}