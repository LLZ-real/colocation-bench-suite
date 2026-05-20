#!/usr/bin/env python3
import csv
import re
from pathlib import Path
from typing import Dict, List, Optional

RESULTS_ROOT = Path("/home/lilinzhen/colocate_lab/results/cbs")
OUT_CSV = Path("docs/colocation_results_clean.csv")

BASELINE_QPS = 165508.28
BASELINE_P99 = 99.327

FIELDS = [
    "phase",
    "offline_type",
    "offline_param",
    "offline_label",
    "clients_per_thread",
    "qps",
    "qps_degradation_pct",
    "gets_p99_ms",
    "p99_slowdown",
    "run_dir",
    "notes",
]

# Only these manually verified results should be included as the stable baseline.
MANUAL_ROWS = [
    {
        "phase": "baseline",
        "offline_type": "none",
        "offline_param": "none",
        "offline_label": "none",
        "clients_per_thread": "900",
        "qps": "165508.28",
        "gets_p99_ms": "99.327",
        "run_dir": "/home/lilinzhen/colocate_lab/results/cbs/20260506_172911_week2_taobench_baseline_none_",
        "notes": "TaoBench only stable baseline",
    }
]


def is_formal_run_dir(run_dir: Path) -> bool:
    """
    Include only formal Week2/Week3 colocation runs.
    Exclude early baseline curves, smoke runs, and unstable exploratory runs.
    """
    name = run_dir.name

    exclude = [
        "taobench_baseline_curve",
        "smoke_",
        "mediawiki",
    ]
    if any(x in name for x in exclude):
        return False

    include = [
        "week2_taobench_baseline_none",
        "week2_taobench_ibench",
        "week3_taobench_spec",
    ]
    return any(x in name for x in include)


def infer_phase(run_dir: Path, offline_type: str) -> str:
    name = run_dir.name
    if offline_type == "none":
        return "baseline"
    if "week2" in name:
        return "week2"
    if "week3" in name:
        return "week3"
    return "unknown"


def infer_spec_label(run_dir: Path, row: Dict[str, str]) -> str:
    """
    Infer SPEC semantic label from new summary first, then from run dir.
    """
    label = (row.get("offline_label") or "").strip()
    if label:
        return label

    # Old Week 3 summaries used offline_param as the semantic SPEC label.
    # Keep runtime params and report labels separate in the cleaned CSV.
    old_param = (row.get("offline_param") or "").strip()
    if re.fullmatch(r"(train|test|ref)_c\d+(_repeat)?", old_param):
        return old_param

    name = run_dir.name

    if "train" in name and "c1" in name:
        return "train_c1"
    if "spec_mcf_train" in name:
        return "train_c1"

    # Repeat should be checked before ref_c8.
    if "ref_c8_repeat" in name:
        return "ref_c8_repeat"
    if "ref_c4_repeat" in name:
        return "ref_c4_repeat"
    if "ref_c2_repeat" in name:
        return "ref_c2_repeat"

    if "ref_c8" in name:
        return "ref_c8"
    if "ref_c4" in name:
        return "ref_c4"
    if "ref_c2" in name:
        return "ref_c2"

    # Fallback: parse cN if available.
    m = re.search(r"ref_c(\d+)", name)
    if m:
        return f"ref_c{m.group(1)}"

    return ""


def infer_ibench_label(row: Dict[str, str], run_dir: Path) -> str:
    """
    For iBench, offline_param is the true runtime parameter.
    offline_label is only semantic label.
    """
    label = (row.get("offline_label") or "").strip()
    if label:
        return label

    param = (row.get("offline_param") or "").strip()
    name = run_dir.name

    # Detect repeat first.
    if "repeat" in name and param:
        return f"w{param}_repeat"

    # Detect wN in directory name.
    m = re.search(r"_w(\d+)", name)
    if m:
        return f"w{m.group(1)}"

    if param:
        return f"w{param}"

    return ""


def normalize_row(row: Dict[str, str], run_dir: Path) -> Optional[Dict[str, str]]:
    offline_type = (row.get("offline_type") or "").strip()
    if not offline_type:
        return None

    qps = (row.get("qps") or "").strip()
    p99 = (row.get("gets_p99_ms") or "").strip()

    if not qps or not p99:
        return None

    try:
        float(qps)
        float(p99)
    except ValueError:
        return None

    clients = (row.get("clients_per_thread") or "").strip()

    if offline_type.startswith("spec_"):
        # Important: SPEC should not use offline_param for ref_c8/train_c1.
        # SPEC runtime parameters are SPEC_SIZE/SPEC_COPIES, while label stores semantic info.
        offline_param = "none"
        offline_label = infer_spec_label(run_dir, row)
    elif offline_type.startswith("ibench_"):
        # Important: iBench offline_param is the real runtime parameter.
        offline_param = (row.get("offline_param") or "").strip()
        offline_label = infer_ibench_label(row, run_dir)
    elif offline_type == "none":
        offline_param = "none"
        offline_label = "none"
    else:
        offline_param = (row.get("offline_param") or "").strip()
        offline_label = (row.get("offline_label") or offline_param or "").strip()

    phase = infer_phase(run_dir, offline_type)

    return {
        "phase": phase,
        "offline_type": offline_type,
        "offline_param": offline_param,
        "offline_label": offline_label,
        "clients_per_thread": clients,
        "qps": qps,
        "gets_p99_ms": p99,
        "run_dir": str(run_dir),
        "notes": make_notes(offline_type, offline_param, offline_label),
    }


def make_notes(offline_type: str, offline_param: str, offline_label: str) -> str:
    if offline_type == "none":
        return "TaoBench only stable baseline"
    if offline_type == "ibench_cpu":
        return "CPU interference on separate physical cores"
    if offline_type == "ibench_membw":
        if "repeat" in offline_label:
            return "Synthetic memory bandwidth interference repeat"
        return "Synthetic memory bandwidth interference"
    if offline_type == "ibench_l3":
        return "Synthetic LLC/cache interference"
    if offline_type == "spec_mcf":
        if offline_label == "train_c1":
            return "SPEC 505.mcf_r train 1 copy"
        if "repeat" in offline_label:
            return "SPEC 505.mcf_r ref 8 copies repeat"
        return f"SPEC 505.mcf_r {offline_label}"
    if offline_type == "spec_lbm":
        if "repeat" in offline_label:
            return "SPEC 519.lbm_r ref 8 copies repeat"
        return f"SPEC 519.lbm_r {offline_label}"
    return ""


def add_degradation(row: Dict[str, str]) -> Dict[str, str]:
    try:
        qps = float(row["qps"])
        p99 = float(row["gets_p99_ms"])

        qps_deg = (BASELINE_QPS - qps) / BASELINE_QPS * 100.0
        p99_slow = p99 / BASELINE_P99

        row["qps_degradation_pct"] = f"{qps_deg:.1f}"
        row["p99_slowdown"] = f"{p99_slow:.2f}"
    except Exception:
        row["qps_degradation_pct"] = ""
        row["p99_slowdown"] = ""

    return row


def output_row(row: Dict[str, str]) -> Dict[str, str]:
    """
    Return exactly the cleaned CSV schema, in FIELDS order.
    This avoids old/new summary.csv formats leaking extra or shifted fields.
    """
    return {field: row.get(field, "") for field in FIELDS}


def read_summary(summary_path: Path) -> List[Dict[str, str]]:
    rows = []
    try:
        with summary_path.open(newline="") as f:
            reader = csv.DictReader(f)
            for row in reader:
                normalized = normalize_row(row, summary_path.parent)
                if normalized is not None:
                    rows.append(normalized)
    except Exception as e:
        print(f"[WARN] failed to read {summary_path}: {e}")
    return rows


def deduplicate(rows: List[Dict[str, str]]) -> List[Dict[str, str]]:
    """
    Dedup by run_dir + offline_type + label.
    Manual baseline may have same run_dir as a discovered row; prefer manual row for baseline.
    """
    out: Dict[tuple, Dict[str, str]] = {}

    for row in rows:
        key = (
            row.get("phase", ""),
            row.get("offline_type", ""),
            row.get("offline_param", ""),
            row.get("offline_label", ""),
            row.get("run_dir", ""),
        )
        out[key] = row

    return list(out.values())


def sort_key(row: Dict[str, str]):
    phase_order = {
        "baseline": 0,
        "week2": 1,
        "week3": 2,
        "unknown": 9,
    }
    type_order = {
        "none": 0,
        "ibench_cpu": 1,
        "ibench_membw": 2,
        "ibench_l3": 3,
        "spec_mcf": 4,
        "spec_lbm": 5,
    }

    label = row.get("offline_label", "")

    # Sort labels naturally: train first, c2, c4, c8, repeat later.
    label_order = 50
    if label == "none":
        label_order = 0
    elif label == "train_c1":
        label_order = 1
    elif label == "w2" or label == "ref_c2":
        label_order = 2
    elif label == "w4" or label == "ref_c4":
        label_order = 4
    elif label == "w8" or label == "ref_c8":
        label_order = 8
    elif "repeat" in label:
        label_order = 9

    return (
        phase_order.get(row.get("phase", "unknown"), 9),
        type_order.get(row.get("offline_type", ""), 99),
        label_order,
        row.get("offline_label", ""),
        row.get("run_dir", ""),
    )


def main():
    rows: List[Dict[str, str]] = []

    # Add manually verified stable baseline.
    for r in MANUAL_ROWS:
        rows.append(add_degradation(dict(r)))

    # Add formal run dirs only.
    for run_dir in sorted(RESULTS_ROOT.glob("*")):
        if not run_dir.is_dir():
            continue
        if not is_formal_run_dir(run_dir):
            continue

        summary = run_dir / "summary.csv"
        if not summary.exists():
            continue

        for r in read_summary(summary):
            # Skip duplicate baseline discovered from files; manual baseline is cleaner.
            if r["offline_type"] == "none":
                continue
            rows.append(add_degradation(r))

    rows = deduplicate(rows)
    rows.sort(key=sort_key)

    OUT_CSV.parent.mkdir(parents=True, exist_ok=True)
    with OUT_CSV.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=FIELDS)
        writer.writeheader()
        for r in rows:
            writer.writerow(output_row(r))

    with OUT_CSV.open(newline="") as f:
        reader = csv.reader(f)
        header = next(reader)
        expected_cols = len(header)
        for line_no, row in enumerate(reader, start=2):
            if len(row) != expected_cols:
                raise RuntimeError(
                    f"{OUT_CSV}:{line_no} has {len(row)} columns; "
                    f"expected {expected_cols}"
                )

    print(f"[OK] wrote {OUT_CSV}")
    print()
    with OUT_CSV.open() as f:
        print(f.read())


if __name__ == "__main__":
    main()
