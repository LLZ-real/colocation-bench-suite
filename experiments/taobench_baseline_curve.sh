#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/../conf/env.sh"
source "$(dirname "$0")/../scripts/common.sh"
source "$(dirname "$0")/../scripts/cleanup.sh"

trap cleanup_taobench EXIT INT TERM

EXP_NAME="taobench_baseline_curve"
make_run_dir "${EXP_NAME}"

save_machine_topology "${RUN_DIR}/machine_topology"
write_config_snapshot "${RUN_DIR}/config.env"

# Avoid sudo password prompt in the middle of the experiment.
sudo -v

log "Creating containers..."
bash "${CBS_ROOT}/containers/create_taobench_server.sh"
bash "${CBS_ROOT}/containers/create_taobench_loadgen.sh"

log "Applying network sysctl..."
sudo sysctl -w net.ipv4.ip_local_port_range="1024 65535" || true
sudo sysctl -w net.ipv4.tcp_tw_reuse=1 || true
sudo sysctl -w net.ipv4.tcp_fin_timeout=15 || true

log "Starting TaoBench server..."
SERVER_LOG="/workspace/results/$(basename "${RUN_DIR}")/logs/server.log"
mkdir -p "${RUN_DIR}/logs"
bash "${CBS_ROOT}/online/taobench/start_server.sh" "${SERVER_LOG}" 120 7200

log "Waiting for server warmup bootstrap..."
sleep 180

log "Checking TaoBench server process..."
docker exec "${SERVER_CONTAINER}" bash -c "
ps -eLo pid,tid,psr,pcpu,stat,comm,args | grep -E 'tao_bench_server|tao|benchpress' | grep -v grep || true
"

HOST_TAO_PID="$(
  ps -e -o pid,args \
    | grep "${TAO_SERVER_PID_PATTERN:-tao_bench_server}" \
    | grep -v grep \
    | awk '{print $1}' \
    | head -n 1 || true
)"

if [ -z "${HOST_TAO_PID}" ]; then
  log "ERROR: Cannot find TaoBench server host PID."
  log "Server log tail:"
  docker exec "${SERVER_CONTAINER}" bash -c "tail -120 ${SERVER_LOG}" || true
  exit 1
fi

log "TaoBench server host PID=${HOST_TAO_PID}"

SUMMARY="${RUN_DIR}/summary.csv"
echo "clients_per_thread,qps,gets_p99_ms,ipc,cache_miss_rate,branch_miss_rate,context_switches,log_file,perf_log" > "${SUMMARY}"

CLIENT_LIST="${CLIENT_LIST:-100 200 300 380 500 600 700 800 900 1000 1200 1400}"
CLIENT_TEST_TIME="${CLIENT_TEST_TIME:-60}"

for CLIENTS in ${CLIENT_LIST}; do
  log "Testing clients_per_thread=${CLIENTS}"

  LOG_FILE="${RUN_DIR}/raw/client_${CLIENTS}.log"
  JSON_FILE="${RUN_DIR}/parsed/client_${CLIENTS}.json"
  PERF_LOG_HOST="${RUN_DIR}/raw/perf_client_${CLIENTS}.log"
  PERF_PID_HOST="${RUN_DIR}/raw/perf_client_${CLIENTS}.pid"
  PERF_CSV="${RUN_DIR}/parsed/perf_client_${CLIENTS}.csv"

  # Start host-side perf collection for TaoBench server.
  bash "${CBS_ROOT}/collectors/start_host_perf_stat.sh" \
    "${SERVER_CONTAINER}" \
    "${TAO_SERVER_PID_PATTERN:-tao_bench_server}" \
    "${PERF_LOG_HOST}" \
    "${PERF_PID_HOST}" || true

  # Run client benchmark.
  bash "${CBS_ROOT}/online/taobench/run_client.sh" \
    "${CLIENTS}" \
    "${CLIENT_TEST_TIME}" \
    "${LOG_FILE}" || true

  # Stop host-side perf.
  bash "${CBS_ROOT}/collectors/stop_host_perf_stat.sh" \
    "${PERF_PID_HOST}" || true

  # Parse TaoBench client output.
  python3 "${CBS_ROOT}/parsers/parse_taobench_client.py" "${LOG_FILE}" --json-out "${JSON_FILE}" || true

  QPS="$(python3 -c "import json; d=json.load(open('${JSON_FILE}')); print(d.get('qps') if d.get('qps') is not None else '')" 2>/dev/null || true)"
  P99="$(python3 -c "import json; d=json.load(open('${JSON_FILE}')); print(d.get('gets_p99_ms') if d.get('gets_p99_ms') is not None else '')" 2>/dev/null || true)"

  # Parse perf output.
  if [ -s "${PERF_LOG_HOST}" ]; then
    python3 "${CBS_ROOT}/parsers/parse_perf_stat.py" "${PERF_LOG_HOST}" --csv-out "${PERF_CSV}" || true

    IPC="$(python3 -c "import csv; p='${PERF_CSV}'; rows=list(csv.DictReader(open(p))); print(rows[0].get('ipc','') if rows else '')" 2>/dev/null || true)"
    CACHE_MR="$(python3 -c "import csv; p='${PERF_CSV}'; rows=list(csv.DictReader(open(p))); print(rows[0].get('cache_miss_rate','') if rows else '')" 2>/dev/null || true)"
    BR_MR="$(python3 -c "import csv; p='${PERF_CSV}'; rows=list(csv.DictReader(open(p))); print(rows[0].get('branch_miss_rate','') if rows else '')" 2>/dev/null || true)"
    CTX="$(python3 -c "import csv; p='${PERF_CSV}'; rows=list(csv.DictReader(open(p))); print(rows[0].get('context-switches','') if rows else '')" 2>/dev/null || true)"
  else
    IPC=""
    CACHE_MR=""
    BR_MR=""
    CTX=""
  fi

  echo "${CLIENTS},${QPS},${P99},${IPC},${CACHE_MR},${BR_MR},${CTX},${LOG_FILE},${PERF_LOG_HOST}" >> "${SUMMARY}"

  log "Result: clients=${CLIENTS}, qps=${QPS}, gets_p99_ms=${P99}, ipc=${IPC}, cache_miss_rate=${CACHE_MR}"

  if [ -n "${P99}" ]; then
    EXCEEDED="$(echo "${P99} > 500" | bc -l || echo 0)"
    if [ "${EXCEEDED}" = "1" ]; then
      log "P99 exceeded 500ms. Stop curve scan."
      break
    fi
  fi

  sleep 15
done

log "Baseline curve finished."
log "Summary: ${SUMMARY}"
