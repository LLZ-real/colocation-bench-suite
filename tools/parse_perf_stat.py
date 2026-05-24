#!/usr/bin/env python3
import csv
import sys
from pathlib import Path

def parse_value(x):
    x = x.strip()
    if not x or x.startswith("<"):
        return ""
    x = x.replace(",", "")
    try:
        return float(x)
    except Exception:
        return ""

def parse_perf_csv(path: Path):
    rows = []
    for line in path.read_text(errors="ignore").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue

        parts = line.split(",")
        if len(parts) < 3:
            continue

        value = parse_value(parts[0])
        unit = parts[1].strip()
        event = parts[2].strip()

        if not event:
            continue

        rows.append({
            "event": event,
            "value": value,
            "unit": unit,
            "raw": line,
        })
    return rows

def main():
    if len(sys.argv) < 2:
        print("Usage: parse_perf_stat.py perf_stat.csv [out.csv]", file=sys.stderr)
        sys.exit(1)

    inp = Path(sys.argv[1])
    out = Path(sys.argv[2]) if len(sys.argv) >= 3 else inp.with_suffix(".parsed.csv")

    rows = parse_perf_csv(inp)

    fields = ["event", "value", "unit", "raw"]
    with out.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)

    print(f"[OK] wrote {out}")
    for r in rows:
        print(f"{r['event']},{r['value']},{r['unit']}")

if __name__ == "__main__":
    main()
