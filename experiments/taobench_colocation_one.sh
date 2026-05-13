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
  cleanup_offline
  cleanup_taobench
}

trap cleanup_all EXIT INT TERM

# ------------------------------------------------------------
# Experiment configuration
# ------------------------------------------------------------

EXP_NAME="${EXP_NAME:-taobench_colocation_one}"

# Workload type:
#   none
#   ibench_cpu
#   ibench_memcap
#   ibench_membw
#   ibench_l3
#   spec_mcf
#   spec_lbm
OFFLINE_TYPE="${OFFLINE_TYPE:-none}"

# Real offline workload parameter.
# IMPORTANT:
# - For iBench, this is a real runtime parameter, e.g. workers or size.
# - For SPEC, this is usually empty; SPEC_SIZE/SPEC_COPIES are used instead.
OFFLINE_PARAM="${OFFLINE_PARAM:-}"

# Human-readable label used for run directory, logs, and summary.
# This must NOT be used as iBench runtime argument.
OFFLINE_LABEL="${OFFLINE_LABEL:-}"

# SPEC defaults.
SPEC_CONFIG="${SPEC_CONFIG:-my_test.cfg}"
SPEC_SIZE="${SPEC_SIZE:-test}"
SPEC_COPIES="${SPEC_COPIES:-1}"

# Auto-generate label if not provided.
if [[ -z "${OFFLINE_LABEL}" ]]; then
  if [[ "${OFFLINE_TYPE}" == spec_* ]]; then
    OFFLINE_LABEL="${SPEC_SIZE}_c${SPEC_COPIES}"
  elif [[ -n "${OFFLINE_PARAM}" ]]; then
    OFFLINE_LABEL="${OFFLINE_PARAM}"
  else
    OFFLINE_LABEL="none"
  fi
fi

make_run_dir "${EXP_NAME}_${OFFLINE_TYPE}_${OFFLINE_LABEL}"

save_machine_topology "${RUN_DIR}/machine_topology"
write_config_snapshot "${RUN_DIR}/config.env"

# ------------------------------------------------------------
# Sudo keepalive
# ------------------------------------------------------------

sudo -v
(
  while true; do
    sudo -n true 2>/dev/null || exit
    sleep 60
  done
) &
SUDO_KEEPALIVE_PID=$!

# ------------------------------------------------------------
# Create containers
# ------------------------------------------------------------

log "Creating containers..."
bash "${CBS_ROOT}/containers/create_taobench_server.sh"
bash "${CBS_ROOT}/containers/create_taobench_loadgen.sh"
bash "${CBS_ROOT}/containers/create_offline.sh"

# ------------------------------------------------------------
# Host network tuning
# ------------------------------------------------------------

log "Applying network sysctl..."
sudo -n sysctl -w net.ipv4.ip_local_port_range="1024 65535" || true
sudo -n sysctl -w net.ipv4.tcp_tw_reuse=1 || true
sudo -n sysctl -w net.ipv4.tcp_fin_timeout=15 || true

# ------------------------------------------------------------
# Start TaoBench server
# ------------------------------------------------------------

mkdir -p "${RUN_DIR}/logs" "${RUN_DIR}/raw" "${RUN_DIR}/parsed"

SERVER_LOG="/workspace/results/$(basename "${RUN_DIR}")/logs/server.log"

TAO_SERVER_WARMUP_TIME="${TAO_SERVER_WARMUP_TIME:-2400}"
TAO_SERVER_TEST_TIME="${TAO_SERVER_TEST_TIME:-7200}"

log "Starting TaoBench server..."
bash "${CBS_ROOT}/online/taobench/start_server.sh" \
  "${SERVER_LOG}" \
  "${TAO_SERVER_WARMUP_TIME}" \
  "${TAO_SERVER_TEST_TIME}"

SERVER_BOOTSTRAP_WAIT="${SERVER_BOOTSTRAP_WAIT:-180}"
log "Waiting for server bootstrap: ${SERVER_BOOTSTRAP_WAIT}s"
sleep "${SERVER_BOOTSTRAP_WAIT}"

# ------------------------------------------------------------
# TaoBench prewarm
# ------------------------------------------------------------

log "Prewarming TaoBench..."

PREWARM_CLIENTS="${PREWARM_CLIENTS:-900}"
PREWARM_ROUNDS="${PREWARM_ROUNDS:-8}"
PREWARM_TEST_TIME="${PREWARM_TEST_TIME:-60}"

PREWARM_SUMMARY="${RUN_DIR}/prewarm.csv"
echo "round,clients_per_thread,qps,gets_p99_ms,log_file" > "${PREWARM_SUMMARY}"

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

  echo "${R},${PREWARM_CLIENTS},${qps},${p99},${PREWARM_LOG}" >> "${PREWARM_SUMMARY}"
  tail -20 "${PREWARM_LOG}" | grep -E 'Totals|Gets' || true

  sleep 10
done

# ------------------------------------------------------------
# Start offline workload
# ------------------------------------------------------------

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
    bash "${CBS_ROOT}/offline/ibench/start_memcap.sh" \
      "${OFFLINE_PARAM:-15}" \
      "${OFFLINE_LOG}"
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

OFFLINE_STABILIZE_WAIT="${OFFLINE_STABILIZE_WAIT:-30}"
log "Waiting for offline workload to stabilize: ${OFFLINE_STABILIZE_WAIT}s"
sleep "${OFFLINE_STABILIZE_WAIT}"

# ------------------------------------------------------------
# Measured TaoBench run
# ------------------------------------------------------------

log "Running measured TaoBench client..."

CLIENTS="${CLIENTS_PER_THREAD:-900}"
CLIENT_TEST_TIME="${CLIENT_TEST_TIME:-300}"

LOG_FILE="${RUN_DIR}/raw/client_measured_clients_${CLIENTS}.log"
JSON_FILE="${RUN_DIR}/parsed/client_measured_clients_${CLIENTS}.json"

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

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------

SUMMARY="${RUN_DIR}/summary.csv"

echo "offline_type,offline_param,offline_label,clients_per_thread,qps,gets_p99_ms,client_log,offline_log" > "${SUMMARY}"
echo "${OFFLINE_TYPE},${OFFLINE_PARAM},${OFFLINE_LABEL},${CLIENTS},${QPS},${P99},${LOG_FILE},${OFFLINE_LOG}" >> "${SUMMARY}"

log "Measured result: offline=${OFFLINE_TYPE}, param=${OFFLINE_PARAM}, label=${OFFLINE_LABEL}, clients=${CLIENTS}, qps=${QPS}, p99=${P99}"
log "Summary: ${SUMMARY}"