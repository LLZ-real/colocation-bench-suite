#!/usr/bin/env python3
import csv
from pathlib import Path

inp = Path("docs/week2_summary.csv")
out = Path("docs/week2_analysis.csv")

rows = list(csv.DictReader(inp.open()))

baseline_rows = [r for r in rows if r["offline_type"] == "none"]
if not baseline_rows:
    raise SystemExit("No baseline row found.")

baseline = baseline_rows[0]
base_qps = float(baseline["qps"])
base_p99 = float(baseline["gets_p99_ms"])

fields = [
    "offline_type",
    "offline_param",
    "clients_per_thread",
    "qps",
    "gets_p99_ms",
    "qps_degradation_pct",
    "p99_slowdown",
    "run_dir",
]

with out.open("w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=fields)
    w.writeheader()

    for r in rows:
        qps = float(r["qps"])
        p99 = float(r["gets_p99_ms"])

        qps_deg = (1.0 - qps / base_qps) * 100.0
        p99_slow = p99 / base_p99

        w.writerow({
            "offline_type": r["offline_type"],
            "offline_param": r["offline_param"],
            "clients_per_thread": r["clients_per_thread"],
            "qps": f"{qps:.2f}",
            "gets_p99_ms": f"{p99:.3f}",
            "qps_degradation_pct": f"{qps_deg:.2f}",
            "p99_slowdown": f"{p99_slow:.2f}",
            "run_dir": r["run_dir"],
        })

print(out)
