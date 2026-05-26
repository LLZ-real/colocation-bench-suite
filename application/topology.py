#!/usr/bin/env python3
import argparse
import json
import subprocess
from collections import defaultdict
from pathlib import Path


def run(cmd):
    try:
        return subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL)
    except Exception:
        return ""


def parse_lscpu_e():
    text = run(["lscpu", "-e=CPU,CORE,SOCKET,NODE,ONLINE,CACHE"])
    if not text:
        text = run(["lscpu", "-e=CPU,CORE,SOCKET,NODE,ONLINE"])
    rows = []
    lines = [ln for ln in text.splitlines() if ln.strip()]
    if not lines:
        return rows
    header = lines[0].split()
    for line in lines[1:]:
        parts = line.split()
        if len(parts) < len(header):
            continue
        row = dict(zip(header, parts))
        rows.append(row)
    return rows


def parse_cache_summary():
    out = {}
    for idx in Path("/sys/devices/system/cpu/cpu0/cache").glob("index*"):
        try:
            level = (idx / "level").read_text().strip()
            ctype = (idx / "type").read_text().strip()
            size = (idx / "size").read_text().strip()
            shared = (idx / "shared_cpu_list").read_text().strip()
            out[f"L{level}_{ctype}"] = {"size": size, "shared_cpu_list": shared}
        except Exception:
            pass
    return out


def topology():
    rows = parse_lscpu_e()
    by_node = defaultdict(list)
    by_socket = defaultdict(list)
    by_core = defaultdict(list)
    for r in rows:
        cpu = int(r["CPU"])
        node = r.get("NODE", "?")
        socket = r.get("SOCKET", "?")
        core = r.get("CORE", "?")
        by_node[node].append(cpu)
        by_socket[socket].append(cpu)
        by_core[(socket, core)].append(cpu)

    smt_pairs = []
    for key, cpus in sorted(by_core.items()):
        if len(cpus) >= 2:
            smt_pairs.append({"socket": key[0], "core": key[1], "cpus": sorted(cpus)})

    return {
        "cpus": rows,
        "nodes": {k: sorted(v) for k, v in sorted(by_node.items())},
        "sockets": {k: sorted(v) for k, v in sorted(by_socket.items())},
        "smt_groups": smt_pairs,
        "cache": parse_cache_summary(),
    }


def fmt_list(values):
    return ",".join(str(v) for v in values)


def print_text(topo):
    print("NUMA nodes:")
    for node, cpus in topo["nodes"].items():
        print(f"  node {node}: {fmt_list(cpus)}")
    print()
    print("Sockets:")
    for socket, cpus in topo["sockets"].items():
        print(f"  socket {socket}: {fmt_list(cpus)}")
    print()
    print("SMT groups:")
    for g in topo["smt_groups"][:64]:
        print(f"  socket {g['socket']} core {g['core']}: {fmt_list(g['cpus'])}")
    print()
    print("CPU0 cache:")
    for name, c in topo["cache"].items():
        print(f"  {name}: size={c['size']} shared={c['shared_cpu_list']}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--format", choices=["json", "text"], default="text")
    args = ap.parse_args()
    topo = topology()
    if args.format == "json":
        print(json.dumps(topo, indent=2))
    else:
        print_text(topo)


if __name__ == "__main__":
    main()

