#!/usr/bin/env python3
"""
Carga el snapshot del dashboard de Afiliados.

Desde que el refresh lo hace Verdi Flows (10, 12 y 14 hs), la fuente viva es un
Google Sheet: una tab por familia de queries, con cada fila serializada por
TO_JSON_STRING. El HTML local queda de respaldo — lo escribe bq_refresh.ps1 a
mano, asi que puede estar varios dias atrasado.

Se intenta el Sheet primero y se cae al HTML si no responde. Siempre se informa
de donde salieron los datos y de cuando son, para que nadie lea numeros viejos
creyendo que son de hoy.

Requiere VPN de MELI: la lectura del Sheet va por la API de Grid, que resuelve
la identidad en el edge.
"""
import json
import re
import urllib.request

SHEET_ID  = '14GoBnB6GgnUYsCBY_nx82DUL2hZEmFXbDR4dByketqc'
DOC_ID    = '01KRE46H4452DPPVSYM5BKXJ14'
GRID      = 'https://grid.melioffice.com'
HTML_PATH = r'C:\Users\lcorales\Downloads\Claude\affiliates-dashboard-grid.html'

# Cada tab agrupa varias queries; la columna _q dice a cual pertenece la fila.
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


def _leer_tab(tab, timeout=60):
    url = f'{GRID}/api/v1/sheets/{SHEET_ID}?doc_id={DOC_ID}&range={tab}!A:B'
    req = urllib.request.Request(url, headers={'x-api-source': 'office'})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode('utf-8')).get('values', [])


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


def _desde_sheet():
    meta = _leer_tab(TAB_META)
    filas_meta = [f for f in meta[1:] if len(f) > 1 and f[1]]
    if not filas_meta:
        raise RuntimeError('la tab g_meta esta vacia: la corrida de Verdi quedo incompleta')
    info = json.loads(filas_meta[0][1])

    data = {k: [] for k in CLAVES}
    for tab in GRUPOS:
        for fila in _leer_tab(tab)[1:]:
            if len(fila) < 2 or not fila[1]:
                continue
            q = fila[0]
            if q in data:
                data[q].append(_normalizar(json.loads(fila[1])))

    vacias = [k for k in CLAVES if not data[k]]
    if vacias:
        raise RuntimeError('queries sin filas en el Sheet: ' + ', '.join(vacias))
    return data, info.get('savedAt', '')


def _desde_html():
    with open(HTML_PATH, encoding='utf-8') as f:
        html = f.read()
    m = re.search(r'window\.__PRELOADED__\s*=\s*(\{.*?\});</script>', html, re.DOTALL)
    snap = json.loads(m.group(1))
    return snap['data'], snap.get('savedAt', '')


def cargar(verbose=True):
    """Devuelve (data, savedAt, fuente). fuente es 'sheet' o 'html'."""
    try:
        data, saved = _desde_sheet()
        fuente = 'sheet'
    except Exception as e:
        if verbose:
            print(f'[fuente] No se pudo leer el Sheet ({e}).')
            print('[fuente] Se usa el HTML local, que puede estar atrasado.')
        data, saved = _desde_html()
        fuente = 'html'

    if verbose:
        etiqueta = ('Google Sheet (Verdi, se actualiza 10/12/14 hs)' if fuente == 'sheet'
                    else 'HTML local (bq_refresh.ps1, manual)')
        print(f'[fuente] {etiqueta} · snapshot {saved[:19].replace("T", " ")} UTC')
    return data, saved, fuente


if __name__ == '__main__':
    import sys
    sys.stdout.reconfigure(encoding='utf-8')
    d, s, f = cargar()
    print(f'\nfuente={f}  savedAt={s}')
    for k in sorted(d):
        print(f'  {k:<30} {len(d[k]):>6} filas')
