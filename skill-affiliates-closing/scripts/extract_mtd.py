#!/usr/bin/env python3
"""
MTD (Month-To-Date) extractor for Affiliates program.
Run: python extract_mtd.py
Outputs:
  1. Slack compact block — (1) KPIs MTD vs same period last month + QR Rolling
  2. Raw driver data per site for writing the highlights narrative
  3. Debug: schema of MTD tables (useful if something looks wrong)
"""
import re, json, sys, calendar
from datetime import date
from collections import defaultdict
sys.stdout.reconfigure(encoding='utf-8')

SITES = ['MLB', 'MLM', 'MLC', 'MLA']
DASHBOARD_URL = 'https://grid.adminml.com/d/01KRE46H4452DPPVSYM5BKXJ14/view'

# ── Load snapshot ────────────────────────────────────────────────────────────
# Lee el Google Sheet que escribe Verdi (10/12/14 hs). Si no responde, cae al
# HTML local, que solo se actualiza cuando alguien corre bq_refresh.ps1 a mano.
from data_source import cargar
data, SAVED_AT, FUENTE = cargar()

# ── Helpers ──────────────────────────────────────────────────────────────────
def fmt_n(n):
    n = float(n) if n else 0
    if abs(n) >= 1_000_000: return f'{n/1_000_000:.3f}M'
    if abs(n) >= 1_000:     return f'{n/1_000:.1f}K'
    return f'{n:.0f}'

def pct_chg(v, ref):
    if not ref: return 'N/A'
    return f'{(float(v) - float(ref)) / abs(float(ref)) * 100:+.1f}%'

def pp_chg(v, ref):
    return f'{(float(v) - float(ref))*100:+.2f}pp'

# ── Build lookups ─────────────────────────────────────────────────────────────
# beh_mtd: 2 rows per site (period='curr' and period='prev')
beh_mtd = {}
for r in data.get('beh_mtd', []):
    site   = r.get('sit_site_id', '')
    period = r.get('period', '')
    beh_mtd[(site, period)] = r

# nmv_mtd: 1 row per site, curr/prev in separate columns
nmv_mtd = {}
for r in data.get('nmv_mtd', []):
    site = r.get('sit_site_id', '')
    nmv_mtd[site] = r

# reg_mtd: rows keyed by (site_id, period, origen_grouped)
reg_mtd = defaultdict(lambda: defaultdict(int))
for r in data.get('reg_mtd', []):
    site   = r.get('site_id', '')
    period = r.get('period', '')
    og     = r.get('origen_grouped', r.get('origen', 'Other'))
    cnt    = int(r.get('users', 0))
    reg_mtd[(site, period)][og] += cnt

# churn_mtd: 1 row per site with curr_* and prev_* fields
churn_mtd = {}
for r in data.get('churn_mtd', []):
    site = r.get('sit_site_id', '')
    churn_mtd[site] = r

# qr_rolling: 1 row per site
qr_rolling = {}
for r in data.get('qr_rolling', []):
    site = r.get('sit_site_id', '')
    qr_rolling[site] = r

# ── Determine current day and month metadata ──────────────────────────────────
# Get max date from data_freshness or from qr_rolling window_end
max_dt_str = ''
for r in data.get('data_freshness', []):
    dt = str(r.get('max_dt', ''))
    if dt > max_dt_str:
        max_dt_str = dt
if not max_dt_str:
    for site in SITES:
        qr = qr_rolling.get(site, {})
        we = str(qr.get('window_end', ''))
        if we > max_dt_str:
            max_dt_str = we

if max_dt_str:
    max_date    = date.fromisoformat(max_dt_str[:10])
    day_n       = max_date.day
    total_days  = calendar.monthrange(max_date.year, max_date.month)[1]
    pct_mes     = round(day_n / total_days * 100)
    curr_month  = max_date.strftime('%Y-%m')
    # Previous month name (for "vs [mes] D1-N" label)
    if max_date.month == 1:
        prev_month = date(max_date.year - 1, 12, 1).strftime('%b-%Y')
    else:
        prev_month = date(max_date.year, max_date.month - 1, 1).strftime('%b-%Y')
else:
    day_n, total_days, pct_mes = '?', '?', '?'
    prev_month = 'mes ant.'

# ── QR Rolling calculation and window ────────────────────────────────────────
def calc_qr_rolling(site):
    qr = qr_rolling.get(site, {})
    new      = float(qr.get('new_30d', 0))
    recov    = float(qr.get('recovered_30d', 0))
    churned  = float(qr.get('churned_30d', 0))
    if not churned: return None
    return (new + recov) / churned

# Date range for QR rolling (use first site that has data)
qr_window = ''
for site in SITES:
    qr = qr_rolling.get(site, {})
    ws = str(qr.get('window_start', ''))[:10]
    we = str(qr.get('window_end',   ''))[:10]
    if ws and we:
        qr_window = f"{ws}–{we}"
        break

# ════════════════════════════════════════════════════════════════════════════
# SECTION 1 — SLACK COMPACT BLOCK
# ════════════════════════════════════════════════════════════════════════════
print(f"=== MTD AL DÍA {day_n}/{total_days} ({pct_mes}% del mes) | datos al {max_dt_str[:10]} ===")
print()
print("=" * 70)
print("  BLOQUE SLACK — [Afiliados | Resultados MTD]")
print("=" * 70)

print(f"\n[Afiliados | Resultados MTD · D{day_n}/{total_days} ({pct_mes}% del mes)]")
print(f"Hola team, les comparto los resultados MTD al día {day_n} de {total_days} ({pct_mes}% del mes).")
print(f"TLDR: [completar con narrativa cross-site]\n")
print(f"(1) KPIs\n")
print(f"```")
print(f"NMV Share   Δ vs {prev_month} D1-{day_n}   Activos MTD      Δ")

for site in SITES:
    nm  = nmv_mtd.get(site, {})
    bc  = beh_mtd.get((site, 'curr'), {})
    bp  = beh_mtd.get((site, 'prev'), {})

    ts_c  = float(nm.get('ts_curr',  0))
    nmv_c = float(nm.get('nmv_curr', 0))
    ts_p  = float(nm.get('ts_prev',  0))
    nmv_p = float(nm.get('nmv_prev', 0))

    sh_c = nmv_c / ts_c  if ts_c  else 0
    sh_p = nmv_p / ts_p  if ts_p  else 0
    sh_d = pp_chg(sh_c, sh_p) if sh_p else '---'

    act_c = float(bc.get('active_aff', 0))
    act_p = float(bp.get('active_aff', 0))
    act_d = pct_chg(act_c, act_p) if act_p else '---'

    print(f"{site:<5}  {sh_c*100:>6.2f}%      {sh_d:>9}      {fmt_n(act_c):>8}   {act_d:>6}")

print(f"```")

# QR Rolling line
qr_parts = []
for site in SITES:
    qr_val = calc_qr_rolling(site)
    qr_parts.append(f"{site} {qr_val:.2f}" if qr_val else f"{site} N/A")
print(f"\nQR Rolling 30d ({qr_window}): {' · '.join(qr_parts)}")

print(f"\n(2) Highlights\n")
for site in SITES:
    print(f"* {site}: [completar con narrativa basada en datos crudos abajo]")

print(f"\nDashboard → {DASHBOARD_URL}")

# ════════════════════════════════════════════════════════════════════════════
# SECTION 2 — RAW DRIVER DATA FOR HIGHLIGHTS (curr vs prev same days)
# ════════════════════════════════════════════════════════════════════════════
print("\n\n" + "=" * 70)
print(f"  DATOS CRUDOS PARA HIGHLIGHTS (D1-{day_n} del mes actual vs D1-{day_n} mes anterior)")
print("=" * 70)

for site in SITES:
    nm  = nmv_mtd.get(site, {})
    bc  = beh_mtd.get((site, 'curr'), {})
    bp  = beh_mtd.get((site, 'prev'), {})
    cm  = churn_mtd.get(site, {})
    rc  = reg_mtd.get((site, 'curr'), {})
    rp  = reg_mtd.get((site, 'prev'), {})
    qr  = qr_rolling.get(site, {})

    print(f"\n  {site}:")

    # Actives
    act_c = float(bc.get('active_aff', 0))
    act_p = float(bp.get('active_aff', 0))
    print(f"    {'Activos MTD':<18} {fmt_n(act_p):>8} → {fmt_n(act_c):>8}   ({pct_chg(act_c, act_p)})")

    # New / Recovered from beh_mtd
    new_c = float(bc.get('new_aff', 0))
    new_p = float(bp.get('new_aff', 0))
    print(f"    {'New aff MTD':<18} {fmt_n(new_p):>8} → {fmt_n(new_c):>8}   ({pct_chg(new_c, new_p)})")

    rec_c = float(bc.get('recovered_aff', 0))
    rec_p = float(bp.get('recovered_aff', 0))
    print(f"    {'Recovered MTD':<18} {fmt_n(rec_p):>8} → {fmt_n(rec_c):>8}   ({pct_chg(rec_c, rec_p)})")

    # Churned from beh_mtd
    ch_c = float(bc.get('churned_aff', 0))
    ch_p = float(bp.get('churned_aff', 0))
    print(f"    {'Churneados MTD':<18} {fmt_n(ch_p):>8} → {fmt_n(ch_c):>8}   ({pct_chg(ch_c, ch_p)})")

    # Churn % from churn_mtd
    pct_c = float(cm.get('pct_churn_new_curr', 0))
    pct_p = float(cm.get('pct_churn_new_prev', 0))
    if pct_c or pct_p:
        print(f"    {'Churn % (MTD)':<18} {pct_p:>7.1f}% → {pct_c:>7.1f}%   ({pct_c-pct_p:+.1f}pp)")

    # NMV Share (all)
    ts_c  = float(nm.get('ts_curr',  0)); nmv_c = float(nm.get('nmv_curr', 0))
    ts_p  = float(nm.get('ts_prev',  0)); nmv_p = float(nm.get('nmv_prev', 0))
    sh_c  = nmv_c / ts_c if ts_c else 0
    sh_p  = nmv_p / ts_p if ts_p else 0
    print(f"    {'NMV share MTD':<18} {sh_p*100:>7.2f}% → {sh_c*100:>7.2f}%   ({(sh_c-sh_p)*100:+.2f}pp)")

    # NMV/Aff LT
    lta_c = float(nm.get('lt_active_curr', 0)); ltn_c = float(nm.get('lt_nmv_curr', 0))
    lta_p = float(nm.get('lt_active_prev', 0)); ltn_p = float(nm.get('lt_nmv_prev', 0))
    npa_c = ltn_c / lta_c if lta_c else 0
    npa_p = ltn_p / lta_p if lta_p else 0
    if npa_c or npa_p:
        print(f"    {'NMV/Aff LT MTD':<18} {fmt_n(npa_p):>8} → {fmt_n(npa_c):>8}   ({pct_chg(npa_c, npa_p)})")

    # Registrations
    tot_c  = sum(rc.values()); tot_p  = sum(rp.values())
    pom_c  = rc.get('POM', 0); pom_p  = rp.get('POM', 0)
    dir_c  = rc.get('Direct', 0); dir_p  = rp.get('Direct', 0)
    print(f"    {'Regs tot. MTD':<18} {fmt_n(tot_p):>8} → {fmt_n(tot_c):>8}   ({pct_chg(tot_c, tot_p)})")
    print(f"    {'— POM':<18} {fmt_n(pom_p):>8} → {fmt_n(pom_c):>8}   ({pct_chg(pom_c, pom_p)})")
    print(f"    {'— Direct':<18} {fmt_n(dir_p):>8} → {fmt_n(dir_c):>8}   ({pct_chg(dir_c, dir_p)})")

    # QR Rolling detail
    qr_val = calc_qr_rolling(site)
    new30  = float(qr.get('new_30d', 0))
    rec30  = float(qr.get('recovered_30d', 0))
    ch30   = float(qr.get('churned_30d', 0))
    if qr_val:
        print(f"    {'QR Rolling 30d':<18} {qr_val:.2f}  (new {fmt_n(new30)} + recov {fmt_n(rec30)}) / churn {fmt_n(ch30)}")

# ════════════════════════════════════════════════════════════════════════════
# SECTION 3 — DEBUG: schema (useful if values look wrong)
# ════════════════════════════════════════════════════════════════════════════
print("\n\n" + "=" * 70)
print("  DEBUG — Schema de tablas MTD (validar si algo parece incorrecto)")
print("=" * 70)
for table in ['beh_mtd', 'nmv_mtd', 'reg_mtd', 'churn_mtd', 'qr_rolling']:
    rows = data.get(table, [])
    print(f"\n{table} ({len(rows)} filas) — campos del primer registro:")
    if rows:
        for k in rows[0]:
            print(f"  {k}")
