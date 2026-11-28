#!/usr/bin/env python3
"""Turns the log of tools/gpu-audit/audit.sh into a table (Markdown).

For each scenario (between PROFMARK and PROFDUMP): the compositor (frames, prepare on the
CPU, render) and each app that drew (frames, CPU paint: average, p95, worst; pixels
painted per frame). Usage: report.py glove.log [LABEL]
"""
import re
import sys

ANSI = re.compile(r"\x1b\[[0-9;]*m")
DUR = re.compile(r"([\d.]+)(ns|µs|us|ms|s)\b")


def ms(text):
    m = DUR.match(text)
    if not m:
        return 0.0
    v, u = float(m.group(1)), m.group(2)
    return v * {"ns": 1e-6, "µs": 1e-3, "us": 1e-3, "ms": 1.0, "s": 1000.0}[u]


def stats(v):
    if not v:
        return (0.0, 0.0, 0.0)
    v = sorted(v)
    p95 = v[min(len(v) - 1, max(0, int(len(v) * 0.95 + 0.999) - 1))]
    return (sum(v) / len(v), p95, v[-1])


def main():
    log = open(sys.argv[1], encoding="utf-8", errors="replace").read().splitlines()
    label = sys.argv[2] if len(sys.argv) > 2 else ""
    scenario = None
    apps = {}
    rows = []
    for raw in log:
        line = ANSI.sub("", raw)
        if "PROFMARK " in line:
            scenario = line.split("PROFMARK ", 1)[1].strip()
            apps = {}
            continue
        if line.startswith("PROF [") and scenario:
            m = re.match(r"PROF \[([^\]]*)\] desenho=(\S+)", line)
            if m:
                px = re.search(r"pintou=(\d+)px|mudou=(\d+)px", line)
                n = int(next(g for g in px.groups() if g)) if px else 0
                apps.setdefault(m.group(1), []).append((ms(m.group(2)), n))
            continue
        if "PROFDUMP " in line and scenario:
            d = dict(kv.split("=", 1) for kv in line.split("PROFDUMP ", 1)[1].split()[1:])
            rows.append((scenario, d, apps))
            scenario = None
    print(f"### Auditoria {label}\n")
    print("| Cenário | Compositor: quadros | preparar (CPU) média / p95 / pior ms | desenhar média / pior ms | App | quadros | pintar (CPU) média / p95 / pior ms | px por quadro |")
    print("|---|---|---|---|---|---|---|---|")
    for name, d, apps in rows:
        comp = (d.get("frames", "0"), f"{d.get('prep_avg')} / {d.get('prep_p95')} / {d.get('prep_max')}", f"{d.get('render_avg')} / {d.get('render_max')}")
        if not apps:
            print(f"| {name} | {comp[0]} | {comp[1]} | {comp[2]} | — | | | |")
        for i, (app, v) in enumerate(sorted(apps.items(), key=lambda kv: -sum(x[0] for x in kv[1]))):
            a, p, w = stats([x[0] for x in v])
            px = int(sum(x[1] for x in v) / max(1, len(v)))
            first = (name, comp[0], comp[1], comp[2]) if i == 0 else ("", "", "", "")
            print(f"| {first[0]} | {first[1]} | {first[2]} | {first[3]} | {app} | {len(v)} | {a:.2f} / {p:.2f} / {w:.2f} | {px} |")


if __name__ == "__main__":
    main()
