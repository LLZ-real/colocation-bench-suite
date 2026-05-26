#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CBS_ROOT="$(cd "${APP_DIR}/.." && pwd)"

source "${CBS_ROOT}/conf/env.sh"
source "${CBS_ROOT}/scripts/common.sh"
source "${CBS_ROOT}/scripts/cleanup.sh"

ACTION="${ACTION:-run}"
DRY_RUN=0
if [[ "${ACTION}" == "dry-run" || "${ACTION}" == "plan" ]]; then
  DRY_RUN=1
fi

app_run() {
  if [[ "${DRY_RUN}" = "1" ]]; then
    printf '[DRY-RUN] '
    printf '%q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}

app_run_shell() {
  local cmd="$1"
  if [[ "${DRY_RUN}" = "1" ]]; then
    printf '[DRY-RUN] %s\n' "${cmd}"
  else
    bash -lc "${cmd}"
  fi
}

require_var() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    die "Missing required variable: ${name}"
  fi
}

timestamp() {
  date '+%Y%m%d_%H%M%S'
}

make_app_run_dir() {
  local exp_name="$1"
  local ts
  ts="$(timestamp)"
  export RUN_DIR="${RESULTS_ROOT}/${ts}_${exp_name}"
  mkdir -p "${RUN_DIR}/logs" "${RUN_DIR}/raw" "${RUN_DIR}/parsed" "${RUN_DIR}/machine_topology"
  log "RUN_DIR=${RUN_DIR}"
}

save_app_topology() {
  local out_dir="$1"
  mkdir -p "${out_dir}"
  lscpu > "${out_dir}/lscpu.txt" 2>&1 || true
  lscpu -e=CPU,CORE,SOCKET,NODE,ONLINE > "${out_dir}/lscpu_e.txt" 2>&1 || true
  numactl -H > "${out_dir}/numactl_H.txt" 2>&1 || true
  python3 "${APP_DIR}/topology.py" --format json > "${out_dir}/topology.json" 2>&1 || true
}

write_app_env_snapshot() {
  local out_file="$1"
  env | sort > "${out_file}"
}
