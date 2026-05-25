#!/usr/bin/env python3
import argparse
import csv
import glob
import json
import re
import statistics
from pathlib import Path
from typing import Dict, List, Optional, Tuple


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_RESULTS_ROOT = Path("/home/lilinzhen/colocate_lab/results/cbs")
DEFAULT_OUT = REPO_ROOT / "docs/results/stage1_smart_repeat_level.csv"
DEFAULT_AGG_OUT = REPO_ROOT / "docs/results/stage1_smart_aggregated.csv"

BASELINE_ORDER = {
    "baseline_none": 0,
    "baseline_after_membw": 20,
    "baseline_after_l3": 40,
    "baseline_after_mcf": 60,
    "baseline_final": 90,
}

CONDITION_ORDER = {
    "baseline_none": 0,
    "ibench_cpu_w8": 5,
    "ibench_membw_w2": 10,
    "ibench_membw_w4": 11,
    "ibench_membw_w8": 12,
    "baseline_after_membw": 20,
    "ibench_l3_w2": 30,
    "ibench_l3_w4": 31,
    "ibench_l3_w8": 32,
    "baseline_after_l3": 40,
    "spec_mcf_ref_c2": 50,
    "spec_mcf_ref_c4": 51,
    "spec_mcf_ref_c8": 52,
    "baseline_after_mcf": 60,
    "spec_lbm_ref_c2": 70,
    "spec_lbm_ref_c4": 71,
    "spec_lbm_ref_c8": 72,
    "baseline_final": 90,
}


def read_env(path: Path) -> Dict[str, str]:
    out = {}
    if not path.exists():
        return out
    for line in path.read_text(errors="ignore").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        out[k.strip()] = v.strip()
    return out


def read_json(path: Path) -> Dict:
    try:
        return json.loads(path.read_text(errors="ignore"))
    except Exception:
        return {}


def fnum(x) -> Optional[float]:
    try:
        if x is None or str(x).strip() == "":
            return None
        return float(x)
    except Exception:
        return None


def clean_cpuset(s: str) -> str:
    return ",".join(part.strip() for part in str(s or "").split(",") if part.strip())


def latest_inspect_cpuset(run_dir: Path, kind: str) -> Tuple[str, str]:
    if kind == "server":
        files = [run_dir / "machine_topology" / "server_container.inspect.json"]
    elif kind == "loadgen":
        files = [run_dir / "machine_topology" / "loadgen_container.inspect.json"]
    else:
        files = sorted((run_dir / "machine_topology").glob("offline_container_*.inspect.json"))

    cpus = ""
    mems = ""
    for f in files:
        try:
            d = json.loads(f.read_text(errors="ignore"))[0]["HostConfig"]
            cpus = d.get("CpusetCpus") or cpus
            mems = d.get("CpusetMems") or mems
        except Exception:
            pass
    return cpus, mems


def parse_condition_from_json_name(path: Path) -> Tuple[str, str]:
    m = re.match(r"(.+)_repeat_([0-9]+)\.json$", path.name)
    if not m:
        return "", ""
    return m.group(1), m.group(2)


def infer_offline_from_condition(condition: str) -> Tuple[str, str, str, str, str]:
    if condition.startswith("baseline"):
        return "none", "none", "none", "", ""
    if condition == "ibench_cpu_w8":
        return "ibench_cpu", "8", "w8", "", ""
    if condition.startswith("ibench_membw_w"):
        w = condition.rsplit("w", 1)[-1]
        return "ibench_membw", w, f"w{w}", "", ""
    if condition.startswith("ibench_l3_w"):
        w = condition.rsplit("w", 1)[-1]
        return "ibench_l3", w, f"w{w}", "", ""
    if condition.startswith("spec_mcf_ref_c"):
        c = condition.rsplit("c", 1)[-1]
        return "spec_mcf", "none", f"ref_c{c}", "ref", c
    if condition.startswith("spec_lbm_ref_c"):
        c = condition.rsplit("c", 1)[-1]
        return "spec_lbm", "none", f"ref_c{c}", "ref", c
    return "unknown", "", "", "", ""


def expected_relation(exp_name: str, run_dir: Path) -> str:
    s = f"{exp_name} {run_dir.name}"
    if "same_smt" in s:
        return "same_smt"
    if "cross_numa" in s:
        return "cross_numa"
    if "same_numa" in s or "full_prewarm" in s:
        return "same_numa"
    return ""


def actual_relation(server_cpus: str, server_mems: str, offline_cpus: str, offline_mems: str) -> str:
    offline_cpus = clean_cpuset(offline_cpus)
    server_mems = str(server_mems or "").strip()
    offline_mems = str(offline_mems or "").strip()

    if offline_cpus == "32,34,36,38,40,42,44,46":
        return "same_smt"
    if server_mems and offline_mems:
        return "same_numa" if server_mems == offline_mems else "cross_numa"
    return ""


def placement_info(exp_name: str, run_dir: Path, server_cpus: str, server_mems: str, offline_cpus: str, offline_mems: str) -> Dict[str, str]:
    expected = expected_relation(exp_name, run_dir)
    actual = actual_relation(server_cpus, server_mems, offline_cpus, offline_mems)
    relation = actual or expected
    valid = "1"
    warning = ""
    source = "actual" if actual else "name"

    if expected and actual and expected != actual:
        valid = "0"
        warning = f"name_relation={expected}, actual_relation={actual}"
        source = "actual_conflict"

    return {
        "relation": relation,
        "relation_expected": expected,
        "relation_actual": actual,
        "relation_source": source,
        "placement_valid": valid,
        "placement_warning": warning,
    }


def is_valid_measurement(qps: Optional[float], p99: Optional[float]) -> bool:
    return qps is not None and p99 is not None and qps >= 1000 and p99 >= 20


def read_summary_rows(summary: Path) -> List[Dict[str, str]]:
    try:
        with summary.open(newline="") as f:
            return list(csv.DictReader(f))
    except Exception as e:
        print(f"[WARN] failed to read summary.csv: {summary}: {e}")
        return []


def base_topology(run_dir: Path, meta: Dict[str, str]) -> Dict[str, str]:
    server_cpus, server_mems = latest_inspect_cpuset(run_dir, "server")
    loadgen_cpus, loadgen_mems = latest_inspect_cpuset(run_dir, "loadgen")
    offline_cpus, offline_mems = latest_inspect_cpuset(run_dir, "offline")
    return {
        "server_cpuset": meta.get("SERVER_CPUSET", "") or server_cpus,
        "server_mems": meta.get("SERVER_MEMS", "") or server_mems,
        "loadgen_cpuset": meta.get("LOADGEN_CPUSET", "") or loadgen_cpus,
        "loadgen_mems": meta.get("LOADGEN_MEMS", "") or loadgen_mems,
        "offline_cpuset": meta.get("OFFLINE_CPUSET", "") or offline_cpus,
        "offline_mems": meta.get("OFFLINE_MEMS", "") or offline_mems,
    }


def normalize_summary_row(row: Dict[str, str], run_dir: Path, meta: Dict[str, str], idx: int) -> Optional[Dict[str, str]]:
    qps = fnum(row.get("qps"))
    p99 = fnum(row.get("gets_p99_ms"))
    if not is_valid_measurement(qps, p99):
        return None

    exp_name = row.get("exp_name") or meta.get("EXP_NAME", run_dir.name)
    condition = row.get("condition_id") or ""
    if not condition:
        return None

    offline_type, offline_param, offline_label, spec_size, spec_copies = infer_offline_from_condition(condition)
    offline_type = row.get("offline_type") or offline_type
    offline_param = row.get("offline_param") or offline_param
    offline_label = row.get("offline_label") or offline_label
    spec_size = row.get("spec_size") or spec_size
    spec_copies = row.get("spec_copies") or spec_copies

    topo = base_topology(run_dir, meta)
    for k in topo:
        summary_key = k.replace("cpuset", "cpuset")
        topo[k] = row.get(summary_key) or topo[k]

    place = placement_info(exp_name, run_dir, topo["server_cpuset"], topo["server_mems"], topo["offline_cpuset"], topo["offline_mems"])

    out = {
        "row_index": str(idx),
        "run_dir": str(run_dir),
        "exp_name": exp_name,
        "condition_id": condition,
        "repeat_id": row.get("repeat_id") or "1",
        "offline_type": offline_type,
        "offline_param": offline_param or ("none" if offline_type == "none" else ""),
        "offline_label": offline_label or ("none" if offline_type == "none" else ""),
        "spec_size": spec_size,
        "spec_copies": spec_copies,
        "clients_per_thread": row.get("clients_per_thread") or meta.get("CLIENTS_PER_THREAD", ""),
        "client_test_time": row.get("client_test_time") or meta.get("CLIENT_TEST_TIME", ""),
        "client_warmup_time": row.get("client_warmup_time") or meta.get("CLIENT_WARMUP_TIME", ""),
        "prewarm_rounds": row.get("prewarm_rounds") or meta.get("PREWARM_ROUNDS", ""),
        "prewarm_clients": row.get("prewarm_clients") or meta.get("PREWARM_CLIENTS", ""),
        "prewarm_test_time": row.get("prewarm_test_time") or meta.get("PREWARM_TEST_TIME", ""),
        "recovery_prewarm_rounds": row.get("recovery_prewarm_rounds") or meta.get("RECOVERY_PREWARM_ROUNDS", ""),
        "recovery_prewarm_test_time": row.get("recovery_prewarm_test_time") or meta.get("RECOVERY_PREWARM_TEST_TIME", ""),
        "server_cpuset": topo["server_cpuset"],
        "server_mems": topo["server_mems"],
        "loadgen_cpuset": topo["loadgen_cpuset"],
        "loadgen_mems": topo["loadgen_mems"],
        "offline_cpuset": topo["offline_cpuset"],
        "offline_mems": topo["offline_mems"],
        "qps": f"{qps:.2f}",
        "gets_p99_ms": f"{p99:.3f}",
        "client_log": row.get("client_log", ""),
        "client_json": row.get("client_json", ""),
        "offline_log": row.get("offline_log", ""),
        "notes": row.get("notes", ""),
    }
    out.update(place)
    return out


def collect_from_summary(run_dir: Path, meta: Dict[str, str]) -> List[Dict[str, str]]:
    rows = []
    for idx, row in enumerate(read_summary_rows(run_dir / "summary.csv")):
        out = normalize_summary_row(row, run_dir, meta, idx)
        if out:
            rows.append(out)
    return rows


def collect_from_parsed(run_dir: Path, meta: Dict[str, str]) -> List[Dict[str, str]]:
    exp_name = meta.get("EXP_NAME", run_dir.name)
    topo = base_topology(run_dir, meta)
    place = placement_info(exp_name, run_dir, topo["server_cpuset"], topo["server_mems"], topo["offline_cpuset"], topo["offline_mems"])
    rows = []
    for jf in sorted((run_dir / "parsed").glob("*_repeat_*.json")):
        condition, repeat_id = parse_condition_from_json_name(jf)
        if not condition:
            continue
        d = read_json(jf)
        qps = fnum(d.get("qps"))
        p99 = fnum(d.get("gets_p99_ms"))
        if not is_valid_measurement(qps, p99):
            continue
        offline_type, offline_param, offline_label, spec_size, spec_copies = infer_offline_from_condition(condition)
        row = {
            "row_index": str(CONDITION_ORDER.get(condition, 999)),
            "run_dir": str(run_dir),
            "exp_name": exp_name,
            "condition_id": condition,
            "repeat_id": repeat_id,
            "offline_type": offline_type,
            "offline_param": offline_param,
            "offline_label": offline_label,
            "spec_size": spec_size,
            "spec_copies": spec_copies,
            "clients_per_thread": meta.get("CLIENTS_PER_THREAD", ""),
            "client_test_time": meta.get("CLIENT_TEST_TIME", ""),
            "client_warmup_time": meta.get("CLIENT_WARMUP_TIME", ""),
            "prewarm_rounds": meta.get("PREWARM_ROUNDS", ""),
            "prewarm_clients": meta.get("PREWARM_CLIENTS", ""),
            "prewarm_test_time": meta.get("PREWARM_TEST_TIME", ""),
            "recovery_prewarm_rounds": meta.get("RECOVERY_PREWARM_ROUNDS", ""),
            "recovery_prewarm_test_time": meta.get("RECOVERY_PREWARM_TEST_TIME", ""),
            "server_cpuset": topo["server_cpuset"],
            "server_mems": topo["server_mems"],
            "loadgen_cpuset": topo["loadgen_cpuset"],
            "loadgen_mems": topo["loadgen_mems"],
            "offline_cpuset": topo["offline_cpuset"],
            "offline_mems": topo["offline_mems"],
            "qps": f"{qps:.2f}",
            "gets_p99_ms": f"{p99:.3f}",
            "client_log": "",
            "client_json": str(jf),
            "offline_log": "",
            "notes": "fallback_from_parsed_json",
        }
        row.update(place)
        rows.append(row)
    return rows


def collect_run(run_dir: Path) -> List[Dict[str, str]]:
    meta = read_env(run_dir / "experiment_meta.env")
    rows = collect_from_summary(run_dir, meta)
    if not rows:
        rows = collect_from_parsed(run_dir, meta)

    target_condition = meta.get("CONDITION_ID", "")
    if target_condition and not any(r["condition_id"] == target_condition for r in rows):
        print(f"[WARN] no valid target condition row: {run_dir}: CONDITION_ID={target_condition}")
        return []

    return rows


def baseline_values(rows: List[Dict[str, str]]) -> Tuple[Optional[float], Optional[float]]:
    qps = [float(r["qps"]) for r in rows if r["condition_id"].startswith("baseline")]
    p99 = [float(r["gets_p99_ms"]) for r in rows if r["condition_id"].startswith("baseline")]
    if not qps:
        return None, None
    return statistics.median(qps), statistics.median(p99)


def nearest_baseline(row: Dict[str, str], run_rows: List[Dict[str, str]]) -> Tuple[Optional[float], Optional[float], str]:
    baselines = [r for r in run_rows if r["condition_id"].startswith("baseline")]
    if not baselines:
        return None, None, ""

    row_idx = int(row.get("row_index") or CONDITION_ORDER.get(row["condition_id"], 999))

    def distance(b: Dict[str, str]) -> Tuple[int, int]:
        b_idx = int(b.get("row_index") or BASELINE_ORDER.get(b["condition_id"], 999))
        return (abs(row_idx - b_idx), 0 if b_idx <= row_idx else 1)

    b = min(baselines, key=distance)
    return float(b["qps"]), float(b["gets_p99_ms"]), b["condition_id"]


def add_normalized(rows: List[Dict[str, str]], mode: str) -> None:
    by_run: Dict[str, List[Dict[str, str]]] = {}
    for r in rows:
        by_run.setdefault(r["run_dir"], []).append(r)

    for run_rows in by_run.values():
        run_rows.sort(key=lambda r: int(r.get("row_index") or CONDITION_ORDER.get(r["condition_id"], 999)))
        median_qps, median_p99 = baseline_values(run_rows)
        for r in run_rows:
            if mode == "nearest":
                bqps, bp99, baseline_id = nearest_baseline(r, run_rows)
            else:
                bqps, bp99, baseline_id = median_qps, median_p99, "run_median_baseline"

            if bqps and bp99:
                qps = float(r["qps"])
                p99 = float(r["gets_p99_ms"])
                r["baseline_condition_id"] = baseline_id
                r["baseline_qps"] = f"{bqps:.2f}"
                r["baseline_p99_ms"] = f"{bp99:.3f}"
                r["qps_degradation_pct"] = f"{(bqps - qps) / bqps * 100.0:.2f}"
                r["p99_slowdown"] = f"{p99 / bp99:.3f}"
            else:
                r["baseline_condition_id"] = ""
                r["baseline_qps"] = ""
                r["baseline_p99_ms"] = ""
                r["qps_degradation_pct"] = ""
                r["p99_slowdown"] = ""


REPEAT_FIELDS = [
    "exp_name",
    "relation",
    "relation_expected",
    "relation_actual",
    "relation_source",
    "placement_valid",
    "placement_warning",
    "condition_id",
    "repeat_id",
    "offline_type",
    "offline_param",
    "offline_label",
    "spec_size",
    "spec_copies",
    "clients_per_thread",
    "client_test_time",
    "client_warmup_time",
    "prewarm_rounds",
    "prewarm_clients",
    "prewarm_test_time",
    "recovery_prewarm_rounds",
    "recovery_prewarm_test_time",
    "server_cpuset",
    "server_mems",
    "loadgen_cpuset",
    "loadgen_mems",
    "offline_cpuset",
    "offline_mems",
    "baseline_condition_id",
    "baseline_qps",
    "baseline_p99_ms",
    "qps",
    "qps_degradation_pct",
    "gets_p99_ms",
    "p99_slowdown",
    "run_dir",
    "client_json",
    "notes",
]

AGG_FIELDS = [
    "relation",
    "condition_id",
    "offline_label",
    "client_test_time",
    "prewarm_rounds",
    "prewarm_clients",
    "prewarm_test_time",
    "recovery_prewarm_rounds",
    "recovery_prewarm_test_time",
    "n",
    "baseline_qps_median",
    "qps_median",
    "qps_degradation_pct_median",
    "baseline_p99_median",
    "p99_median",
    "p99_slowdown_median",
    "run_dirs",
]


def write_csv(path: Path, fields: List[str], rows: List[Dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        for r in rows:
            w.writerow({k: r.get(k, "") for k in fields})


def agg_key(r: Dict[str, str]) -> Tuple[str, str, str, str, str, str, str, str, str]:
    return (
        r["relation"],
        r["condition_id"],
        r["offline_label"],
        r["client_test_time"],
        r["prewarm_rounds"],
        r["prewarm_clients"],
        r["prewarm_test_time"],
        r["recovery_prewarm_rounds"],
        r["recovery_prewarm_test_time"],
    )


def write_agg(path: Path, rows: List[Dict[str, str]]) -> None:
    groups: Dict[Tuple[str, str, str, str, str, str, str, str, str], List[Dict[str, str]]] = {}
    for r in rows:
        groups.setdefault(agg_key(r), []).append(r)

    out = []
    for key, rs in groups.items():
        bqps = [float(r["baseline_qps"]) for r in rs if r.get("baseline_qps")]
        bp99 = [float(r["baseline_p99_ms"]) for r in rs if r.get("baseline_p99_ms")]
        qps = [float(r["qps"]) for r in rs]
        p99 = [float(r["gets_p99_ms"]) for r in rs]
        qdeg = [float(r["qps_degradation_pct"]) for r in rs if r.get("qps_degradation_pct")]
        pslo = [float(r["p99_slowdown"]) for r in rs if r.get("p99_slowdown")]
        out.append({
            "relation": key[0],
            "condition_id": key[1],
            "offline_label": key[2],
            "client_test_time": key[3],
            "prewarm_rounds": key[4],
            "prewarm_clients": key[5],
            "prewarm_test_time": key[6],
            "recovery_prewarm_rounds": key[7],
            "recovery_prewarm_test_time": key[8],
            "n": str(len(rs)),
            "baseline_qps_median": f"{statistics.median(bqps):.2f}" if bqps else "",
            "qps_median": f"{statistics.median(qps):.2f}",
            "qps_degradation_pct_median": f"{statistics.median(qdeg):.2f}" if qdeg else "",
            "baseline_p99_median": f"{statistics.median(bp99):.3f}" if bp99 else "",
            "p99_median": f"{statistics.median(p99):.3f}",
            "p99_slowdown_median": f"{statistics.median(pslo):.3f}" if pslo else "",
            "run_dirs": ";".join(sorted(set(r["run_dir"] for r in rs))),
        })

    out.sort(key=lambda r: (r["relation"], CONDITION_ORDER.get(r["condition_id"], 999), r["condition_id"]))
    write_csv(path, AGG_FIELDS, out)


def resolve_output(path: str) -> Path:
    p = Path(path)
    return p if p.is_absolute() else REPO_ROOT / p


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=str(DEFAULT_RESULTS_ROOT))
    ap.add_argument("--include", action="append", default=[], help="glob pattern under root, e.g. 'stage1_place_*'")
    ap.add_argument("--exclude", action="append", default=["smoke*", "*pmu*"], help="glob pattern by run dir basename")
    ap.add_argument("--out", default=str(DEFAULT_OUT))
    ap.add_argument("--agg-out", default=str(DEFAULT_AGG_OUT))
    ap.add_argument("--baseline-mode", choices=["nearest", "run-median"], default="nearest")
    ap.add_argument("--include-invalid-placement", action="store_true", help="keep runs whose name relation conflicts with recorded cpuset/mems")
    args = ap.parse_args()

    root = Path(args.root)
    patterns = args.include or [
        "stage1_90min_full_prewarm_no_repeat_*",
        "stage1_place_same_numa_*",
        "stage1_place_cross_numa_*",
        "stage1_place_same_smt_*",
        "stage1_single_*",
    ]

    run_dirs = []
    for pat in patterns:
        run_dirs.extend(Path(p) for p in glob.glob(str(root / pat)))
    run_dirs = sorted(set(d for d in run_dirs if d.is_dir()))

    filtered = []
    for d in run_dirs:
        name = d.name
        if any(Path(name).match(ex) for ex in args.exclude):
            continue
        if not ((d / "summary.csv").exists() or (d / "parsed").exists()):
            continue
        filtered.append(d)

    all_rows = []
    skipped_invalid = 0
    for d in filtered:
        rows = collect_run(d)
        if not rows:
            print(f"[WARN] no valid measured rows: {d}")
            continue
        if not args.include_invalid_placement:
            invalid = [r for r in rows if r.get("placement_valid") == "0"]
            if invalid:
                skipped_invalid += 1
                print(f"[WARN] skipped placement-conflict run: {d}: {invalid[0].get('placement_warning')}")
                continue
        all_rows.extend(rows)

    add_normalized(all_rows, args.baseline_mode)
    all_rows.sort(key=lambda r: (r["relation"], r["run_dir"], int(r.get("row_index") or 999)))

    out = resolve_output(args.out)
    agg_out = resolve_output(args.agg_out)
    write_csv(out, REPEAT_FIELDS, all_rows)
    write_agg(agg_out, all_rows)

    print(f"[OK] runs scanned: {len(filtered)}")
    print(f"[OK] placement-conflict runs skipped: {skipped_invalid}")
    print(f"[OK] valid rows: {len(all_rows)}")
    print(f"[OK] baseline mode: {args.baseline_mode}")
    print(f"[OK] wrote: {out}")
    print(f"[OK] wrote: {agg_out}")


if __name__ == "__main__":
    main()
