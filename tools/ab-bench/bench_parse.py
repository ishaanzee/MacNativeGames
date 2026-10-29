"""Summarise bench.sh runs: per-frame times from TOTK_BENCH_FRAMES inside the measured window (when the build writes
it), plus the game log's frame-time / GPU / submit timing, BotW's 30 s fps lines and present cadence in the window.
usage: python3 -I bench_parse.py <runs dir> <label> [label ...]"""
import os, re, sys

def pct(v, p):
    if not v: return float('nan')
    v = sorted(v); return v[min(len(v) - 1, int(len(v) * p / 100))]
avg = lambda v: sum(v) / len(v) if v else float('nan')

base = sys.argv[1]
print(f"{'label':24} {'fps':>6} {'1%low':>6} {'p50':>6} {'p95':>6} {'p99':>6} {'>16.7':>6} {'>33':>4} | "
      f"{'ft50':>6} {'ft95':>6} {'gpu50':>6} {'gpu95':>6} {'sub50':>6} | {'held%':>6} {'logfps':>7}")
for label in sys.argv[2:]:
    d = os.path.join(base, label)
    try:
        f0, f1, l0, l1 = map(int, open(os.path.join(d, 'window')).read().split())
    except Exception as e:
        print(f"{label:24} (no window: {e})"); continue
    ts = {}
    fp = os.path.join(d, 'frames.txt')
    if os.path.exists(fp):
        for line in open(fp):
            p = line.split()
            if len(p) == 2: ts[int(p[0])] = int(p[1])
    fr = sorted(k for k in ts if f0 <= k <= f1)
    dt = [(ts[b] - ts[a]) / 1e6 for a, b in zip(fr, fr[1:]) if b == a + 1]
    total = (ts[fr[-1]] - ts[fr[0]]) / 1e9 if len(fr) > 1 else 0
    fps = (len(fr) - 1) / total if total > 0 else float('nan')
    low1 = 1000 / pct(dt, 99) if dt else float('nan')
    lines = open(os.path.join(d, 'game.log'), encoding='utf-8', errors='ignore').read().splitlines()[l0:l1]
    ft50, ft95, g50, g95, s50, held, lfps = [], [], [], [], [], [], []
    for l in lines:
        m = re.search(r'帧时间 p50 ([\d.]+) / p95 ([\d.]+)', l)
        if m: ft50.append(float(m.group(1))); ft95.append(float(m.group(2)))
        m = re.search(r'NVN 提交\+出图 p50 ([\d.]+).*?GPU p50 ([\d.]+) / p95 ([\d.]+)', l)
        if m: s50.append(float(m.group(1))); g50.append(float(m.group(2))); g95.append(float(m.group(3)))
        m = re.search(r'上屏节奏.*?多停一次刷新以上 \d+ 次（([\d.]+)%）', l)
        if m: held.append(float(m.group(1)))
        m = re.search(r'real-time frame step: \d+ frames in [\d.]+ s \(([\d.]+) fps', l)
        if m: lfps.append(float(m.group(1)))
    print(f"{label:24} {fps:6.1f} {low1:6.1f} {pct(dt,50):6.2f} {pct(dt,95):6.2f} {pct(dt,99):6.2f} "
          f"{sum(x > 16.7 for x in dt):6d} {sum(x > 33.4 for x in dt):4d} | "
          f"{avg(ft50):6.2f} {avg(ft95):6.2f} {avg(g50):6.2f} {avg(g95):6.2f} {avg(s50):6.2f} | {avg(held):6.1f} {avg(lfps):7.1f}")
