#!/usr/bin/env python3
"""Generate the optimized Stage 1 condition matrix (v4 — real-data driven).

Usage:
  python3 tools/generate_stage1_full_matrix.py --mode spec    --out docs/stage1_spec_matrix.csv
  python3 tools/generate_stage1_full_matrix.py --mode ibench  --out docs/stage1_ibench_keepers.csv
  python3 tools/generate_stage1_full_matrix.py --mode all     --out docs/stage1_full_matrix.csv
  python3 tools/generate_stage1_full_matrix.py --mode smoke   --out /tmp/stage1_smoke.csv
"""
import argparse
import csv
import sys
from pathlib import Path

# ---- iBench keepers (intensity collapsed to arg=60, cpu dropped except same_smt) ----
IBENCH_KEEPERS = [
    ("ibench_membw", [4, 6, 8], 60, "membw"),
    ("ibench_l3",    [4, 6, 8], 60, "l3"),
]

# ---- SPEC benchmarks (priority-ordered, copies c4 + c8) ----
SPEC_BENCHMARKS = [
    # P0: fill 10-20% degradation gap
    ("505.mcf_r",        "memory",  "p0"),
    ("519.lbm_r",        "memory",  "p0"),
    ("503.bwaves_r",     "memory",  "p0"),
    # P1: same_smt uniqueness (branch/BTB pollution)
    ("502.gcc_r",        "branch",  "p1"),
    ("541.leela_r",      "branch",  "p1"),
    # P2: moderate mixed profile
    ("508.namd_r",       "compute", "p2"),
    ("525.x264_r",       "mixed",   "p2"),
    ("521.wrf_r",        "mixed",   "p2"),
    # P3: diversity fill
    ("538.imagick_r",    "compute", "p3"),
    ("511.povray_r",     "compute", "p3"),
    ("549.fotonik3d_r",  "memory",  "p3"),
    ("554.roms_r",       "memory",  "p3"),
    ("523.xalancbmk_r",  "branch",  "p3"),
    ("531.deepsjeng_r",  "branch",  "p3"),
    ("526.blender_r",    "compute", "p3"),
    ("527.cam4_r",       "mixed",   "p3"),
]

SPEC_COPIES = [4, 8]
SPEC_SIZE = "ref"

FIELDS = [
    "condition_id", "offline_type", "offline_param",
    "offline_intensity", "offline_label",
    "spec_size", "spec_copies", "spec_bench",
    "workload_category", "resource_profile", "priority",
]


def generate_ibench_keepers():
    rows = []
    for bench_type, workers, arg, profile in IBENCH_KEEPERS:
        for w in workers:
            rows.append({
                "condition_id": f"{bench_type}_w{w}_a{arg}",
                "offline_type": bench_type,
                "offline_param": str(w),
                "offline_intensity": str(arg),
                "offline_label": f"w{w}",
                "spec_size": "", "spec_copies": "", "spec_bench": "",
                "workload_category": "ibench",
                "resource_profile": profile,
                "priority": "keeper",
            })
    return rows


def generate_spec():
    rows = []
    for bench, profile, priority in SPEC_BENCHMARKS:
        for c in SPEC_COPIES:
            short = bench.replace(".", "_").replace("_r", "")
            rows.append({
                "condition_id": f"spec_{short}_c{c}",
                "offline_type": "spec",
                "offline_param": "",
                "offline_intensity": "",
                "offline_label": f"c{c}",
                "spec_size": SPEC_SIZE,
                "spec_copies": str(c),
                "spec_bench": bench,
                "workload_category": "spec",
                "resource_profile": profile,
                "priority": priority,
            })
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=["ibench", "spec", "all", "smoke"], default="all")
    ap.add_argument("--out", default="")
    args = ap.parse_args()

    rows = []
    if args.mode in ("ibench", "all"):
        rows.extend(generate_ibench_keepers())
    if args.mode in ("spec", "all"):
        rows.extend(generate_spec())

    if args.mode == "smoke":
        rows = [
            # 1 quick iBench as control
            {"condition_id": "ibench_membw_w4_a60", "offline_type": "ibench_membw",
             "offline_param": "4", "offline_intensity": "60", "offline_label": "w4",
             "spec_size": "", "spec_copies": "", "spec_bench": "",
             "workload_category": "ibench", "resource_profile": "membw", "priority": "smoke"},
            # 2 SPEC P0 benchmarks to verify degradation position
            {"condition_id": "spec_505_mcf_c8", "offline_type": "spec",
             "offline_param": "", "offline_intensity": "", "offline_label": "c8",
             "spec_size": SPEC_SIZE, "spec_copies": "8", "spec_bench": "505.mcf_r",
             "workload_category": "spec", "resource_profile": "memory", "priority": "smoke"},
            {"condition_id": "spec_519_lbm_c8", "offline_type": "spec",
             "offline_param": "", "offline_intensity": "", "offline_label": "c8",
             "spec_size": SPEC_SIZE, "spec_copies": "8", "spec_bench": "519.lbm_r",
             "workload_category": "spec", "resource_profile": "memory", "priority": "smoke"},
        ]

    if args.out:
        out = Path(args.out)
        out.parent.mkdir(parents=True, exist_ok=True)
        with out.open("w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=FIELDS)
            w.writeheader()
            w.writerows(rows)
        cats = {}
        for r in rows:
            cats[r["workload_category"]] = cats.get(r["workload_category"], 0) + 1
        print(f"[OK] wrote {len(rows)} conditions to {out}")
        for k, v in sorted(cats.items()):
            print(f"     {k}: {v}")
    else:
        w = csv.DictWriter(sys.stdout, fieldnames=FIELDS)
        w.writeheader()
        w.writerows(rows)


if __name__ == "__main__":
    main()
