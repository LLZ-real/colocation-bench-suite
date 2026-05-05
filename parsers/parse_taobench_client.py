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
    }

    for line in text.splitlines():
        parts = line.split()
        if not parts:
            continue

        if parts[0] == "Totals":
            result["raw_totals_line"] = line
            if len(parts) >= 2:
                try:
                    result["qps"] = float(parts[1])
                except ValueError:
                    pass

        if parts[0] == "Gets":
            result["raw_gets_line"] = line
            if len(parts) >= 7:
                try:
                    result["gets_p99_ms"] = float(parts[6])
                except ValueError:
                    pass

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
