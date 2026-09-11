#!/usr/bin/env python3
"""
Monthly closing extractor for Affiliates program.
Run: python extract_monthly.py
Outputs three sections:
  1. Detailed 13-metric table (M-2 | M-1 | M0 | M1/M0 | M2/M1 | M2/M0)
  2. Compact Slack block — (1) Main KPIs + QR line
  3. Raw driver data per site for writing the insights narrative
"""
import re, json, sys
from collections import defaultdict
sys.stdout.reconfigure(encoding='utf-8')

SITES = ['MLB', 'MLM', 'MLC', 'MLA']
DASHBOARD_URL = 'https://grid.adminml.com/d/01KRE46H4452DPPVSYM5BKXJ14/view'

# ── Load snapshot ────────────────────────────────────────────────────────────
# Lee el Google Sheet que escribe Verdi (10/12/14 hs). Si no responde, cae al
# HTML local, que solo se actualiza cuando alguien corre bq_refresh.ps1 a mano.
from data_source import cargar
data, SAVED_AT, FUENTE = cargar()

# ── Build lookups ────────────────────────────────────────────────────────────
beh = {}
for r in data.get('behaviour', []):
    if r.get('period') == 'MONTH':
        beh[(r.get('sit_site_id', ''), str(r.get('dt', ''))[:7])] = r

churn_d = {}
for r in data.get('churn', []):
    churn_d[(r.get('sit_site_id', ''), str(r.get('month', ''))[:7])] = r

nmv = {}
for r in data.get('nmv_monthly', []):
    nmv[(r.get('sit_site_id', ''), str(r.get('mes', ''))[:7], r.get('seg', ''))] = r

reg_agg = defaultdict(lambda: defaultdict(int))
for r in data.get('registrations', []):
    # La query v2 pre-agrega en BQ y marca cada fila con `grain` (month | week).
    # Sin `grain` son filas diarias del formato viejo y suman igual. Las de
    # semana traen year/month en null y romperian el int().
    if r.get('grain') not in (None, 'month'):
        continue
    reg_agg[(r.get('site_id', ''), int(r.get('year') or 0), int(r.get('month') or 0))][
        r.get('origen_grouped', '')] += int(r.get('users', 0))

spend = {}
for r in data.get('spend_pom', []):
    spend[(r.get('site_id', ''), str(r.get('month_id', ''))[:7])] = float(r.get('cost_lc', 0))

# ── Find last 3 closed months (ascending order) ──────────────────────────────
# Exclude the current partial month so we only compare fully-closed months.
from datetime import date
current_ym = date.today().strftime('%Y-%m')
all_months = sorted(
    set(k[1] for k in beh if k[1] < current_ym),
    reverse=True
)
M = all_months[:3][::-1]   # M[0]=oldest, M[1]=middle, M[2]=most recent closed
print(f"=== MESES: {M[0]} | {M[1]} | {M[2]} ===\n")

# ── Helpers ──────────────────────────────────────────────────────────────────
def fmt_n(n):
    n = float(n)
    if abs(n) >= 1_000_000: return f'{n/1_000_000:.3f}M'
    if abs(n) >= 1_000:     return f'{n/1_000:.1f}K'
    return f'{n:.0f}'

def pct_chg(v, ref):
    if not ref: return 'N/A'
    return f'{(v - ref) / abs(ref) * 100:+.1f}%'

def sem(v, ref, rev=False, thr=0.03):
    if not ref: return '🟡'
    p = (v - ref) / abs(ref)
    if rev:  return '🟢' if p < -thr else ('🔴' if p > thr else '🟡')
    return     '🟢' if p > thr  else ('🔴' if p < -thr else '🟡')

def get_reg(site, ym):
    yr, mo = int(ym[:4]), int(ym[5:7])
    d = reg_agg.get((site, yr, mo), {})
    return d.get('POM', 0), d.get('Direct', 0), sum(d.values())

# ════════════════════════════════════════════════════════════════════════════
# SECTION 1 — DETAILED TABLE
# ════════════════════════════════════════════════════════════════════════════
print("=" * 100)
print(f"  {'TABLA DETALLADA':^95}")
print("=" * 100)
print(f"  {'Métrica':<22} {M[0]:>10} {M[1]:>10} {M[2]:>10}   {'M1/M0':^10}  {'M2/M1':^10}  {'M2/M0':^10}")

for site in SITES:
    b  = [beh.get((site, m), {}) for m in M]
    c  = [churn_d.get((site, m), {}) for m in M]
    na = [nmv.get((site, m, 'all'), {}) for m in M]
    nl = [nmv.get((site, m, 'lt'),  {}) for m in M]
    nk = [nmv.get((site, m, 'nlt'), {}) for m in M]

    act   = [b[i].get('active_aff', 0) for i in range(3)]
    new   = [b[i].get('new_aff', 0)    for i in range(3)]
    recu  = [b[i].get('recurrent', 0)  for i in range(3)]
    recov = [b[i].get('recovered', 0)  for i in range(3)]
    qr    = [b[i].get('quick_ratio')   for i in range(3)]
    ch_n  = [c[i].get('churned', 0)    for i in range(3)]
    ch_p  = [c[i].get('churned', 0) / max(c[i].get('active_prev', 1), 1) * 100 for i in range(3)]
    sh_a  = [na[i].get('share_ts', 0)  for i in range(3)]
    sh_l  = [nl[i].get('share_ts', 0)  for i in range(3)]
    sh_k  = [nk[i].get('share_ts', 0)  for i in range(3)]
    npa   = [nl[i].get('npa', 0)       for i in range(3)]
    regs  = [get_reg(site, m) for m in M]
    poms  = [r[0] for r in regs]
    dirs  = [r[1] for r in regs]
    tots  = [r[2] for r in regs]
    sps   = [spend.get((site, m), 0) for m in M]

    print(f"\n  ── {site} {'─'*80}")

    def pr(label, vals, rev=False):
        v0, v1, v2 = [float(x) for x in vals]
        d10 = pct_chg(v1, v0); d21 = pct_chg(v2, v1); d20 = pct_chg(v2, v0)
        s10 = sem(v1, v0, rev); s21 = sem(v2, v1, rev); s20 = sem(v2, v0, rev)
        print(f"  {label:<22} {fmt_n(v0):>10} {fmt_n(v1):>10} {fmt_n(v2):>10}   {d10:>6} {s10}  {d21:>6} {s21}  {d20:>6} {s20}")

    def pr_pp(label, vals, rev=False):
        v0, v1, v2 = vals
        d10 = f'{(v1-v0)*100:+.2f}pp'; d21 = f'{(v2-v1)*100:+.2f}pp'; d20 = f'{(v2-v0)*100:+.2f}pp'
        s10 = sem(v1, v0, rev); s21 = sem(v2, v1, rev); s20 = sem(v2, v0, rev)
        print(f"  {label:<22} {v0*100:>9.2f}% {v1*100:>9.2f}% {v2*100:>9.2f}%   {d10:>8} {s10}  {d21:>8} {s21}  {d20:>8} {s20}")

    pr('Activos totales', act)
    pr('Nuevos activos', new)
    pr('Recurrentes', recu)
    pr('Recovered', recov)
    pr('Registros tot.', tots)
    pr('— POM', poms)
    pr('— Direct', dirs)
    pr_pp('NMV share all', sh_a)
    pr_pp('NMV share LT', sh_l)
    pr_pp('NMV share KA', sh_k)
    pr_pp('Churn total %', [x / 100 for x in ch_p], rev=True)

    qs   = [f'{q:.2f}' if q else 'N/A' for q in qr]
    def qdelta(a, b): return f'{(b-a):+.2f}pp' if (a and b) else 'N/A'
    def qsem(a, b):  return sem(b, a) if (a and b) else '🟡'
    print(f"  {'QR calendario':<22} {qs[0]:>10} {qs[1]:>10} {qs[2]:>10}"
          f"   {qdelta(qr[0],qr[1]):>8} {qsem(qr[0],qr[1])}"
          f"  {qdelta(qr[1],qr[2]):>8} {qsem(qr[1],qr[2])}"
          f"  {qdelta(qr[0],qr[2]):>8} {qsem(qr[0],qr[2])}")

# ════════════════════════════════════════════════════════════════════════════
# SECTION 2 — SLACK COMPACT BLOCK (M-1 vs M0 only)
# ════════════════════════════════════════════════════════════════════════════
print("\n\n" + "=" * 70)
print("  BLOQUE SLACK — (1) Main KPIs")
print("=" * 70)
print(f"\n```")
print(f"          NMV Share   Δ vs {M[1]}     Activos      Δ")
for site in SITES:
    sh1 = nmv.get((site, M[1], 'all'), {}).get('share_ts', 0)
    sh2 = nmv.get((site, M[2], 'all'), {}).get('share_ts', 0)
    act1 = beh.get((site, M[1]), {}).get('active_aff', 0)
    act2 = beh.get((site, M[2]), {}).get('active_aff', 0)
    sh_d = f'{(sh2-sh1)*100:+.2f} pp'
    act_d = pct_chg(act2, act1)
    print(f"{site:<5}      {sh2*100:>6.2f}%    {sh_d:>9}      {fmt_n(act2):>7}    {act_d:>6}")
print(f"```")

qr_parts = []
for site in SITES:
    q1 = beh.get((site, M[1]), {}).get('quick_ratio')
    q2 = beh.get((site, M[2]), {}).get('quick_ratio')
    if q1 and q2:
        qr_parts.append(f"{site} {q2:.2f} ({(q2-q1):+.2f})")
    elif q2:
        qr_parts.append(f"{site} {q2:.2f}")
print(f"\nQR mensual (vs cierre {M[1]}): {' · '.join(qr_parts)}")

# ════════════════════════════════════════════════════════════════════════════
# SECTION 3 — RAW DRIVER DATA FOR INSIGHTS (M-1 → M0)
# ════════════════════════════════════════════════════════════════════════════
print("\n\n" + "=" * 70)
print("  DATOS PARA INSIGHTS (M-1 → M0)")
print("=" * 70)
for site in SITES:
    b1 = beh.get((site, M[1]), {}); b2 = beh.get((site, M[2]), {})
    c1 = churn_d.get((site, M[1]), {}); c2 = churn_d.get((site, M[2]), {})
    na1 = nmv.get((site, M[1], 'all'), {}); na2 = nmv.get((site, M[2], 'all'), {})
    nl1 = nmv.get((site, M[1], 'lt'), {}); nl2 = nmv.get((site, M[2], 'lt'), {})
    pom1, dir1, _ = get_reg(site, M[1])
    pom2, dir2, _ = get_reg(site, M[2])

    print(f"\n  {site}:")

    def drv(label, v1, v2):
        delta = pct_chg(float(v2), float(v1))
        print(f"    {label:<18} {fmt_n(v1):>8} → {fmt_n(v2):>8}   ({delta})")

    drv('Activos', b1.get('active_aff', 0), b2.get('active_aff', 0))
    drv('New aff', b1.get('new_aff', 0), b2.get('new_aff', 0))
    drv('Recurrentes', b1.get('recurrent', 0), b2.get('recurrent', 0))
    drv('Recovered', b1.get('recovered', 0), b2.get('recovered', 0))
    cp1 = c1.get('churned', 0) / max(c1.get('active_prev', 1), 1) * 100
    cp2 = c2.get('churned', 0) / max(c2.get('active_prev', 1), 1) * 100
    print(f"    {'Churn %':<18} {cp1:>7.1f}% → {cp2:>7.1f}%   ({cp2-cp1:+.1f}pp)")
    sh1 = na1.get('share_ts', 0); sh2 = na2.get('share_ts', 0)
    print(f"    {'NMV share all':<18} {sh1*100:>7.2f}% → {sh2*100:>7.2f}%   ({(sh2-sh1)*100:+.2f}pp)")
    q1 = b1.get('quick_ratio'); q2 = b2.get('quick_ratio')
    if q1 and q2:
        print(f"    {'QR calendario':<18} {q1:>8.2f} → {q2:>8.2f}   ({(q2-q1):+.2f})")
    drv('Regs POM', pom1, pom2)
    drv('Regs Direct', dir1, dir2)

print(f"\n\nDashboard: {DASHBOARD_URL}")
