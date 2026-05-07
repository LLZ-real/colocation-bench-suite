#!/usr/bin/env python3
import csv
import glob
from pathlib import Path

ROOT = Path("/home/lilinzhen/colocate_lab/results/cbs")

patterns = [
    "*week2_taobench_baseline*",
    "*week2_taobench_ibench_cpu*",
    "*week2_taobench_ibench_membw*",
    "*week2_taobench_ibench_memcap*",
]

rows = []

for pat in patterns:
    for d in sorted(ROOT.glob(pat)):
        summary = d / "summary.csv"
        if not summary.exists():
            continue

        with summary.open() as f:
            r = list(csv.DictReader(f))
            if not r:
                continue
            row = r[0]
            row["run_dir"] = str(d)
            rows.append(row)

if not rows:
    print("No summary.csv found.")
    raise SystemExit(0)

out_fields = [
    "offline_type",
    "offline_param",
    "clients_per_thread",
    "qps",
    "gets_p99_ms",
    "run_dir",
]

print(",".join(out_fields))
for row in rows:
    print(",".join(str(row.get(k, "")) for k in out_fields))
