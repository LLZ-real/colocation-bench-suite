#!/usr/bin/env python3
"""Parse Stage 1-B PMU + QPS data into a modeling-ready feature matrix.

Usage:
  python3 tools/parse_stage1_pmu.py --run-dir <run_dir> --out <output.csv>

Output:
  feature_matrix.csv — one row per condition, PMU features + QPS/P99 targets
  pmu_summary.csv   — raw PMU stats per condition (mean, median, std per event)
"""
import argparse
import csv
import re
import sys
from collections import defaultdict
from pathlib import Path

import pandas as pd
import numpy as np

PERF_COLUMNS = ["time", "count", "unit", "event", "runtime", "pct", "extra1", "extra2"]


def read_perf_csv(path: Path) -> pd.DataFrame:
    """Read a single perf stat CSV file, return cleaned DataFrame."""
    if not path.exists() or path.stat().st_size == 0:
        return pd.DataFrame()

    df = pd.read_csv(
        path,
        sep=",",
        header=None,
        names=PERF_COLUMNS,
        comment="#",
        engine="python",
        on_bad_lines="skip",
        dtype=str,
    )

    # Strip whitespace from all string columns
    for col in df.columns:
        df[col] = df[col].str.strip()

    # Drop empty or comment lines
    df = df[~df["time"].str.startswith("#", na=False)]
    df = df[df["time"].str.match(r"^\d+\.?\d*$", na=False)]

    # Convert numeric columns
    for col in ["count", "runtime", "pct"]:
        df[col] = pd.to_numeric(df[col], errors="coerce")

    df = df.dropna(subset=["count", "event"])
    return df


def aggregate_pmu(df: pd.DataFrame, condition_id: str) -> dict:
    """Aggregate PMU metrics per event into mean/median/std."""
    if df.empty:
        return {}

    features = {"condition_id": condition_id}

    # Per-event aggregate stats
    for event, group in df.groupby("event"):
        counts = group["count"].dropna()
        if len(counts) < 2:
            continue

        features[f"{event}_mean"] = round(counts.mean(), 1)
        features[f"{event}_median"] = round(counts.median(), 1)
        features[f"{event}_std"] = round(counts.std(), 1)

    # Derived features (computed from aggregated means)
    _add_derived(features)

    return features


def _add_derived(f):
    """Add derived PMU metrics from raw counters."""
    # IPC
    if all(k in f for k in ["instructions_mean", "cycles_mean"]) and f["cycles_mean"] > 0:
        f["IPC"] = round(f["instructions_mean"] / f["cycles_mean"], 4)

    # LLC miss rate
    if all(k in f for k in ["LLC-load-misses_mean", "LLC-loads_mean"]) and f["LLC-loads_mean"] > 0:
        f["LLC_miss_rate"] = round(f["LLC-load-misses_mean"] / f["LLC-loads_mean"], 4)

    # L1 dcache miss rate
    if all(k in f for k in ["L1-dcache-load-misses_mean", "L1-dcache-loads_mean"]) and f["L1-dcache-loads_mean"] > 0:
        f["L1_dcache_miss_rate"] = round(f["L1-dcache-load-misses_mean"] / f["L1-dcache-loads_mean"], 4)

    # Branch miss rate
    if all(k in f for k in ["branch-misses_mean", "branch-instructions_mean"]) and f["branch-instructions_mean"] > 0:
        f["branch_miss_rate"] = round(f["branch-misses_mean"] / f["branch-instructions_mean"], 4)

    # L2 miss rate
    if all(k in f for k in ["l2_rqsts.all_demand_miss_mean", "l2_rqsts.all_demand_data_rd_mean"]) and f["l2_rqsts.all_demand_data_rd_mean"] > 0:
        f["L2_miss_rate"] = round(f["l2_rqsts.all_demand_miss_mean"] / f["l2_rqsts.all_demand_data_rd_mean"], 4)

    # Cache miss ratio (cache-references vs cache-misses)
    if all(k in f for k in ["cache-references_mean", "cache-misses_mean"]) and f["cache-references_mean"] > 0:
        f["cache_miss_rate"] = round(f["cache-misses_mean"] / f["cache-references_mean"], 4)

    # Context switches per second (proxy: count / runtime_seconds)
    # Approximate using the first perf interval time as sample period
    # (PERF_DURATION is exact, use it from meta if available)


def read_summary_csv(path: Path) -> dict:
    """Read summary.csv and return {condition_id: {qps, p99, ...}}."""
    result = {}
    if not path.exists():
        return result
    with path.open() as f:
        for r in csv.DictReader(f):
            cid = r.get("condition_id", "")
            if cid:
                qps = r.get("qps", "")
                p99 = r.get("gets_p99_ms", "")
                result[cid] = {
                    "qps": float(qps) if qps else 0.0,
                    "p99_ms": float(p99) if p99 else 0.0,
                    "placement": r.get("placement", ""),
                    "offline_type": r.get("offline_type", ""),
                }
    return result


def read_pmu_meta(path: Path) -> dict:
    """Read pmu_meta.env for PMU duration and event list."""
    meta = {}
    if not path.exists():
        return meta
    for line in path.read_text(errors="ignore").splitlines():
        line = line.strip()
        if "=" in line:
            k, v = line.split("=", 1)
            meta[k] = v
    return meta


def main():
    ap = argparse.ArgumentParser(description="Parse Stage 1-B PMU data")
    ap.add_argument("--run-dir", required=True, help="Stage 1-B run directory")
    ap.add_argument("--out", default="", help="Output feature matrix CSV path")
    ap.add_argument("--pmu-summary", default="", help="Output raw PMU summary CSV path")
    args = ap.parse_args()

    run_dir = Path(args.run_dir)
    if not run_dir.is_dir():
        print(f"[ERROR] Not a directory: {run_dir}")
        sys.exit(1)

    pmu_dir = run_dir / "pmu"
    summary_csv = run_dir / "summary.csv"
    meta = read_pmu_meta(pmu_dir / "pmu_meta.env")
    qps_data = read_summary_csv(summary_csv)

    print(f"Run dir:  {run_dir}")
    print(f"PMU dir:  {pmu_dir}")
    print(f"Duration: {meta.get('PERF_DURATION', '?')}s")
    print(f"Events:   {meta.get('PMU_EVENTS', '?')[:80]}...")

    # Process each condition
    conditions_found = 0
    conditions_ok = 0
    all_features = []
    all_raw = []

    for cond_dir in sorted(pmu_dir.iterdir()):
        if not cond_dir.is_dir():
            continue
        condition_id = cond_dir.name
        conditions_found += 1

        perf_csv = cond_dir / "host_perf.csv"
        if not perf_csv.exists() or perf_csv.stat().st_size == 0:
            print(f"  [SKIP] {condition_id}: no perf CSV")
            continue

        df = read_perf_csv(perf_csv)
        if df.empty:
            print(f"  [SKIP] {condition_id}: empty perf data")
            continue

        # Aggregate PMU
        features = aggregate_pmu(df, condition_id)

        # Add QPS/P99 from summary
        qps_row = qps_data.get(condition_id, {})
        features["qps"] = qps_row.get("qps", 0.0)
        features["p99_ms"] = qps_row.get("p99_ms", 0.0)
        features["placement"] = qps_row.get("placement", "")
        features["offline_type"] = qps_row.get("offline_type", "")

        # Count valid samples
        features["pmu_samples"] = len(df)
        features["pmu_event_types"] = df["event"].nunique()

        all_features.append(features)
        conditions_ok += 1

        # Also save raw per-event stats
        for event, group in df.groupby("event"):
            counts = group["count"].dropna()
            if len(counts) > 0:
                all_raw.append({
                    "condition_id": condition_id,
                    "event": event,
                    "count_mean": counts.mean(),
                    "count_median": counts.median(),
                    "count_std": counts.std(),
                    "count_min": counts.min(),
                    "count_max": counts.max(),
                    "samples": len(counts),
                })

    print(f"\nConditions found: {conditions_found}")
    print(f"Conditions parsed: {conditions_ok}")
    print(f"QPS rows available: {len(qps_data)}")

    if not conditions_ok:
        print("[ERROR] No PMU data parsed")
        sys.exit(1)

    # Write feature matrix
    if not args.out:
        args.out = str(run_dir / "pmu" / "feature_matrix.csv")
    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=all_features[0].keys())
        writer.writeheader()
        writer.writerows(all_features)
    print(f"\n[OK] Feature matrix: {out_path} ({len(all_features)} rows, {len(all_features[0]) - 3} features)")

    # Write raw PMU summary
    if not args.pmu_summary:
        args.pmu_summary = str(run_dir / "pmu" / "pmu_summary.csv")
    pmu_out = Path(args.pmu_summary)
    with pmu_out.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["condition_id", "event", "count_mean", "count_median", "count_std", "count_min", "count_max", "samples"])
        writer.writeheader()
        writer.writerows(all_raw)
    print(f"[OK] PMU summary: {pmu_out} ({len(all_raw)} rows)")


if __name__ == "__main__":
    main()
