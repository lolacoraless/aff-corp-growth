#!/usr/bin/env python3
"""
Carga el snapshot del dashboard de Afiliados.

Desde que el refresh lo hace Verdi Flows (10:17, 12:17 y 14:17), la fuente viva
es un Google Sheet: la tab "snapshot" tiene todas las queries juntas, una fila
por registro, con la fila serializada por TO_JSON_STRING. Verdi la reescribe
entera de una vez y solo si llegaron todas las consultas, asi que nunca queda a
medias. Los HTML locales quedan de respaldo y pueden estar atrasados.

Orden: tab snapshot -> tabs g_* del flow anterior (solo si estan completas) ->
el HTML local mas nuevo. Siempre se informa de donde salieron los datos y de
cuando son, para que nadie lea numeros viejos creyendo que son de hoy.

Requiere VPN de MELI: la lectura del Sheet va por la API de Grid, que resuelve
la identidad en el edge.
"""
import json
import os
import re
import urllib.request

SHEET_ID  = '14GoBnB6GgnUYsCBY_nx82DUL2hZEmFXbDR4dByketqc'
DOC_ID    = '01KRE46H4452DPPVSYM5BKXJ14'
GRID      = 'https://grid.melioffice.com'
TAB_SNAPSHOT = 'snapshot'
HTMLS = [r'C:\Users\lcorales\Downloads\Claude\affiliates-dashboard-v2.html',
         r'C:\Users\lcorales\Downloads\Claude\affiliates-dashboard-grid.html']

# Tabs del flow anterior, una por familia. Solo se leen si falta la tab snapshot.
GRUPOS = {
    'g_behaviour':  ['behaviour', 'beh_mtd', 'beh_pacing', 'qr_rolling'],
    'g_registros':  ['registrations', 'reg_mtd', 'reg_pacing'],
    'g_landing':    ['landing_traffic', 'landing_pacing'],
    'g_nmv':        ['nmv_monthly', 'nmv_weekly', 'nmv_mtd', 'nmv_pacing', 'nmv_lt_by_status'],
    'g_activacion': ['act1', 'act2', 'act_source', 'act_new_days'],
    'g_churn':      ['churn', 'churn_comp', 'churn_mtd', 'earnings_buckets'],
    'g_retencion':  ['retention_by_segment', 'retention_cohort_curve'],
    'g_varios':     ['spend_pom', 'data_freshness', 'mkt_context'],
    'g_linkgen':    ['link_gen_monthly', 'link_gen_daily', 'link_gen_mtd_comp',
                     'link_gen_by_segment', 'link_gen_earnings_by_status'],
}
TAB_META = 'g_meta'
CLAVES = [k for ks in GRUPOS.values() for k in ks]
# Series que nunca vienen vacias: si falta alguna, el snapshot esta roto.
NUCLEO = ['behaviour', 'registrations', 'nmv_monthly']


def _leer_tab(tab, timeout=60):
    url = f'{GRID}/api/v1/sheets/{SHEET_ID}?doc_id={DOC_ID}&range={tab}!A:B'
    req = urllib.request.Request(url, headers={'x-api-source': 'office'})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        filas = json.loads(r.read().decode('utf-8')).get('values', [])
    # la primera fila es el header que escribe el nodo de Sheets
    return [f for f in filas[1:] if len(f) > 1 and f[1]]


def _normalizar(v):
    """
    BigQuery serializa los NUMERIC como string para no perder precision, y las
    columnas vienen con el case original. El pipeline de PowerShell ya hacia las
    dos cosas (Parse-BQResult), y el resto de los scripts cuenta con eso: claves
    en minuscula y numeros como numeros.
    """
    if isinstance(v, list):
        return [_normalizar(x) for x in v]
    if isinstance(v, dict):
        return {k.lower(): _normalizar(x) for k, x in v.items()}
    if isinstance(v, str) and v.strip() != '':
        try:
            f = float(v)
            return int(f) if f.is_integer() and abs(f) < 2**53 else f
        except ValueError:
            return v
    return v


def _armar(filas):
    """Filas [_q, r] -> (data, info). Exige exactamente una fila __meta__."""
    metas = [f for f in filas if f[0] == '__meta__']
    if len(metas) != 1:
        raise RuntimeError(f'{len(metas)} filas __meta__ en el Sheet (tiene que haber 1)')
    data = {k: [] for k in CLAVES}
    for q, r in (f[:2] for f in filas):
        if q in data:
            data[q].append(_normalizar(json.loads(r)))
    return data, json.loads(metas[0][1])


def _desde_snapshot():
    data, info = _armar(_leer_tab(TAB_SNAPSHOT))
    # Verdi escribe todo junto o nada, asi que una query vacia puede ser
    # legitima (un MTD el dia 1 del mes). Solo el nucleo tiene que estar.
    rotas = [k for k in NUCLEO if not data[k]]
    if rotas:
        raise RuntimeError('la tab snapshot no trae ' + ', '.join(rotas))
    return data, info.get('savedAt', '')


def _desde_tabs_viejas():
    filas = []
    for tab in list(GRUPOS) + [TAB_META]:
        filas += _leer_tab(tab)
    data, info = _armar(filas)
    # Estas tabs se escribian de a una: una vacia es una corrida que se corto.
    vacias = [k for k in CLAVES if not data[k]]
    if vacias:
        raise RuntimeError('tabs g_* incompletas: ' + ', '.join(vacias))
    return data, info.get('savedAt', '')


def _desde_html():
    mejor = None
    for ruta in HTMLS:
        if not os.path.exists(ruta):
            continue
        with open(ruta, encoding='utf-8-sig') as f:
            m = re.search(r'window\.__PRELOADED__\s*=\s*(\{.*?\});</script>', f.read(), re.DOTALL)
        if not m:
            continue
        snap = json.loads(m.group(1))
        if mejor is None or snap.get('savedAt', '') > mejor[1]:
            mejor = (snap['data'], snap.get('savedAt', ''), os.path.basename(ruta))
    if mejor is None:
        raise RuntimeError('no hay ningun HTML local con snapshot')
    return mejor


def cargar(verbose=True):
    """
    Devuelve (data, savedAt, fuente). fuente es 'sheet', 'sheet-tabs-viejas' o 'html'.
    Entre el Sheet y el HTML local gana el mas nuevo: el HTML puede estar mas al dia
    si alguien corrio bq_refresh.ps1 a mano mientras Verdi fallaba.
    """
    motivos, candidatos = [], []
    for fuente, leer in (('sheet', _desde_snapshot), ('sheet-tabs-viejas', _desde_tabs_viejas)):
        try:
            data, saved = leer()
            candidatos.append((saved, fuente, data, 'Google Sheet'))
            break
        except Exception as e:
            motivos.append(f'{fuente}: {e}')
    try:
        data, saved, archivo = _desde_html()
        candidatos.append((saved, 'html', data, archivo))
    except Exception as e:
        motivos.append(f'html: {e}')
    if not candidatos:
        raise RuntimeError('no hay ninguna fuente disponible: ' + ' | '.join(motivos))
    saved, fuente, data, origen = max(candidatos, key=lambda c: c[0][:19])

    if verbose:
        for m in motivos:
            print(f'[fuente] No se pudo usar {m}')
        if fuente == 'html':
            print(f'[fuente] Se usa el HTML local {origen}: es lo mas nuevo que hay, pero puede estar atrasado.')
        etiqueta = {'sheet': 'Google Sheet, tab snapshot (Verdi, 10:17/12:17/14:17)',
                    'sheet-tabs-viejas': 'Google Sheet, tabs g_* del flow anterior (pueden estar viejas)',
                    'html': 'HTML local (respaldo)'}[fuente]
        print(f'[fuente] {etiqueta} · snapshot {saved[:19].replace("T", " ")} UTC')
    return data, saved, fuente


if __name__ == '__main__':
    import sys
    sys.stdout.reconfigure(encoding='utf-8')
    d, s, f = cargar()
    print(f'\nfuente={f}  savedAt={s}')
    for k in sorted(d):
        print(f'  {k:<30} {len(d[k]):>6} filas')
