// Una celda de Sheets aguanta 50.000 caracteres; cortamos en 40.000 por margen.
const CHUNK = 40000;
const SENTINELA = '~';  // un pedazo que arranque con = o + lo tomaria como formula
const json = $('Armar snapshot').first().json.snapshotJson;
const items = [];
for (let i = 0; i < json.length; i += CHUNK) {
  items.push({ json: { snapshot: SENTINELA + json.slice(i, i + CHUNK) } });
}
if (!items.length) throw new Error('snapshot vacio, no hay nada para escribir');
return items;