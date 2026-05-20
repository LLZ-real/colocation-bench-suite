#!/usr/bin/env python3
import csv
import re
from pathlib import Path
from typing import Dict, List, Optional

import matplotlib.pyplot as plt


INPUT_CSV = Path("docs/colocation_results_clean.csv")
OUT_DIR = Path("docs/figures")


def read_rows(path: Path) -> List[Dict[str, str]]:
    with path.open(newline="") as f:
        return list(csv.DictReader(f))


def to_float(value: str) -> Optional[float]:
    try:
        return float(value)
    except Exception:
        return None


def parse_copies(label: str) -> Optional[int]:
    """
    Parse labels such as:
      ref_c2
      ref_c4
      ref_c8
      ref_c8_repeat
    """
    m = re.search(r"ref_c(\d+)", label or "")
    if not m:
        return None
    return int(m.group(1))


def pick_spec_points(rows: List[Dict[str, str]], offline_type: str) -> List[Dict[str, str]]:
    """
    Use only non-repeat SPEC points for the copies gradient figure.
    Repeat points are useful for stability validation but should not duplicate
    the same x value in the main gradient curve.
    """
    points = []
    for r in rows:
        if r.get("phase") != "week3":
            continue
        if r.get("offline_type") != offline_type:
            continue

        label = r.get("offline_label", "")
        if "repeat" in label:
            continue

        copies = parse_copies(label)
        if copies is None:
            continue

        qps_deg = to_float(r.get("qps_degradation_pct", ""))
        p99_slow = to_float(r.get("p99_slowdown", ""))
        qps = to_float(r.get("qps", ""))
        p99 = to_float(r.get("gets_p99_ms", ""))

        if qps_deg is None or p99_slow is None:
            continue

        points.append({
            "copies": copies,
            "qps_degradation_pct": qps_deg,
            "p99_slowdown": p99_slow,
            "qps": qps,
            "p99": p99,
            "label": label,
        })

    points.sort(key=lambda x: x["copies"])
    return points


def save_current_figure(name: str) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    png = OUT_DIR / f"{name}.png"
    pdf = OUT_DIR / f"{name}.pdf"
    plt.savefig(png, dpi=200, bbox_inches="tight")
    plt.savefig(pdf, bbox_inches="tight")
    print(f"[OK] wrote {png}")
    print(f"[OK] wrote {pdf}")


def plot_spec_qps_degradation(rows: List[Dict[str, str]]) -> None:
    mcf = pick_spec_points(rows, "spec_mcf")
    lbm = pick_spec_points(rows, "spec_lbm")

    plt.figure(figsize=(7.0, 4.2))

    if mcf:
        plt.plot(
            [p["copies"] for p in mcf],
            [p["qps_degradation_pct"] for p in mcf],
            marker="o",
            label="SPEC 505.mcf_r",
        )

    if lbm:
        plt.plot(
            [p["copies"] for p in lbm],
            [p["qps_degradation_pct"] for p in lbm],
            marker="o",
            label="SPEC 519.lbm_r",
        )

    plt.xlabel("SPEC copies")
    plt.ylabel("TaoBench QPS degradation (%)")
    plt.title("Stage 1: QPS degradation vs. SPEC offline intensity")
    plt.xticks([2, 4, 8])
    plt.grid(True, axis="y", linestyle="--", linewidth=0.6, alpha=0.7)
    plt.legend()
    save_current_figure("stage1_spec_qps_degradation_vs_copies")
    plt.close()


def plot_spec_p99_slowdown(rows: List[Dict[str, str]]) -> None:
    mcf = pick_spec_points(rows, "spec_mcf")
    lbm = pick_spec_points(rows, "spec_lbm")

    plt.figure(figsize=(7.0, 4.2))

    if mcf:
        plt.plot(
            [p["copies"] for p in mcf],
            [p["p99_slowdown"] for p in mcf],
            marker="o",
            label="SPEC 505.mcf_r",
        )

    if lbm:
        plt.plot(
            [p["copies"] for p in lbm],
            [p["p99_slowdown"] for p in lbm],
            marker="o",
            label="SPEC 519.lbm_r",
        )

    plt.xlabel("SPEC copies")
    plt.ylabel("TaoBench P99 slowdown")
    plt.title("Stage 1: P99 slowdown vs. SPEC offline intensity")
    plt.xticks([2, 4, 8])
    plt.grid(True, axis="y", linestyle="--", linewidth=0.6, alpha=0.7)
    plt.legend()
    save_current_figure("stage1_spec_p99_slowdown_vs_copies")
    plt.close()


def row_by_type_label(rows: List[Dict[str, str]], offline_type: str, label: str) -> Optional[Dict[str, str]]:
    for r in rows:
        if r.get("offline_type") == offline_type and r.get("offline_label") == label:
            return r
    return None


def make_key_workload_rows(rows: List[Dict[str, str]]) -> List[Dict[str, str]]:
    """
    Key points for presentation.
    Avoid too many rows; keep this slide-friendly.
    """
    specs = [
        ("none", "none", "TaoBench only"),
        ("ibench_cpu", "w30", "iBench CPU w30"),
        ("ibench_membw", "w8", "iBench memBw w8"),
        ("ibench_l3", "w8", "iBench L3 w8"),
        ("spec_mcf", "ref_c2", "mcf ref c2"),
        ("spec_mcf", "ref_c4", "mcf ref c4"),
        ("spec_mcf", "ref_c8", "mcf ref c8"),
        ("spec_lbm", "ref_c2", "lbm ref c2"),
        ("spec_lbm", "ref_c4", "lbm ref c4"),
        ("spec_lbm", "ref_c8", "lbm ref c8"),
    ]

    selected = []
    for offline_type, label, display in specs:
        r = row_by_type_label(rows, offline_type, label)
        if r is None:
            continue
        new_r = dict(r)
        new_r["display_name"] = display
        selected.append(new_r)

    return selected


def plot_key_qps_degradation(rows: List[Dict[str, str]]) -> None:
    selected = make_key_workload_rows(rows)

    names = [r["display_name"] for r in selected]
    values = [to_float(r.get("qps_degradation_pct", "")) or 0.0 for r in selected]

    plt.figure(figsize=(9.5, 4.8))
    plt.bar(range(len(values)), values)
    plt.xticks(range(len(values)), names, rotation=35, ha="right")
    plt.ylabel("QPS degradation (%)")
    plt.title("Stage 1: Key workload impact on TaoBench QPS")
    plt.grid(True, axis="y", linestyle="--", linewidth=0.6, alpha=0.7)
    save_current_figure("stage1_key_workloads_qps_degradation")
    plt.close()


def plot_key_p99_slowdown(rows: List[Dict[str, str]]) -> None:
    selected = make_key_workload_rows(rows)

    names = [r["display_name"] for r in selected]
    values = [to_float(r.get("p99_slowdown", "")) or 0.0 for r in selected]

    plt.figure(figsize=(9.5, 4.8))
    plt.bar(range(len(values)), values)
    plt.xticks(range(len(values)), names, rotation=35, ha="right")
    plt.ylabel("P99 slowdown")
    plt.title("Stage 1: Key workload impact on TaoBench P99 latency")
    plt.grid(True, axis="y", linestyle="--", linewidth=0.6, alpha=0.7)
    save_current_figure("stage1_key_workloads_p99_slowdown")
    plt.close()


def main() -> None:
    if not INPUT_CSV.exists():
        raise SystemExit(f"Input CSV not found: {INPUT_CSV}")

    rows = read_rows(INPUT_CSV)

    plot_spec_qps_degradation(rows)
    plot_spec_p99_slowdown(rows)
    plot_key_qps_degradation(rows)
    plot_key_p99_slowdown(rows)

    print()
    print("[DONE] Figures are under docs/figures/")


if __name__ == "__main__":
    main()
