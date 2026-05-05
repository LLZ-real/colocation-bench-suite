#!/usr/bin/env python3
import argparse
import csv
from pathlib import Path

EVENTS = {
    "cycles",
    "instructions",
    "branches",
    "branch-misses",
    "cache-references",
    "cache-misses",
    "context-switches",
    "cpu-migrations",
    "page-faults",
}

def clean_number(s: str):
    s = s.strip().replace(",", "")
    if not s:
        return None
    if "<not" in s or "not" in s or "supported" in s:
        return None
    try:
        return float(s)
    except ValueError:
        return None

def parse_perf_csv_line(line: str):
    # perf stat -x, -I format usually looks like:
    # time,count,unit,event,runtime,percentage,...
    parts = line.strip().split(",")
    if len(parts) < 4:
        return None, None

    value = clean_number(parts[1])
    event = parts[3].strip()
    return event, value

def parse_perf_space_line(line: str):
    # perf default format:
    # time count event
    parts = line.split()
    if len(parts) < 3:
        return None, None

    value = clean_number(parts[1])
    event = parts[2].strip()
    return event, value

def parse_perf(path: Path):
    totals = {e: 0.0 for e in EVENTS}

    if not path.exists() or path.stat().st_size == 0:
        result = dict(totals)
        result["ipc"] = ""
        result["branch_miss_rate"] = ""
        result["cache_miss_rate"] = ""
        return result

    for raw in path.read_text(errors="ignore").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue

        if "," in line:
            event, value = parse_perf_csv_line(line)
        else:
            event, value = parse_perf_space_line(line)

        if event in EVENTS and value is not None:
            totals[event] += value

    instructions = totals.get("instructions", 0.0)
    cycles = totals.get("cycles", 0.0)
    branches = totals.get("branches", 0.0)
    branch_misses = totals.get("branch-misses", 0.0)
    cache_refs = totals.get("cache-references", 0.0)
    cache_misses = totals.get("cache-misses", 0.0)

    result = dict(totals)
    result["ipc"] = instructions / cycles if cycles > 0 else ""
    result["branch_miss_rate"] = branch_misses / branches if branches > 0 else ""
    result["cache_miss_rate"] = cache_misses / cache_refs if cache_refs > 0 else ""

    return result

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("perf_log")
    ap.add_argument("--csv-out", required=True)
    args = ap.parse_args()

    result = parse_perf(Path(args.perf_log))

    with open(args.csv_out, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(result.keys()))
        w.writeheader()
        w.writerow(result)

if __name__ == "__main__":
    main()
