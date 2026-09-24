#!/usr/bin/env python3
"""
Genera verdi-dashboard-v4.json, el refresh automatico del dashboard de Afiliados
en Verdi Flows (n8n 2.0.3). La SQL sale de queries-v2/grupos/*.sql: si cambia una
query, se edita ahi y se vuelve a correr este script.

    python generar_verdi_v4.py

Por que la v4 (fallas del 21 al 24/09/2026, revisadas en JOBS_BY_USER):

1. BigQuery rechazaba los jobs con quotaExceeded ("max number of jobs that can
   be queued per project"). Es una cuota de meli-bi-data, compartida con todos,
   y se llena en punto, cuando disparan los schedules de medio MELI: los 22
   rechazos del periodo cayeron entre XX:00 y XX:02. Los reintentos nativos de
   n8n esperan 5 s como mucho y caian en el mismo pico.
2. En meli-bi-data cada job recibe ~8-20 slots, sea chico o grande. La v2 corria
   las 10 familias de a una (n8n ejecuta las ramas en serie), asi que tardaba la
   suma: 25-35 min. Verdi corta cerca de los 30, y el Sheet quedaba con tabs de
   dias distintos bajo un g_meta viejo.
   Juntar todo en un solo job no sirve: recibe los mismos ~9 slots y tarda mas de
   35 min (probado el 24/09).

Lo que hace la v4:
- Las 10 familias van como 10 items a UN nodo de BigQuery. Ese nodo inserta todos
  los jobs de sus items y despues espera a todos (executeQuery.operation.ts), asi
  que corren en paralelo, cada uno con su parte de slots: el tiempo pasa a ser el
  de la familia mas lenta.
- Dispara a los :17, lejos del pico de en punto.
- Hasta 3 intentos, con esperas de 2 y 6 min entre si. El timeout de n8n cuenta
  desde el inicio de la ejecucion, esperas incluidas, asi que el peor caso tiene
  que entrar en 30 min.
- El Sheet se toca recien cuando llegaron las 10 familias sin errores, y se
  escribe una sola vez: 1 clear + 1 append en la tab "snapshot" (antes 9 + 9).
- Mail al terminar bien, y mail si fallan los 3 intentos.
"""
import io
import json
import os
import sys
import uuid

AQUI = os.path.dirname(os.path.abspath(__file__))
GRUPOS_DIR = os.path.join(AQUI, 'queries-v2', 'grupos')
GRUPOS = ['g_behaviour', 'g_registros', 'g_landing', 'g_nmv', 'g_activacion',
          'g_churn', 'g_retencion', 'g_varios', 'g_linkgen', 'g_meta']

# Una clave por familia que nunca viene vacia. Si falta alguna, esa familia no
# llego entera y no se escribe nada.
TESTIGOS = ['behaviour', 'registrations', 'landing_traffic', 'nmv_monthly', 'act1',
            'churn', 'retention_by_segment', 'data_freshness', 'link_gen_monthly', '__meta__']

SHEET = '14GoBnB6GgnUYsCBY_nx82DUL2hZEmFXbDR4dByketqc'
TAB = 'snapshot'
MAIL = 'lola.corales@mercadolibre.com'
DASH = 'https://grid.adminml.com/d/01KRE46H4452DPPVSYM5BKXJ14/view'
FLOW = 'https://web.furycloud.io/ai/verdi-flows/workflow/qijF6v2nteCD7uAy'
PROYECTO_BQ = 'meli-bi-data'
CRED = {"googleGenericOAuth2Api": {"id": "REEMPLAZAR_ID_CREDENCIAL",
                                   "name": "Credenciales Lola Corales"}}
ESPERAS = [2, 6]  # minutos entre intentos
SUFIJOS = ['', ' (2do intento)', ' (3er intento)']


def leer_grupos():
    sqls = {}
    for g in GRUPOS:
        with io.open(os.path.join(GRUPOS_DIR, g + '.sql'), encoding='utf-8') as f:
            sql = f.read().replace('\r\n', '\n').strip()
        # Van dentro de un raw string r'''...''' de BigQuery, y el nodo de n8n
        # evalua cualquier {{ }} que encuentre en la SQL.
        assert "'''" not in sql, g + ": la SQL tiene ''' y rompe el literal"
        assert '{{' not in sql, g + ': la SQL tiene {{ y n8n lo tomaria como expresion'
        sqls[g] = sql
    return sqls


def sql_preparar(sqls):
    filas = []
    for i, g in enumerate(GRUPOS):
        nombres = (" AS grupo", " AS sql") if i == 0 else ("", "")
        filas.append("  STRUCT('%s'%s, r'''\n%s\n'''%s)" % (g, nombres[0], sqls[g], nombres[1]))
    return ("-- Una fila por familia de queries. El nodo siguiente recibe las 10 filas y\n"
            "-- lanza los 10 jobs a la vez. La fuente de estas SQL es queries-v2/grupos/\n"
            "-- en el repo aff-corp-growth: se editan ahi y se regenera con\n"
            "-- generar_verdi_v4.py.\n"
            "SELECT grupo, sql FROM UNNEST([\n" + ",\n".join(filas) + "\n])")


def expr_datos():
    return "($json.data || [])"


def expr_gate():
    # Nombre de tab inexistente = el nodo de Sheets falla antes de escribir nada
    # (spreadsheetGetSheet tira "Sheet with name ... not found") y el item sale
    # por la salida de error hacia el proximo intento.
    d = expr_datos()
    testigos = json.dumps(TESTIGOS)
    return ("={{ (%s.some(x => x.error !== undefined) || %s.some(k => !%s.some(x => x._q === k))) "
            "? 'NO SE ESCRIBE - faltan consultas' : '%s' }}" % (d, testigos, d, TAB))


def expr_errores():
    d = expr_datos()
    testigos = json.dumps(TESTIGOS)
    return ("{{ [].concat(%s.filter(x => x && x.error !== undefined).map(x => x.error), "
            "$json.error !== undefined ? [$json.error] : [])"
            ".map(e => typeof e === 'string' ? e : JSON.stringify(e)).join(' | ').slice(0, 1500) "
            "|| 'sin detalle en el item, ver Executions en Verdi' }}"
            "<br>Familias que no llegaron: "
            "{{ %s.length ? (%s.filter(k => !%s.some(x => x._q === k)).join(', ') || 'ninguna') : 'no aplica' }}"
            % (d, d, testigos, d))


def armar(sqls, con_esperas=True):
    nodes, conns = [], {}

    def conectar(a, b, salida=0):
        c = conns.setdefault(a, {"main": []})
        while len(c["main"]) <= salida:
            c["main"].append([])
        c["main"][salida].append({"node": b, "type": "main", "index": 0})

    def nodo(nombre, tipo, ver, params, x, y, nota=None, **extra):
        n = {"parameters": params, "id": str(uuid.uuid4()), "name": nombre,
             "type": "n8n-nodes-base." + tipo, "typeVersion": ver, "position": [x, y]}
        if nota:
            n["notes"], n["notesInFlow"] = nota, True
        n.update(extra)
        nodes.append(n)
        return nombre

    doc = {"__rl": True, "mode": "id", "value": SHEET}
    prep_sql = sql_preparar(sqls)

    disparo = nodo("Disparo 10:17, 12:17 y 14:17", "scheduleTrigger", 1.2,
                   {"rule": {"interval": [{"triggerAtHour": h, "triggerAtMinute": 17}
                                          for h in (10, 12, 14)]}},
                   -300, 0, nota="A los :17 y no en punto: en punto se llena la cola de meli-bi-data")

    ok = "Aviso: OK"
    fallo = "Aviso: falló"
    entrada = disparo
    errores_previos = []  # salidas de error del intento anterior
    for k, suf in enumerate(SUFIJOS):
        y = k * 420
        if k:
            if con_esperas:
                espera = nodo("Esperar %d min" % ESPERAS[k - 1], "wait", 1.1,
                              {"resume": "timeInterval", "amount": ESPERAS[k - 1], "unit": "minutes"},
                              -300, y, webhookId=str(uuid.uuid4()))
                for origen, salida in errores_previos:
                    conectar(origen, espera, salida)
                entrada = espera
            else:
                entrada = None

        prep = nodo("Preparar consultas" + suf, "googleBigQuery", 2.1,
                    {"projectId": {"__rl": True, "mode": "id", "value": PROYECTO_BQ},
                     "sqlQuery": prep_sql, "options": {}},
                    -40, y, retryOnFail=True, maxTries=3, waitBetweenTries=5000,
                    onError="continueErrorOutput", executeOnce=True, credentials=CRED,
                    nota="Devuelve las 10 SQL, una por fila" if not k else None)
        if entrada:
            conectar(entrada, prep)
        else:
            for origen, salida in errores_previos:
                conectar(origen, prep, salida)

        # Sin retryOnFail a proposito: si un job falla, n8n reintentaria el nodo
        # entero y relanzaria los 10 jobs mientras los otros 9 siguen corriendo.
        cons = nodo("Consultar BigQuery" + suf, "googleBigQuery", 2.1,
                    {"projectId": {"__rl": True, "mode": "id", "value": PROYECTO_BQ},
                     "sqlQuery": "={{ $json.sql }}", "options": {}},
                    220, y, onError="continueRegularOutput", credentials=CRED,
                    nota="10 jobs en paralelo, uno por familia" if not k else None)
        junt = nodo("Juntar filas" + suf, "aggregate", 1,
                    {"aggregate": "aggregateAllItemData", "options": {}}, 480, y)
        vac = nodo("Vaciar snapshot" + suf, "googleSheets", 4.7,
                   {"operation": "clear", "documentId": doc,
                    "sheetName": {"__rl": True, "mode": "name", "value": expr_gate()}},
                   740, y, onError="continueErrorOutput", credentials=CRED,
                   nota="Solo si llegaron las 10 familias sin error" if not k else None)
        abr = nodo("Abrir filas" + suf, "splitOut", 1,
                   {"fieldToSplitOut": "data", "options": {}}, 1000, y)
        esc = nodo("Escribir snapshot" + suf, "googleSheets", 4.7,
                   {"operation": "append", "documentId": doc,
                    "sheetName": {"__rl": True, "mode": "name", "value": TAB},
                    "columns": {"value": {}, "mappingMode": "autoMapInputData", "matchingColumns": [],
                                "schema": [{"id": c, "type": "string", "display": True, "removed": False,
                                            "required": False, "displayName": c, "defaultMatch": False,
                                            "canBeUsedToMatch": True} for c in ("_q", "r")],
                                "attemptToConvertTypes": False, "convertFieldsToString": False},
                    "options": {}},
                   1260, y, onError="continueErrorOutput", credentials=CRED)
        conectar(prep, cons, 0)
        conectar(cons, junt)
        conectar(junt, vac)
        conectar(vac, abr, 0)
        conectar(abr, esc)
        conectar(esc, ok, 0)
        errores_previos = [(prep, 1), (vac, 1), (esc, 1)]

    for origen, salida in errores_previos:
        conectar(origen, fallo, salida)

    hora = "{{ $now.setZone('America/Argentina/Buenos_Aires').toFormat('dd/MM HH:mm') }}"
    ultimo = lambda base: " : ".join(
        ["$('%s%s').isExecuted ? $('%s%s').first().json.data.length" % (base, s, base, s)
         for s in reversed(SUFIJOS[1:])] + ["$('%s').first().json.data.length" % base])
    intento = " : ".join(["$('Juntar filas%s').isExecuted ? %d" % (s, i + 1)
                          for i, s in reversed(list(enumerate(SUFIJOS))) if i] + ["1"])

    def mail(asunto, cuerpo):
        return {"sendTo": MAIL, "subject": asunto, "emailType": "html", "message": cuerpo,
                "options": {"appendAttribution": False}}

    nodo(ok, "gmail", 2.2,
         mail("=Dashboard Afiliados actualizado · " + hora,
              "=Se escribieron {{ " + ultimo("Juntar filas") + " }} filas en el Sheet "
              "(intento {{ " + intento + " }} de 3).<br><br>Dashboard: " + DASH),
         1520, 0, executeOnce=True, credentials=CRED)
    nodo(fallo, "gmail", 2.2,
         mail("=FALLÓ el refresh del dashboard · " + hora,
              "=Ninguno de los 3 intentos terminó bien (el último arrancó unos 8 minutos "
              "después del primero).<br><br>"
              "El Sheet no se toca hasta tener todas las consultas, así que <b>el dashboard sigue "
              "mostrando la última actualización completa</b>. Si el error fue al escribir, la tab "
              "snapshot puede haber quedado vacía: en ese caso el dashboard usa los datos que trae "
              "embebidos.<br><br>El próximo horario programado vuelve a intentar solo.<br><br>"
              "Error del último intento: " + expr_errores() + "<br><br>Flow: " + FLOW),
         1520, 840, executeOnce=True, credentials=CRED)

    nombre = "Dashboard Afiliados · refresh v4" + ("" if con_esperas else " (sin esperas)")
    return {"name": nombre, "nodes": nodes, "pinData": {}, "connections": conns,
            "settings": {"executionOrder": "v1", "callerPolicy": "workflowsFromSameOwner",
                         "executionTimeout": -1, "saveExecutionProgress": True,
                         "saveDataErrorExecution": "all"},
            "versionId": str(uuid.uuid4()), "meta": {"templateCredsSetupCompleted": True},
            "tags": []}


def validar(wf, sqls):
    nombres = [n["name"] for n in wf["nodes"]]
    assert len(nombres) == len(set(nombres)), "nombres repetidos"
    nombres = set(nombres)
    destinos = {d["node"] for c in wf["connections"].values() for s in c["main"] for d in s}
    assert destinos <= nombres, "conexiones a nodos inexistentes: %s" % (destinos - nombres)
    assert set(wf["connections"]) <= nombres, "conexiones desde nodos inexistentes"

    trig = [n["name"] for n in wf["nodes"] if n["type"].endswith("scheduleTrigger")][0]
    vistos, pila = set(), [trig]
    while pila:
        a = pila.pop()
        if a not in vistos:
            vistos.add(a)
            pila += [d["node"] for s in wf["connections"].get(a, {"main": []})["main"] for d in s]
    assert vistos == nombres, "nodos huerfanos: %s" % (nombres - vistos)

    def hay_ciclo(a, camino):
        return a in camino or any(hay_ciclo(d["node"], camino | {a})
                                  for s in wf["connections"].get(a, {"main": []})["main"] for d in s)
    assert not hay_ciclo(trig, set()), "hay un ciclo"

    por_nombre = {n["name"]: n for n in wf["nodes"]}
    for n in wf["nodes"]:
        if n.get("onError") == "continueErrorOutput":
            salidas = wf["connections"][n["name"]]["main"]
            assert len(salidas) == 2 and salidas[1], n["name"] + ": salida de error sin conectar"
        if n.get("retryOnFail"):
            assert n.get("maxTries", 3) <= 5 and n.get("waitBetweenTries", 1000) <= 5000
        # un nodo de una sola entrada no puede recibir de las dos salidas del mismo nodo:
        # correria dos veces
        if n["name"] in wf["connections"]:
            for s in wf["connections"][n["name"]]["main"]:
                assert len({d["node"] for d in s}) == len(s)
        if n["name"].startswith("Preparar consultas"):
            sql = n["parameters"]["sqlQuery"]
            for g, s in sqls.items():
                assert "r'''\n" + s + "\n'''" in sql, g + " no esta entera en " + n["name"]
    # el Sheet solo se toca desde los nodos de Sheets, y todo clear lleva la compuerta
    for n in wf["nodes"]:
        if n["type"].endswith("googleSheets") and n["parameters"]["operation"] == "clear":
            assert "NO SE ESCRIBE" in n["parameters"]["sheetName"]["value"], n["name"] + " sin compuerta"
    # ninguna salida de error queda apuntando a un nodo que escriba sin compuerta
    for a, c in wf["connections"].items():
        if len(c["main"]) > 1:
            for d in c["main"][1]:
                t = por_nombre[d["node"]]
                assert not (t["type"].endswith("googleSheets") and t["parameters"]["operation"] == "append")


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    sqls = leer_grupos()
    for con_esperas, archivo in ((True, "verdi-dashboard-v4.json"),
                                 (False, "verdi-dashboard-v4-sin-esperas.json")):
        wf = armar(sqls, con_esperas)
        validar(wf, sqls)
        with io.open(os.path.join(AQUI, archivo), "w", encoding="utf-8", newline="\n") as f:
            json.dump(wf, f, ensure_ascii=False, indent=2)
        tipos = {}
        for n in wf["nodes"]:
            t = n["type"].split(".")[-1]
            tipos[t] = tipos.get(t, 0) + 1
        print("%-38s %2d nodos  %s" % (archivo, len(wf["nodes"]), tipos))
