#!/usr/bin/env python3
import csv
from pathlib import Path

ROOT = Path("/home/lilinzhen/colocate_lab/results/cbs")
OUT = Path("docs/pmu_representative_points.csv")

TARGETS = [
    ("baseline", "pmu_taobench_baseline", "perf_stat_baseline.parsed.csv"),
    ("ibench_membw_w8", "pmu_taobench_ibench_membw_w8", "perf_stat_ibench_membw_w8.parsed.csv"),
    ("ibench_l3_w8", "pmu_taobench_ibench_l3_w8", "perf_stat_ibench_l3_w8.parsed.csv"),
    ("spec_mcf_ref_c8", "pmu_taobench_spec_mcf_ref_c8", "perf_stat_spec_mcf_ref_c8.parsed.csv"),
    ("spec_lbm_ref_c8", "pmu_taobench_spec_lbm_ref_c8", "perf_stat_spec_lbm_ref_c8.parsed.csv"),
]

EVENTS = [
    "cycles",
    "instructions",
    "cache-references",
    "cache-misses",
    "LLC-loads",
    "LLC-load-misses",
    "branches",
    "branch-misses",
    "context-switches",
    "cpu-migrations",
    "page-faults",
]

def latest_dir(pattern: str):
    matches = sorted(ROOT.glob(f"*{pattern}*"), key=lambda p: p.stat().st_mtime, reverse=True)
    return matches[0] if matches else None

def read_event_values(path: Path):
    values = {}
    if not path.exists():
        return values
    with path.open(newline="") as f:
        for r in csv.DictReader(f):
            event = r.get("event", "")
            val = r.get("value", "")
            if event:
                values[event] = val
    return values

def main():
    rows = []
    for name, dir_pattern, parsed_name in TARGETS:
        d = latest_dir(dir_pattern)
        if d is None:
            print(f"[WARN] missing dir for {name}")
            continue

        path = d / "logs" / parsed_name
        values = read_event_values(path)

        row = {"point": name, "run_dir": str(d)}
        for e in EVENTS:
            row[e] = values.get(e, "")

        try:
            cycles = float(row.get("cycles") or 0)
            instr = float(row.get("instructions") or 0)
            cache_ref = float(row.get("cache-references") or 0)
            cache_miss = float(row.get("cache-misses") or 0)
            llc_loads = float(row.get("LLC-loads") or 0)
            llc_miss = float(row.get("LLC-load-misses") or 0)

            row["ipc"] = f"{instr / cycles:.4f}" if cycles > 0 else ""
            row["cache_miss_rate"] = f"{cache_miss / cache_ref:.4f}" if cache_ref > 0 else ""
            row["llc_load_miss_rate"] = f"{llc_miss / llc_loads:.4f}" if llc_loads > 0 else ""
        except Exception:
            row["ipc"] = ""
            row["cache_miss_rate"] = ""
            row["llc_load_miss_rate"] = ""

        rows.append(row)

    fields = ["point", "ipc", "cache_miss_rate", "llc_load_miss_rate"] + EVENTS + ["run_dir"]

    OUT.parent.mkdir(parents=True, exist_ok=True)
    with OUT.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)

    print(f"[OK] wrote {OUT}")
    print(OUT.read_text())

if __name__ == "__main__":
    main()
