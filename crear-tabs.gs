// Crea la tab que escribe el refresh de Verdi (v4). Las tabs g_* son del flow
// anterior: el dashboard solo las lee si falta "snapshot", y se pueden borrar
// una vez que la v4 haya corrido bien.
function crearTabs() {
  var TABS = ["snapshot"];
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