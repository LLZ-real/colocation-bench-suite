#!/usr/bin/env python3
import argparse
import csv
import statistics
from pathlib import Path
from typing import Dict, List, Tuple, Optional

BASELINE_QPS = 165508.28
BASELINE_P99 = 99.327

REPEAT_FIELDS = [
    "timestamp",
    "exp_name",
    "repeat_id",
    "offline_type",
    "offline_param",
    "offline_label",
    "spec_size",
    "spec_copies",
    "clients_per_thread",
    "client_test_time",
    "prewarm_rounds",
    "server_cpuset",
    "server_mems",
    "loadgen_cpuset",
    "loadgen_mems",
    "offline_cpuset",
    "offline_mems",
    "qps",
    "qps_degradation_pct",
    "gets_p99_ms",
    "p99_slowdown",
    "client_log",
    "offline_log",
    "run_dir",
    "notes",
]

AGG_FIELDS = [
    "exp_name",
    "offline_type",
    "offline_param",
    "offline_label",
    "spec_size",
    "spec_copies",
    "clients_per_thread",
    "server_cpuset",
    "server_mems",
    "offline_cpuset",
    "offline_mems",
    "n",
    "qps_mean",
    "qps_median",
    "qps_stdev",
    "qps_degradation_pct_median",
    "p99_mean",
    "p99_median",
    "p99_stdev",
    "p99_slowdown_median",
    "run_dirs",
]

def fnum(x: str) -> Optional[float]:
    try:
        if x is None or str(x).strip() == "":
            return None
        return float(x)
    except Exception:
        return None

def normalize(row: Dict[str, str], run_dir: Path) -> Optional[Dict[str, str]]:
    offline_type = (row.get("offline_type") or "").strip()
    if not offline_type:
        return None

    qps = fnum(row.get("qps", ""))
    p99 = fnum(row.get("gets_p99_ms", ""))
    if qps is None or p99 is None:
        return None

    offline_param = (row.get("offline_param") or "").strip()
    offline_label = (row.get("offline_label") or offline_param or "").strip()

    if offline_type == "none":
        offline_param = "none"
        offline_label = "none"

    if offline_type.startswith("spec_"):
        if not offline_label or offline_label == "none":
            spec_size = row.get("spec_size", "") or "ref"
            spec_copies = row.get("spec_copies", "") or ""
            offline_label = f"{spec_size}_c{spec_copies}" if spec_copies else spec_size
        offline_param = "none"

    out = {
        "timestamp": row.get("timestamp", ""),
        "exp_name": row.get("exp_name", run_dir.name),
        "repeat_id": row.get("repeat_id", "1"),
        "offline_type": offline_type,
        "offline_param": offline_param,
        "offline_label": offline_label,
        "spec_size": row.get("spec_size", ""),
        "spec_copies": row.get("spec_copies", ""),
        "clients_per_thread": row.get("clients_per_thread", ""),
        "client_test_time": row.get("client_test_time", ""),
        "prewarm_rounds": row.get("prewarm_rounds", ""),
        "server_cpuset": row.get("server_cpuset", ""),
        "server_mems": row.get("server_mems", ""),
        "loadgen_cpuset": row.get("loadgen_cpuset", ""),
        "loadgen_mems": row.get("loadgen_mems", ""),
        "offline_cpuset": row.get("offline_cpuset", ""),
        "offline_mems": row.get("offline_mems", ""),
        "qps": f"{qps:.2f}",
        "qps_degradation_pct": f"{(BASELINE_QPS - qps) / BASELINE_QPS * 100.0:.2f}",
        "gets_p99_ms": f"{p99:.3f}",
        "p99_slowdown": f"{p99 / BASELINE_P99:.3f}",
        "client_log": row.get("client_log", ""),
        "offline_log": row.get("offline_log", ""),
        "run_dir": str(run_dir),
        "notes": row.get("notes", ""),
    }
    return out

def read_all(root: Path) -> List[Dict[str, str]]:
    rows: List[Dict[str, str]] = []
    for summary in sorted(root.glob("*/summary.csv")):
        run_dir = summary.parent
        try:
            with summary.open(newline="") as f:
                reader = csv.DictReader(f)
                for row in reader:
                    n = normalize(row, run_dir)
                    if n:
                        rows.append(n)
        except Exception as e:
            print(f"[WARN] failed to read {summary}: {e}")
    return rows

def group_key(r: Dict[str, str]) -> Tuple[str, ...]:
    return (
        r["exp_name"],
        r["offline_type"],
        r["offline_param"],
        r["offline_label"],
        r["spec_size"],
        r["spec_copies"],
        r["clients_per_thread"],
        r["server_cpuset"],
        r["server_mems"],
        r["offline_cpuset"],
        r["offline_mems"],
    )

def aggregate(rows: List[Dict[str, str]]) -> List[Dict[str, str]]:
    groups: Dict[Tuple[str, ...], List[Dict[str, str]]] = {}
    for r in rows:
        groups.setdefault(group_key(r), []).append(r)

    out = []
    for key, rs in groups.items():
        qps_vals = [float(r["qps"]) for r in rs]
        p99_vals = [float(r["gets_p99_ms"]) for r in rs]
        qps_deg_median = (BASELINE_QPS - statistics.median(qps_vals)) / BASELINE_QPS * 100.0
        p99_slow_median = statistics.median(p99_vals) / BASELINE_P99

        row = {
            "exp_name": key[0],
            "offline_type": key[1],
            "offline_param": key[2],
            "offline_label": key[3],
            "spec_size": key[4],
            "spec_copies": key[5],
            "clients_per_thread": key[6],
            "server_cpuset": key[7],
            "server_mems": key[8],
            "offline_cpuset": key[9],
            "offline_mems": key[10],
            "n": str(len(rs)),
            "qps_mean": f"{statistics.mean(qps_vals):.2f}",
            "qps_median": f"{statistics.median(qps_vals):.2f}",
            "qps_stdev": f"{statistics.stdev(qps_vals):.2f}" if len(qps_vals) >= 2 else "0.00",
            "qps_degradation_pct_median": f"{qps_deg_median:.2f}",
            "p99_mean": f"{statistics.mean(p99_vals):.3f}",
            "p99_median": f"{statistics.median(p99_vals):.3f}",
            "p99_stdev": f"{statistics.stdev(p99_vals):.3f}" if len(p99_vals) >= 2 else "0.000",
            "p99_slowdown_median": f"{p99_slow_median:.3f}",
            "run_dirs": ";".join(sorted(set(r["run_dir"] for r in rs))),
        }
        out.append(row)

    out.sort(key=lambda r: (r["offline_type"], r["offline_label"], r["exp_name"]))
    return out

def write_csv(path: Path, fields: List[str], rows: List[Dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        for r in rows:
            w.writerow({k: r.get(k, "") for k in fields})
    print(f"[OK] wrote {path}")

def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default="/home/lilinzhen/colocate_lab/results/cbs")
    ap.add_argument("--repeat-out", default="docs/stage1_repeat_level.csv")
    ap.add_argument("--agg-out", default="docs/stage1_aggregated.csv")
    args = ap.parse_args()

    rows = read_all(Path(args.root))
    write_csv(Path(args.repeat_out), REPEAT_FIELDS, rows)
    write_csv(Path(args.agg_out), AGG_FIELDS, aggregate(rows))

if __name__ == "__main__":
    main()