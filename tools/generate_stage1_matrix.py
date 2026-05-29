#!/usr/bin/env python3
"""Generate Stage 1 condition matrix CSV for the sweep experiment."""
import argparse
import csv
import sys
from pathlib import Path


IBENCH_TYPES = ["ibench_cpu", "ibench_membw", "ibench_l3"]
IBENCH_WORKERS = [1, 2, 4, 6, 8]
IBENCH_ARGS = [30, 60, 90]

SPEC_BENCHMARKS = [
    ("503.bwaves_r", [1, 2, 4, 8], "memory"),
    ("505.mcf_r", [1, 2, 4, 8], "memory"),
    ("519.lbm_r", [1, 2, 4, 8], "memory"),
    ("549.fotonik3d_r", [1, 2, 4], "memory"),
    ("554.roms_r", [1, 2, 4], "memory"),
    ("508.namd_r", [1, 2, 4, 8], "compute"),
    ("511.povray_r", [1, 2, 4, 8], "compute"),
    ("538.imagick_r", [1, 2, 4, 8], "compute"),
    ("526.blender_r", [1, 2, 4], "compute"),
    ("502.gcc_r", [1, 2, 4, 8], "branch"),
    ("541.leela_r", [1, 2, 4, 8], "branch"),
    ("523.xalancbmk_r", [1, 2, 4], "branch"),
    ("531.deepsjeng_r", [1, 2, 4], "branch"),
    ("525.x264_r", [1, 2, 4, 8], "mixed"),
    ("521.wrf_r", [1, 2, 4], "mixed"),
    ("527.cam4_r", [1, 2, 4], "mixed"),
]

MATRIX_FIELDS = [
    "condition_id", "offline_type", "offline_param",
    "offline_intensity", "offline_label",
    "spec_size", "spec_copies", "spec_bench",
    "workload_category", "resource_profile",
]


def generate_ibench() -> list[dict]:
    rows = []
    for bench_type in IBENCH_TYPES:
        for w in IBENCH_WORKERS:
            for a in IBENCH_ARGS:
                rows.append({
                    "condition_id": f"{bench_type}_w{w}_a{a}",
                    "offline_type": bench_type,
                    "offline_param": str(w),
                    "offline_intensity": str(a),
                    "offline_label": f"w{w}_a{a}",
                    "spec_size": "",
                    "spec_copies": "",
                    "spec_bench": "",
                    "workload_category": "ibench",
                    "resource_profile": bench_type.split("_")[1],
                })
    return rows


def generate_spec() -> list[dict]:
    rows = []
    for bench, copies_list, profile in SPEC_BENCHMARKS:
        for c in copies_list:
            short = bench.replace(".", "_").replace("_r", "")
            rows.append({
                "condition_id": f"spec_{short}_c{c}",
                "offline_type": "spec",
                "offline_param": "",
                "offline_intensity": "",
                "offline_label": f"c{c}",
                "spec_size": "ref",
                "spec_copies": str(c),
                "spec_bench": bench,
                "workload_category": "spec",
                "resource_profile": profile,
            })
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=["ibench", "spec", "all"], default="all")
    ap.add_argument("--out", default="")
    args = ap.parse_args()

    rows = []
    if args.mode in ("ibench", "all"):
        rows.extend(generate_ibench())
    if args.mode in ("spec", "all"):
        rows.extend(generate_spec())

    if args.out:
        out = Path(args.out)
        out.parent.mkdir(parents=True, exist_ok=True)
        with out.open("w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=MATRIX_FIELDS)
            w.writeheader()
            w.writerows(rows)
        print(f"[OK] wrote {len(rows)} conditions to {out}")
        print(f"     iBench: {sum(1 for r in rows if r['workload_category'] == 'ibench')}")
        print(f"     SPEC:   {sum(1 for r in rows if r['workload_category'] == 'spec')}")
    else:
        w = csv.DictWriter(sys.stdout, fieldnames=MATRIX_FIELDS)
        w.writeheader()
        w.writerows(rows)


if __name__ == "__main__":
    main()
