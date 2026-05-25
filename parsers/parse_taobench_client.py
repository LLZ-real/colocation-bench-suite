#!/usr/bin/env python3
import argparse
import json
import re
from pathlib import Path

def parse_log(path: Path):
    text = path.read_text(errors="ignore")
    result = {
        "log": str(path),
        "qps": None,
        "gets_p99_ms": None,
        "raw_totals_line": None,
        "raw_gets_line": None,
        "has_final_stats": False,
        "dcperf_role": None,
        "diagnostic_status": "missing_final_stats",
        "progress_last_line": None,
        "progress_last_avg_ops_sec": None,
        "progress_last_avg_latency_ms": None,
    }

    for line in text.splitlines():
        parts = line.split()
        if not parts:
            continue

        if line.lstrip().startswith("[RUN #"):
            result["progress_last_line"] = line.strip()
            m_ops = re.search(r"\(avg:\s*([0-9.]+)\)\s+ops/sec", line)
            if m_ops:
                try:
                    result["progress_last_avg_ops_sec"] = float(m_ops.group(1))
                except ValueError:
                    pass
            m_lat = re.search(r"\(avg:\s*([0-9.]+)\)\s+msec latency", line)
            if m_lat:
                try:
                    result["progress_last_avg_latency_ms"] = float(m_lat.group(1))
                except ValueError:
                    pass

        if parts[0] == "Totals":
            result["has_final_stats"] = True
            result["raw_totals_line"] = line
            if len(parts) >= 2:
                try:
                    result["qps"] = float(parts[1])
                except ValueError:
                    pass

        if parts[0] == "Gets":
            result["has_final_stats"] = True
            result["raw_gets_line"] = line
            if len(parts) >= 7:
                try:
                    result["gets_p99_ms"] = float(parts[6])
                except ValueError:
                    pass

        if line.startswith('{"machines":'):
            try:
                d = json.loads(line)
                role = d.get("metrics", {}).get("role")
                if role:
                    result["dcperf_role"] = role
            except Exception:
                pass

    if result["qps"] is not None and result["gets_p99_ms"] is not None:
        result["diagnostic_status"] = "ok"
    elif result["dcperf_role"] == "unknown":
        result["diagnostic_status"] = "dcperf_role_unknown_no_final_stats"
    elif result["progress_last_line"]:
        result["diagnostic_status"] = "progress_seen_no_final_stats"

    return result

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log")
    ap.add_argument("--json-out")
    args = ap.parse_args()

    result = parse_log(Path(args.log))

    if args.json_out:
        Path(args.json_out).write_text(json.dumps(result, indent=2))
    else:
        print(json.dumps(result, indent=2))

if __name__ == "__main__":
    main()
