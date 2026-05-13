#!/usr/bin/env python3
import csv
from pathlib import Path

ROOT = Path("/home/lilinzhen/colocate_lab/results/cbs")

patterns = [
    "*week3_taobench_spec*",
    "*smoke_taobench_spec*",
]

rows = []

for pat in patterns:
    for d in sorted(ROOT.glob(pat)):
        summary = d / "summary.csv"
        if not summary.exists():
            continue
        with summary.open() as f:
            reader = csv.DictReader(f)
            for row in reader:
                row["run_dir"] = str(d)
                rows.append(row)

if not rows:
    print("No week3 summary.csv found.")
    raise SystemExit(0)

fields = sorted(set().union(*(r.keys() for r in rows)))
preferred = [
    "offline_type",
    "offline_param",
    "clients_per_thread",
    "qps",
    "gets_p99_ms",
    "run_dir",
]
fields = [f for f in preferred if f in fields] + [f for f in fields if f not in preferred]

print(",".join(fields))
for r in rows:
    print(",".join(str(r.get(f, "")) for f in fields))
