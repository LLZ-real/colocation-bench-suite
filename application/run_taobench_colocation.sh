#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/docker.sh"
source "${SCRIPT_DIR}/lib/resources.sh"

if [[ "${ACTION:-run}" == "topology" ]]; then
  python3 "${SCRIPT_DIR}/topology.py" --format "${TOPOLOGY_FORMAT:-text}"
  exit 0
fi

EXP_NAME="${EXP_NAME:-app_taobench_colocation}"
OFFLINE_TYPE="${OFFLINE_TYPE:-${OFFLINE_WORKLOAD:-none}}"
OFFLINE_PARAM="${OFFLINE_PARAM:-}"
OFFLINE_LABEL="${OFFLINE_LABEL:-}"
SPEC_CONFIG="${SPEC_CONFIG:-my_test.cfg}"
SPEC_SIZE="${SPEC_SIZE:-ref}"
SPEC_COPIES="${SPEC_COPIES:-1}"

CLIENTS_PER_THREAD="${CLIENTS_PER_THREAD:-900}"
CLIENT_WARMUP_TIME="${CLIENT_WARMUP_TIME:-120}"
CLIENT_TEST_TIME="${CLIENT_TEST_TIME:-60}"
SERVER_BOOTSTRAP_WAIT="${SERVER_BOOTSTRAP_WAIT:-180}"
OFFLINE_STABILIZE_WAIT="${OFFLINE_STABILIZE_WAIT:-20}"
TAO_SERVER_WARMUP_TIME="${TAO_SERVER_WARMUP_TIME:-2400}"
TAO_SERVER_TEST_TIME="${TAO_SERVER_TEST_TIME:-10800}"

SERVER_CONTAINER="${SERVER_CONTAINER:-clab-server}"
LOADGEN_CONTAINER="${LOADGEN_CONTAINER:-clab-loadgen}"
OFFLINE_CONTAINER="${OFFLINE_CONTAINER:-clab-offline}"

SERVER_CPUSET="${SERVER_CPUSET:-0,2,4,6,8,10,12,14}"
SERVER_MEMS="${SERVER_MEMS:-0}"
LOADGEN_CPUSET="${LOADGEN_CPUSET:-1,3,5,7,9,11,13,15,33,35,37,39,41,43,45,47}"
LOADGEN_MEMS="${LOADGEN_MEMS:-1}"
OFFLINE_CPUSET="${OFFLINE_CPUSET:-16,18,20,22,24,26,28,30}"
OFFLINE_MEMS="${OFFLINE_MEMS:-0}"

if [[ -z "${OFFLINE_LABEL}" ]]; then
  if [[ "${OFFLINE_TYPE}" == spec_* ]]; then
    OFFLINE_LABEL="${SPEC_SIZE}_c${SPEC_COPIES}"
  elif [[ -n "${OFFLINE_PARAM}" ]]; then
    OFFLINE_LABEL="w${OFFLINE_PARAM}"
  else
    OFFLINE_LABEL="none"
  fi
fi

SUDO_KEEPALIVE_PID=""
cleanup_sudo_keepalive() {
  if [[ -n "${SUDO_KEEPALIVE_PID}" ]]; then
    kill "${SUDO_KEEPALIVE_PID}" 2>/dev/null || true
  fi
}

on_exit() {
  local code=$?
  log "Exiting with code=${code}. Cleaning up..."
  cleanup_sudo_keepalive || true
  if [[ "${DRY_RUN}" = "1" ]]; then
    log "Dry-run mode, skipping container/process cleanup."
    exit "${code}"
  fi
  cleanup_offline || true
  cleanup_taobench || true
  exit "${code}"
}

trap on_exit EXIT INT TERM

start_sudo_keepalive() {
  if [[ "${ENABLE_SUDO:-1}" != "1" || "${DRY_RUN}" = "1" ]]; then
    return 0
  fi
  sudo -v
  (
    while true; do
      sudo -n true 2>/dev/null || exit
      sleep 60
    done
  ) &
  SUDO_KEEPALIVE_PID="$!"
}

write_summary_header() {
  cat > "${RUN_DIR}/summary.csv" <<'EOF'
timestamp,exp_name,offline_type,offline_param,offline_label,spec_size,spec_copies,clients_per_thread,client_warmup_time,client_test_time,server_cpuset,server_mems,loadgen_cpuset,loadgen_mems,offline_cpuset,offline_mems,qps,gets_p99_ms,client_log,client_json,offline_log,run_dir,notes
EOF
}

csv_append_summary() {
  python3 - "${RUN_DIR}/summary.csv" "$@" <<'PY'
import csv
import sys

path = sys.argv[1]
row = sys.argv[2:]
with open(path, "a", newline="") as f:
    csv.writer(f).writerow(row)
PY
}

parse_json_field() {
  local json_file="$1"
  local key="$2"
  python3 - "$json_file" "$key" <<'PY'
import json
import sys
try:
    d=json.load(open(sys.argv[1]))
    v=d.get(sys.argv[2], "")
    print("" if v is None else v)
except Exception:
    print("")
PY
}

start_offline_workload() {
  local log_path="$1"
  case "${OFFLINE_TYPE}" in
    none)
      log "No offline workload."
      ;;
    ibench_cpu)
      app_run bash "${CBS_ROOT}/offline/ibench/start_cpu.sh" "${OFFLINE_PARAM:-8}" "${log_path}"
      ;;
    ibench_membw)
      app_run bash "${CBS_ROOT}/offline/ibench/start_membw.sh" "${OFFLINE_PARAM:-8}" "${log_path}"
      ;;
    ibench_l3)
      app_run bash "${CBS_ROOT}/offline/ibench/start_l3.sh" "${OFFLINE_PARAM:-8}" "${log_path}"
      ;;
    ibench_memcap)
      app_run bash "${CBS_ROOT}/offline/ibench/start_memcap.sh" "${OFFLINE_PARAM:-15}" "${log_path}"
      ;;
    spec_mcf)
      app_run env SPEC_COPIES="${SPEC_COPIES}" bash "${CBS_ROOT}/offline/spec/start_runcpu.sh" "505.mcf_r" "${log_path}" "${SPEC_SIZE}" "${SPEC_CONFIG}"
      ;;
    spec_lbm)
      app_run env SPEC_COPIES="${SPEC_COPIES}" bash "${CBS_ROOT}/offline/spec/start_runcpu.sh" "519.lbm_r" "${log_path}" "${SPEC_SIZE}" "${SPEC_CONFIG}"
      ;;
    *)
      die "Unknown OFFLINE_TYPE=${OFFLINE_TYPE}"
      ;;
  esac
}

make_app_run_dir "${EXP_NAME}_${OFFLINE_TYPE}_${OFFLINE_LABEL}"
save_app_topology "${RUN_DIR}/machine_topology"
write_app_env_snapshot "${RUN_DIR}/config.env"
write_summary_header

log "Action=${ACTION}, dry_run=${DRY_RUN}"
log "Placement: server=${SERVER_CPUSET}/mems${SERVER_MEMS}, loadgen=${LOADGEN_CPUSET}/mems${LOADGEN_MEMS}, offline=${OFFLINE_CPUSET}/mems${OFFLINE_MEMS}"
python3 "${SCRIPT_DIR}/topology.py" --format text > "${RUN_DIR}/machine_topology/topology.txt" || true

start_sudo_keepalive
apply_resource_hooks_before_run

taobench_volumes=("${RESULTS_ROOT}:/workspace/results")
if [[ "${DCPERF_MOUNT:-1}" == "1" ]]; then
  taobench_volumes=("${DCPERF_DIR}:/workspace/DCPerf" "${taobench_volumes[@]}")
  log "Using host-mounted DCPerf: ${DCPERF_DIR} -> /workspace/DCPerf"
else
  log "Using image-baked DCPerf at /workspace/DCPerf"
fi

create_app_container server "${SERVER_CONTAINER}" "${SERVER_CPUSET}" "${SERVER_MEMS}" \
  "${taobench_volumes[@]}"
create_app_container loadgen "${LOADGEN_CONTAINER}" "${LOADGEN_CPUSET}" "${LOADGEN_MEMS}" \
  "${taobench_volumes[@]}"
create_app_container offline "${OFFLINE_CONTAINER}" "${OFFLINE_CPUSET}" "${OFFLINE_MEMS}" \
  "${IBENCH_DIR}:/workspace/iBench" \
  "${SPEC_DIR}:/workspace/cpu2017" \
  "${RESULTS_ROOT}:/workspace/results"

inspect_app_container "${SERVER_CONTAINER}" "${RUN_DIR}/machine_topology/server_container.inspect.json"
inspect_app_container "${LOADGEN_CONTAINER}" "${RUN_DIR}/machine_topology/loadgen_container.inspect.json"
inspect_app_container "${OFFLINE_CONTAINER}" "${RUN_DIR}/machine_topology/offline_container.inspect.json"

apply_resource_hooks_after_containers

SERVER_LOG="/workspace/results/$(basename "${RUN_DIR}")/logs/server.log"
OFFLINE_LOG="/workspace/results/$(basename "${RUN_DIR}")/logs/offline_${OFFLINE_TYPE}_${OFFLINE_LABEL}.log"
CLIENT_LOG="${RUN_DIR}/raw/client_${OFFLINE_TYPE}_${OFFLINE_LABEL}.log"
CLIENT_JSON="${RUN_DIR}/parsed/client_${OFFLINE_TYPE}_${OFFLINE_LABEL}.json"

app_run bash "${CBS_ROOT}/online/taobench/start_server.sh" "${SERVER_LOG}" "${TAO_SERVER_WARMUP_TIME}" "${TAO_SERVER_TEST_TIME}"
if [[ "${DRY_RUN}" != "1" ]]; then
  log "Waiting for TaoBench server bootstrap: ${SERVER_BOOTSTRAP_WAIT}s"
  sleep "${SERVER_BOOTSTRAP_WAIT}"
fi

start_offline_workload "${OFFLINE_LOG}"
if [[ "${OFFLINE_TYPE}" != "none" && "${DRY_RUN}" != "1" ]]; then
  log "Waiting for offline workload to stabilize: ${OFFLINE_STABILIZE_WAIT}s"
  sleep "${OFFLINE_STABILIZE_WAIT}"
fi

app_run env CLIENT_WARMUP_TIME="${CLIENT_WARMUP_TIME}" bash "${CBS_ROOT}/online/taobench/run_client.sh" "${CLIENTS_PER_THREAD}" "${CLIENT_TEST_TIME}" "${CLIENT_LOG}"

if [[ "${DRY_RUN}" != "1" ]]; then
  python3 "${CBS_ROOT}/parsers/parse_taobench_client.py" "${CLIENT_LOG}" --json-out "${CLIENT_JSON}" || true
  QPS="$(parse_json_field "${CLIENT_JSON}" qps)"
  P99="$(parse_json_field "${CLIENT_JSON}" gets_p99_ms)"
  NOTES="$(parse_json_field "${CLIENT_JSON}" diagnostic_status)"
else
  QPS=""
  P99=""
  NOTES="dry-run"
fi

csv_append_summary \
  "$(date -Iseconds)" \
  "${EXP_NAME}" \
  "${OFFLINE_TYPE}" \
  "${OFFLINE_PARAM}" \
  "${OFFLINE_LABEL}" \
  "${SPEC_SIZE}" \
  "${SPEC_COPIES}" \
  "${CLIENTS_PER_THREAD}" \
  "${CLIENT_WARMUP_TIME}" \
  "${CLIENT_TEST_TIME}" \
  "${SERVER_CPUSET}" \
  "${SERVER_MEMS}" \
  "${LOADGEN_CPUSET}" \
  "${LOADGEN_MEMS}" \
  "${OFFLINE_CPUSET}" \
  "${OFFLINE_MEMS}" \
  "${QPS}" \
  "${P99}" \
  "${CLIENT_LOG}" \
  "${CLIENT_JSON}" \
  "${OFFLINE_LOG}" \
  "${RUN_DIR}" \
  "${NOTES}"

log "Measured result: qps=${QPS}, p99=${P99}, notes=${NOTES}"
log "Summary: ${RUN_DIR}/summary.csv"
