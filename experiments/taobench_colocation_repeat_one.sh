#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/../conf/env.sh"
source "$(dirname "$0")/../scripts/common.sh"
source "$(dirname "$0")/../scripts/cleanup.sh"

SUDO_KEEPALIVE_PID=""

cleanup_sudo_keepalive() {
  if [ -n "${SUDO_KEEPALIVE_PID}" ]; then
    kill "${SUDO_KEEPALIVE_PID}" 2>/dev/null || true
  fi
}

csv_append_row() {
  python3 - "$SUMMARY" "$@" <<'PY'
import csv
import sys

path = sys.argv[1]
row = sys.argv[2:]

with open(path, "a", newline="") as f:
    csv.writer(f).writerow(row)
PY
}

cleanup_all() {
  cleanup_sudo_keepalive
  cleanup_offline
  cleanup_taobench
}

trap cleanup_all EXIT INT TERM

EXP_NAME="${EXP_NAME:-taobench_colocation_repeat_one}"

OFFLINE_TYPE="${OFFLINE_TYPE:-none}"
OFFLINE_PARAM="${OFFLINE_PARAM:-}"
OFFLINE_LABEL="${OFFLINE_LABEL:-}"

SPEC_CONFIG="${SPEC_CONFIG:-my_test.cfg}"
SPEC_SIZE="${SPEC_SIZE:-test}"
SPEC_COPIES="${SPEC_COPIES:-1}"

CLIENTS="${CLIENTS_PER_THREAD:-900}"
CLIENT_TEST_TIME="${CLIENT_TEST_TIME:-300}"
CLIENT_WARMUP_TIME="${CLIENT_WARMUP_TIME:-120}"

PREWARM_CLIENTS="${PREWARM_CLIENTS:-900}"
PREWARM_ROUNDS="${PREWARM_ROUNDS:-8}"
PREWARM_TEST_TIME="${PREWARM_TEST_TIME:-60}"

MEASURE_REPEATS="${MEASURE_REPEATS:-3}"
MEASURE_GAP="${MEASURE_GAP:-30}"

SERVER_BOOTSTRAP_WAIT="${SERVER_BOOTSTRAP_WAIT:-180}"
OFFLINE_STABILIZE_WAIT="${OFFLINE_STABILIZE_WAIT:-30}"

TAO_SERVER_WARMUP_TIME="${TAO_SERVER_WARMUP_TIME:-2400}"
TAO_SERVER_TEST_TIME="${TAO_SERVER_TEST_TIME:-7200}"

ENABLE_SUDO="${ENABLE_SUDO:-1}"

if [[ -z "${OFFLINE_LABEL}" ]]; then
  if [[ "${OFFLINE_TYPE}" == spec_* ]]; then
    OFFLINE_LABEL="${SPEC_SIZE}_c${SPEC_COPIES}"
  elif [[ -n "${OFFLINE_PARAM}" ]]; then
    OFFLINE_LABEL="w${OFFLINE_PARAM}"
  else
    OFFLINE_LABEL="none"
  fi
fi

make_run_dir "${EXP_NAME}_${OFFLINE_TYPE}_${OFFLINE_LABEL}"

mkdir -p "${RUN_DIR}/logs" "${RUN_DIR}/raw" "${RUN_DIR}/parsed" "${RUN_DIR}/machine_topology"

save_machine_topology "${RUN_DIR}/machine_topology" || true
write_config_snapshot "${RUN_DIR}/config.env" || true

{
  echo "timestamp=$(date -Iseconds)"
  echo "hostname=$(hostname)"
  echo "EXP_NAME=${EXP_NAME}"
  echo "OFFLINE_TYPE=${OFFLINE_TYPE}"
  echo "OFFLINE_PARAM=${OFFLINE_PARAM}"
  echo "OFFLINE_LABEL=${OFFLINE_LABEL}"
  echo "SPEC_CONFIG=${SPEC_CONFIG}"
  echo "SPEC_SIZE=${SPEC_SIZE}"
  echo "SPEC_COPIES=${SPEC_COPIES}"
  echo "CLIENTS_PER_THREAD=${CLIENTS}"
  echo "CLIENT_TEST_TIME=${CLIENT_TEST_TIME}"
  echo "CLIENT_WARMUP_TIME=${CLIENT_WARMUP_TIME}"
  echo "PREWARM_CLIENTS=${PREWARM_CLIENTS}"
  echo "PREWARM_ROUNDS=${PREWARM_ROUNDS}"
  echo "PREWARM_TEST_TIME=${PREWARM_TEST_TIME}"
  echo "MEASURE_REPEATS=${MEASURE_REPEATS}"
  echo "MEASURE_GAP=${MEASURE_GAP}"
  echo "SERVER_CPUSET=${SERVER_CPUSET}"
  echo "SERVER_MEMS=${SERVER_MEMS}"
  echo "LOADGEN_CPUSET=${LOADGEN_CPUSET}"
  echo "LOADGEN_MEMS=${LOADGEN_MEMS}"
  echo "OFFLINE_CPUSET=${OFFLINE_CPUSET}"
  echo "OFFLINE_MEMS=${OFFLINE_MEMS}"
  echo "TAO_MEMSIZE=${TAO_MEMSIZE}"
  echo "TAO_SERVER_PORT=${TAO_SERVER_PORT}"
  echo "TAO_INTERFACE_NAME=${TAO_INTERFACE_NAME}"
} > "${RUN_DIR}/experiment_meta.env"

if [ "${ENABLE_SUDO}" = "1" ]; then
  sudo -v
  (
    while true; do
      sudo -n true 2>/dev/null || exit
      sleep 60
    done
  ) &
  SUDO_KEEPALIVE_PID=$!
fi

log "Creating containers..."
bash "${CBS_ROOT}/containers/create_taobench_server.sh"
bash "${CBS_ROOT}/containers/create_taobench_loadgen.sh"
bash "${CBS_ROOT}/containers/create_offline.sh"

log "Saving docker inspect..."
docker inspect "${SERVER_CONTAINER}" > "${RUN_DIR}/machine_topology/server_container.inspect.json" 2>/dev/null || true
docker inspect "${LOADGEN_CONTAINER}" > "${RUN_DIR}/machine_topology/loadgen_container.inspect.json" 2>/dev/null || true
docker inspect "${OFFLINE_CONTAINER}" > "${RUN_DIR}/machine_topology/offline_container.inspect.json" 2>/dev/null || true

log "Applying network sysctl..."
if [ "${ENABLE_SUDO}" = "1" ]; then
  sudo -n sysctl -w net.ipv4.ip_local_port_range="1024 65535" || true
  sudo -n sysctl -w net.ipv4.tcp_tw_reuse=1 || true
  sudo -n sysctl -w net.ipv4.tcp_fin_timeout=15 || true
else
  log "Skipping network sysctl because ENABLE_SUDO=0"
fi

SERVER_LOG="/workspace/results/$(basename "${RUN_DIR}")/logs/server.log"

log "Starting TaoBench server..."
bash "${CBS_ROOT}/online/taobench/start_server.sh" \
  "${SERVER_LOG}" \
  "${TAO_SERVER_WARMUP_TIME}" \
  "${TAO_SERVER_TEST_TIME}"

log "Waiting for server bootstrap: ${SERVER_BOOTSTRAP_WAIT}s"
sleep "${SERVER_BOOTSTRAP_WAIT}"

log "Prewarming TaoBench..."
PREWARM_SUMMARY="${RUN_DIR}/prewarm.csv"
echo "round,clients_per_thread,qps,gets_p99_ms,log_file,json_file" > "${PREWARM_SUMMARY}"

for R in $(seq 1 "${PREWARM_ROUNDS}"); do
  PREWARM_LOG="${RUN_DIR}/raw/prewarm_${R}_clients_${PREWARM_CLIENTS}.log"
  PREWARM_JSON="${RUN_DIR}/parsed/prewarm_${R}_clients_${PREWARM_CLIENTS}.json"

  log "Prewarm round ${R}/${PREWARM_ROUNDS}"

  bash "${CBS_ROOT}/online/taobench/run_client.sh" \
    "${PREWARM_CLIENTS}" \
    "${PREWARM_TEST_TIME}" \
    "${PREWARM_LOG}" || true

  python3 "${CBS_ROOT}/parsers/parse_taobench_client.py" \
    "${PREWARM_LOG}" \
    --json-out "${PREWARM_JSON}" || true

  qps="$(
    python3 -c "import json; d=json.load(open('${PREWARM_JSON}')); print(d.get('qps') if d.get('qps') is not None else '')" \
      2>/dev/null || true
  )"

  p99="$(
    python3 -c "import json; d=json.load(open('${PREWARM_JSON}')); print(d.get('gets_p99_ms') if d.get('gets_p99_ms') is not None else '')" \
      2>/dev/null || true
  )"

  echo "${R},${PREWARM_CLIENTS},${qps},${p99},${PREWARM_LOG},${PREWARM_JSON}" >> "${PREWARM_SUMMARY}"

  tail -20 "${PREWARM_LOG}" | grep -E 'Totals|Gets' || true
  sleep 10
done

log "Starting offline workload: type=${OFFLINE_TYPE}, param=${OFFLINE_PARAM}, label=${OFFLINE_LABEL}"

OFFLINE_LOG="/workspace/results/$(basename "${RUN_DIR}")/logs/offline_${OFFLINE_TYPE}_${OFFLINE_LABEL}.log"

case "${OFFLINE_TYPE}" in
  none)
    log "No offline workload."
    ;;
  ibench_cpu)
    bash "${CBS_ROOT}/offline/ibench/start_cpu.sh" \
      "${OFFLINE_PARAM:-8}" \
      "${OFFLINE_LOG}"
    ;;
  ibench_memcap)
    echo "[ERROR] ibench_memcap is not recommended for formal Stage 1 because it may cause OOM-like behavior." >&2
    exit 2
    ;;
  ibench_membw)
    bash "${CBS_ROOT}/offline/ibench/start_membw.sh" \
      "${OFFLINE_PARAM:-8}" \
      "${OFFLINE_LOG}"
    ;;
  ibench_l3)
    bash "${CBS_ROOT}/offline/ibench/start_l3.sh" \
      "${OFFLINE_PARAM:-8}" \
      "${OFFLINE_LOG}"
    ;;
  spec_mcf)
    bash "${CBS_ROOT}/offline/spec/start_runcpu.sh" \
      "505.mcf_r" \
      "${OFFLINE_LOG}" \
      "${SPEC_SIZE}" \
      "${SPEC_CONFIG}"
    ;;
  spec_lbm)
    bash "${CBS_ROOT}/offline/spec/start_runcpu.sh" \
      "519.lbm_r" \
      "${OFFLINE_LOG}" \
      "${SPEC_SIZE}" \
      "${SPEC_CONFIG}"
    ;;
  *)
    die "Unknown OFFLINE_TYPE=${OFFLINE_TYPE}"
    ;;
esac

log "Waiting for offline workload to stabilize: ${OFFLINE_STABILIZE_WAIT}s"
sleep "${OFFLINE_STABILIZE_WAIT}"

SUMMARY="${RUN_DIR}/summary.csv"

cat > "${SUMMARY}" <<'EOF'
timestamp,exp_name,repeat_id,offline_type,offline_param,offline_label,spec_size,spec_copies,clients_per_thread,client_test_time,client_warmup_time,prewarm_rounds,prewarm_clients,prewarm_test_time,server_cpuset,server_mems,loadgen_cpuset,loadgen_mems,offline_cpuset,offline_mems,qps,gets_p99_ms,client_log,client_json,offline_log,run_dir,notes
EOF

for I in $(seq 1 "${MEASURE_REPEATS}"); do
  LOG_FILE="${RUN_DIR}/raw/client_measured_repeat_${I}_clients_${CLIENTS}.log"
  JSON_FILE="${RUN_DIR}/parsed/client_measured_repeat_${I}_clients_${CLIENTS}.json"

  log "Measured TaoBench run ${I}/${MEASURE_REPEATS}"

  bash "${CBS_ROOT}/online/taobench/run_client.sh" \
    "${CLIENTS}" \
    "${CLIENT_TEST_TIME}" \
    "${LOG_FILE}" || true

  python3 "${CBS_ROOT}/parsers/parse_taobench_client.py" \
    "${LOG_FILE}" \
    --json-out "${JSON_FILE}" || true

  QPS="$(
    python3 -c "import json; d=json.load(open('${JSON_FILE}')); print(d.get('qps') if d.get('qps') is not None else '')" \
      2>/dev/null || true
  )"

  P99="$(
    python3 -c "import json; d=json.load(open('${JSON_FILE}')); print(d.get('gets_p99_ms') if d.get('gets_p99_ms') is not None else '')" \
      2>/dev/null || true
  )"

  NOTES=""

  csv_append_row \
    "$(date -Iseconds)" \
    "${EXP_NAME}" \
    "${I}" \
    "${OFFLINE_TYPE}" \
    "${OFFLINE_PARAM}" \
    "${OFFLINE_LABEL}" \
    "${SPEC_SIZE}" \
    "${SPEC_COPIES}" \
    "${CLIENTS}" \
    "${CLIENT_TEST_TIME}" \
    "${CLIENT_WARMUP_TIME}" \
    "${PREWARM_ROUNDS}" \
    "${PREWARM_CLIENTS}" \
    "${PREWARM_TEST_TIME}" \
    "${SERVER_CPUSET}" \
    "${SERVER_MEMS}" \
    "${LOADGEN_CPUSET}" \
    "${LOADGEN_MEMS}" \
    "${OFFLINE_CPUSET}" \
    "${OFFLINE_MEMS}" \
    "${QPS}" \
    "${P99}" \
    "${LOG_FILE}" \
    "${JSON_FILE}" \
    "${OFFLINE_LOG}" \
    "${RUN_DIR}" \
    "${NOTES}"

  log "Repeat ${I}: qps=${QPS}, p99=${P99}"

  if [ "${I}" != "${MEASURE_REPEATS}" ]; then
    log "Sleeping MEASURE_GAP=${MEASURE_GAP}s"
    sleep "${MEASURE_GAP}"
  fi
done

log "Summary: ${SUMMARY}"
