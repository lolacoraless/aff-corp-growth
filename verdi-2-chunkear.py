# Una celda de Sheets aguanta 50.000 caracteres; cortamos en 40.000 por margen.
CHUNK = 40000
SENTINELA = '~'   # un pedazo que arranque con = o + lo tomaria como formula

texto = _('Armar snapshot').first().json.snapshotJson

items = []
i = 0
while i < len(texto):
    items.append({"snapshot": SENTINELA + texto[i:i + CHUNK]})
    i = i + CHUNK

if len(items) == 0:
    raise Exception('snapshot vacio, no hay nada para escribir')

return items
