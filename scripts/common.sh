#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[$(date '+%F %T')] $*"
}

die() {
  echo "[ERROR] $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"
}

ensure_dir() {
  mkdir -p "$1"
}

timestamp() {
  date '+%Y%m%d_%H%M%S'
}

make_run_dir() {
  local exp_name="$1"
  local ts
  ts="$(timestamp)"
  export RUN_DIR="${RESULTS_ROOT}/${ts}_${exp_name}"

  mkdir -p "${RUN_DIR}/logs"
  mkdir -p "${RUN_DIR}/raw"
  mkdir -p "${RUN_DIR}/parsed"
  mkdir -p "${RUN_DIR}/machine_topology"

  log "RUN_DIR=${RUN_DIR}"
}

save_machine_topology() {
  local out_dir="$1"
  mkdir -p "$out_dir"

  lscpu > "${out_dir}/lscpu.txt" || true
  lscpu -e=CPU,CORE,SOCKET,NODE,ONLINE,MAXMHZ,MINMHZ > "${out_dir}/lscpu_e.txt" || true
  numactl -H > "${out_dir}/numactl_H.txt" 2>/dev/null || true
  free -h > "${out_dir}/free_h.txt" || true
  uname -a > "${out_dir}/uname_a.txt" || true
  docker version > "${out_dir}/docker_version.txt" 2>&1 || true
  cat /sys/devices/system/cpu/cpu*/topology/thread_siblings_list 2>/dev/null | sort -u > "${out_dir}/thread_siblings.txt" || true
}

write_config_snapshot() {
  local out_file="$1"
  env | sort > "$out_file"
}
