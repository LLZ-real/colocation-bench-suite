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

cleanup_all() {
  cleanup_sudo_keepalive
  cleanup_taobench
}

trap cleanup_all EXIT INT TERM

EXP_NAME="taobench_baseline_curve"
make_run_dir "${EXP_NAME}"

save_machine_topology "${RUN_DIR}/machine_topology"
write_config_snapshot "${RUN_DIR}/config.env"

# Keep sudo valid during long runs.
ENABLE_SUDO="${ENABLE_SUDO:-1}"
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

log "Applying network sysctl..."
if [ "${ENABLE_SUDO}" = "1" ]; then
  sudo -n sysctl -w net.ipv4.ip_local_port_range="1024 65535" || true
  sudo -n sysctl -w net.ipv4.tcp_tw_reuse=1 || true
  sudo -n sysctl -w net.ipv4.tcp_fin_timeout=15 || true
else
  log "Skipping network sysctl because ENABLE_SUDO=0"
fi

SERVER_LOG="/workspace/results/$(basename "${RUN_DIR}")/logs/server.log"
mkdir -p "${RUN_DIR}/logs"

TAO_SERVER_WARMUP_TIME="${TAO_SERVER_WARMUP_TIME:-2400}"
TAO_SERVER_TEST_TIME="${TAO_SERVER_TEST_TIME:-7200}"

log "Starting TaoBench server..."
bash "${CBS_ROOT}/online/taobench/start_server.sh" \
  "${SERVER_LOG}" \
  "${TAO_SERVER_WARMUP_TIME}" \
  "${TAO_SERVER_TEST_TIME}"

SERVER_BOOTSTRAP_WAIT="${SERVER_BOOTSTRAP_WAIT:-60}"
log "Waiting for server bootstrap: ${SERVER_BOOTSTRAP_WAIT}s"
sleep "${SERVER_BOOTSTRAP_WAIT}"

log "Checking TaoBench server process..."
docker exec "${SERVER_CONTAINER}" bash -c "
ps -eLo pid,tid,psr,pcpu,stat,comm,args | grep -E 'tao_bench_server|tao|benchpress' | grep -v grep || true
"

HOST_TAO_PID="$(
  docker top "${SERVER_CONTAINER}" -eo pid,args 2>/dev/null \
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

PREWARM_CLIENTS="${PREWARM_CLIENTS:-900}"
PREWARM_ROUNDS="${PREWARM_ROUNDS:-0}"
PREWARM_TEST_TIME="${PREWARM_TEST_TIME:-60}"
PREWARM_MIN_ROUNDS="${PREWARM_MIN_ROUNDS:-6}"
PREWARM_STOP_ON_STABLE="${PREWARM_STOP_ON_STABLE:-1}"
PREWARM_QPS_EPS="${PREWARM_QPS_EPS:-0.10}"
PREWARM_P99_EPS="${PREWARM_P99_EPS:-0.15}"

PREWARM_SUMMARY="${RUN_DIR}/prewarm.csv"
echo "round,clients_per_thread,qps,gets_p99_ms,log_file" > "${PREWARM_SUMMARY}"

prev_qps=""
prev_p99=""

if [ "${PREWARM_ROUNDS}" -gt 0 ]; then
  log "Starting prewarm: clients_per_thread=${PREWARM_CLIENTS}, max_rounds=${PREWARM_ROUNDS}, test_time=${PREWARM_TEST_TIME}"

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

    qps="$(python3 -c "import json; d=json.load(open('${PREWARM_JSON}')); print(d.get('qps') if d.get('qps') is not None else '')" 2>/dev/null || true)"
    p99="$(python3 -c "import json; d=json.load(open('${PREWARM_JSON}')); print(d.get('gets_p99_ms') if d.get('gets_p99_ms') is not None else '')" 2>/dev/null || true)"

    echo "${R},${PREWARM_CLIENTS},${qps},${p99},${PREWARM_LOG}" >> "${PREWARM_SUMMARY}"

    tail -20 "${PREWARM_LOG}" | grep -E 'Totals|Gets' || true

    if [ "${PREWARM_STOP_ON_STABLE}" = "1" ] && [ "${R}" -ge "${PREWARM_MIN_ROUNDS}" ]; then
      if [ -n "${prev_qps}" ] && [ -n "${prev_p99}" ] && [ -n "${qps}" ] && [ -n "${p99}" ]; then
        stable="$(
          python3 - <<PY
prev_qps=float("${prev_qps}")
prev_p99=float("${prev_p99}")
qps=float("${qps}")
p99=float("${p99}")
qps_eps=float("${PREWARM_QPS_EPS}")
p99_eps=float("${PREWARM_P99_EPS}")

qps_diff=abs(qps-prev_qps)/max(prev_qps, 1.0)
p99_diff=abs(p99-prev_p99)/max(prev_p99, 1.0)

print("1" if qps_diff <= qps_eps and p99_diff <= p99_eps else "0")
PY
        )"

        if [ "${stable}" = "1" ]; then
          log "Prewarm converged at round ${R}. qps=${qps}, p99=${p99}"
          break
        fi
      fi
    fi

    prev_qps="${qps}"
    prev_p99="${p99}"

    sleep 10
  done

  log "Prewarm finished. Summary: ${PREWARM_SUMMARY}"
fi

SUMMARY="${RUN_DIR}/summary.csv"
echo "run_index,clients_per_thread,qps,gets_p99_ms,ipc,cache_miss_rate,branch_miss_rate,context_switches,log_file,perf_log" > "${SUMMARY}"

CLIENT_LIST="${CLIENT_LIST:-900 900 900}"
CLIENT_TEST_TIME="${CLIENT_TEST_TIME:-60}"
ENABLE_PERF="${ENABLE_PERF:-1}"

RUN_INDEX=0

for CLIENTS in ${CLIENT_LIST}; do
  RUN_INDEX=$((RUN_INDEX + 1))
  TAG="idx${RUN_INDEX}_clients_${CLIENTS}"

  log "Testing clients_per_thread=${CLIENTS}"

  LOG_FILE="${RUN_DIR}/raw/client_${TAG}.log"
  JSON_FILE="${RUN_DIR}/parsed/client_${TAG}.json"
  PERF_LOG_HOST="${RUN_DIR}/raw/perf_${TAG}.log"
  PERF_PID_HOST="${RUN_DIR}/raw/perf_${TAG}.pid"
  PERF_CSV="${RUN_DIR}/parsed/perf_${TAG}.csv"

  if [ "${ENABLE_PERF}" = "1" ]; then
    bash "${CBS_ROOT}/collectors/start_host_perf_stat.sh" \
      "${SERVER_CONTAINER}" \
      "${TAO_SERVER_PID_PATTERN:-tao_bench_server}" \
      "${PERF_LOG_HOST}" \
      "${PERF_PID_HOST}" || true
  fi

  bash "${CBS_ROOT}/online/taobench/run_client.sh" \
    "${CLIENTS}" \
    "${CLIENT_TEST_TIME}" \
    "${LOG_FILE}" || true

  if [ "${ENABLE_PERF}" = "1" ]; then
    bash "${CBS_ROOT}/collectors/stop_host_perf_stat.sh" \
      "${PERF_PID_HOST}" || true
  fi

  python3 "${CBS_ROOT}/parsers/parse_taobench_client.py" "${LOG_FILE}" --json-out "${JSON_FILE}" || true

  QPS="$(python3 -c "import json; d=json.load(open('${JSON_FILE}')); print(d.get('qps') if d.get('qps') is not None else '')" 2>/dev/null || true)"
  P99="$(python3 -c "import json; d=json.load(open('${JSON_FILE}')); print(d.get('gets_p99_ms') if d.get('gets_p99_ms') is not None else '')" 2>/dev/null || true)"

  if [ "${ENABLE_PERF}" = "1" ] && [ -s "${PERF_LOG_HOST}" ]; then
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

  echo "${RUN_INDEX},${CLIENTS},${QPS},${P99},${IPC},${CACHE_MR},${BR_MR},${CTX},${LOG_FILE},${PERF_LOG_HOST}" >> "${SUMMARY}"

  log "Result: idx=${RUN_INDEX}, clients=${CLIENTS}, qps=${QPS}, gets_p99_ms=${P99}, ipc=${IPC}, cache_miss_rate=${CACHE_MR}"

  sleep 15
done

log "Baseline curve finished."
log "Prewarm summary: ${PREWARM_SUMMARY}"
log "Measurement summary: ${SUMMARY}"
