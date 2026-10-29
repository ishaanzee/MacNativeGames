"""Summarise bench_ab.sh runs: frame times per condition (all A windows together, all B windows together) from
TOTK_BENCH_FRAMES, and the log's GPU / submit and present cadence lines inside each condition's windows.
usage: python3 -I ab_parse.py <runs dir> <label> [label ...]"""
import os, re, sys

def pct(v, p):
    if not v: return float('nan')
    v = sorted(v); return v[min(len(v) - 1, int(len(v) * p / 100))]
avg = lambda v: sum(v) / len(v) if v else float('nan')

base = sys.argv[1]
for label in sys.argv[2:]:
    d = os.path.join(base, label)
    cfg = open(os.path.join(d, 'config')).read().strip()
    ts = {}
    for line in open(os.path.join(d, 'frames.txt')):
        p = line.split()
        if len(p) == 2: ts[int(p[0])] = int(p[1])
    lines = open(os.path.join(d, 'game.log'), encoding='utf-8', errors='ignore').read().splitlines()
    acc = {}
    for w in open(os.path.join(d, 'windows')):
        c, f0, f1, l0, l1 = w.split(); f0, f1, l0, l1 = map(int, (f0, f1, l0, l1))
        a = acc.setdefault(c, {'dt': [], 'secs': 0.0, 'frames': 0, 'g50': [], 'g95': [], 's50': [], 'held': [], 'pi50': [], 'pi95': [], 'win': []})
        fr = [k for k in range(f0, f1 + 1) if k in ts]
        dt = [(ts[k + 1] - ts[k]) / 1e6 for k in fr if k + 1 in ts and k + 1 <= f1]
        a['dt'] += dt
        if len(fr) > 1:
            secs = (ts[fr[-1]] - ts[fr[0]]) / 1e9; a['secs'] += secs; a['frames'] += len(fr) - 1
            a['win'].append((len(fr) - 1) / secs if secs > 0 else float('nan'))
        for l in lines[l0:l1]:
            m = re.search(r'NVN 提交\+出图 p50 ([\d.]+).*?GPU p50 ([\d.]+) / p95 ([\d.]+)', l)
            if m: a['s50'].append(float(m.group(1))); a['g50'].append(float(m.group(2))); a['g95'].append(float(m.group(3)))
            m = re.search(r'上屏节奏.*?间隔 p50 ([\d.]+) / p95 ([\d.]+).*?多停一次刷新以上 \d+ 次（([\d.]+)%）', l)
            if m: a['pi50'].append(float(m.group(1))); a['pi95'].append(float(m.group(2))); a['held'].append(float(m.group(3)))
    print(f"== {label}: {cfg}")
    print(f"   {'cond':4} {'fps':>6} {'1%low':>6} {'p50':>6} {'p95':>6} {'p99':>6} {'>12.5':>6} {'>16.7':>6} {'>33':>4} | {'gpu50':>6} {'gpu95':>6} {'sub50':>6} | {'pres50':>6} {'pres95':>6} {'held%':>6} | per-window fps")
    for c in sorted(acc):
        a = acc[c]; dt = a['dt']
        fps = a['frames'] / a['secs'] if a['secs'] else float('nan')
        print(f"   {c:4} {fps:6.1f} {1000 / pct(dt, 99) if dt else float('nan'):6.1f} {pct(dt,50):6.2f} {pct(dt,95):6.2f} {pct(dt,99):6.2f} "
              f"{sum(x > 12.5 for x in dt):6d} {sum(x > 16.7 for x in dt):6d} {sum(x > 33.4 for x in dt):4d} | "
              f"{avg(a['g50']):6.2f} {avg(a['g95']):6.2f} {avg(a['s50']):6.2f} | {avg(a['pi50']):6.2f} {avg(a['pi95']):6.2f} {avg(a['held']):6.1f} | "
              + ' '.join(f'{x:.0f}' for x in a['win']))
