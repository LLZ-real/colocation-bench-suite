#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Stage 1-B: PMU + QPS collection (v2 — simplified).
#
# Runs perf system-wide during the TaoBench client measurement
# window. perf exits naturally (sleep $PERF_DURATION), no kill
# needed. QPS/P99 are also recorded from the same client run.
#
# Prerequisite:
#   echo 'lilinzhen ALL=(ALL) NOPASSWD: /usr/bin/perf' | sudo tee /etc/sudoers.d/perf-nopasswd
#
# Usage:
#   MATRIX_FILE=docs/results/stage1_stageB_matrix.csv \
#   PLACEMENT=same_numa EXP_NAME=stage1_same_numa_pmu \
#   bash experiments/data_collection_experiment/stage1_sweep_pmu.sh
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CBS_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

source "${CBS_ROOT}/conf/env.sh"
source "${CBS_ROOT}/scripts/common.sh"
source "${CBS_ROOT}/scripts/cleanup.sh"

# ----------------------------
# Parameters
# ----------------------------

PLACEMENT="${PLACEMENT:?set PLACEMENT}"
MATRIX_FILE="${MATRIX_FILE:?set MATRIX_FILE}"
EXP_NAME="${EXP_NAME:-stage1_${PLACEMENT}_pmu}"

CLIENTS="${CLIENTS_PER_THREAD:-900}"
CLIENT_WARMUP_TIME="${CLIENT_WARMUP_TIME:-120}"
CLIENT_TEST_TIME="${CLIENT_TEST_TIME:-60}"

PREWARM_CLIENTS="${PREWARM_CLIENTS:-900}"
PREWARM_ROUNDS="${PREWARM_ROUNDS:-8}"
PREWARM_TEST_TIME="${PREWARM_TEST_TIME:-60}"

SERVER_BOOTSTRAP_WAIT="${SERVER_BOOTSTRAP_WAIT:-180}"
OFFLINE_STABILIZE_WAIT="${OFFLINE_STABILIZE_WAIT:-90}"
OFFLINE_COOLDOWN_WAIT="${OFFLINE_COOLDOWN_WAIT:-5}"

TAO_SERVER_WARMUP_TIME="${TAO_SERVER_WARMUP_TIME:-2400}"
TAO_SERVER_TEST_TIME="${TAO_SERVER_TEST_TIME:-18000}"

SPEC_CONFIG="${SPEC_CONFIG:-my_test.cfg}"
ENABLE_SUDO="${ENABLE_SUDO:-1}"
BASELINE_INTERVAL="${BASELINE_INTERVAL:-10}"

# perf runs for: client warmup + test + 30s buffer
PERF_DURATION=$((CLIENT_WARMUP_TIME + CLIENT_TEST_TIME + 30))

# ----------------------------
# Placement (direct assignment — conf/env.sh may have other defaults)
# ----------------------------

case "${PLACEMENT}" in
  same_numa)  OFFLINE_CPUSET="16,17,18,19,20,21,22,23"; OFFLINE_MEMS="0" ;;
  cross_numa) OFFLINE_CPUSET="48,49,50,51,52,53,54,55"; OFFLINE_MEMS="1" ;;
  same_smt)   OFFLINE_CPUSET="64,65,66,67,68,69,70,71"; OFFLINE_MEMS="0" ;;
  *) die "Unknown PLACEMENT=${PLACEMENT}" ;;
esac

# ----------------------------
# Run directory
# ----------------------------

RUN_TAG="$(date +%Y%m%d_%H%M%S)"
RUN_DIR="${RESULTS_ROOT}/${EXP_NAME}_${RUN_TAG}"

mkdir -p "${RUN_DIR}/pmu" "${RUN_DIR}/logs" "${RUN_DIR}/raw" "${RUN_DIR}/parsed" "${RUN_DIR}/progress"

SUMMARY="${RUN_DIR}/summary.csv"
PROGRESS_FILE="${RUN_DIR}/progress/completed.csv"
FAILURES_FILE="${RUN_DIR}/progress/failures.csv"
PMU_META="${RUN_DIR}/pmu/pmu_meta.env"

SUDO_KEEPALIVE_PID=""

# ----------------------------
# Helpers
# ----------------------------

log() {
  echo "[$(date '+%F %T')] $*" >> "${RUN_DIR}/progress/full.log"
  echo "[$(date '+%F %T')] $*" >&2
}

die() { echo "[ERROR] $*" >&2; exit 1; }

save_progress() { echo "$1" >> "${PROGRESS_FILE}"; }
record_failure() { echo "$1,$2" >> "${FAILURES_FILE}"; }

load_completed() { [[ -f "${PROGRESS_FILE}" ]] && sort -u "${PROGRESS_FILE}" || true; }

parse_json_field() {
  local jf="$1" key="$2"
  python3 - "$jf" "$key" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    v = d.get(sys.argv[2], "")
    print("" if v is None else v)
except Exception: print("")
PY
}

on_exit() {
  local code=$?
  log "Exiting code=${code}. Cleaning up..."
  cleanup_sudo_keepalive || true
  cleanup_offline || true
  cleanup_taobench || true
  docker rm -f "${SERVER_CONTAINER}" "${LOADGEN_CONTAINER}" "${OFFLINE_CONTAINER}" 2>/dev/null || true
  exit "${code}"
}
on_interrupt() {
  log "Interrupted."; trap - EXIT
  cleanup_sudo_keepalive || true; cleanup_offline || true; cleanup_taobench || true
  docker rm -f "${SERVER_CONTAINER}" "${LOADGEN_CONTAINER}" "${OFFLINE_CONTAINER}" 2>/dev/null || true
  exit 130
}
trap on_exit EXIT; trap on_interrupt INT TERM

cleanup_sudo_keepalive() { [[ -n "${SUDO_KEEPALIVE_PID}" ]] && kill "${SUDO_KEEPALIVE_PID}" 2>/dev/null || true; }

write_summary_header() {
  cat > "${SUMMARY}" <<'EOF'
timestamp,exp_name,placement,condition_id,offline_type,offline_param,offline_intensity,offline_label,spec_size,spec_copies,spec_bench,clients_per_thread,client_test_time,qps,gets_p99_ms,perf_csv,client_log,offline_log,run_dir
EOF
}

# ----------------------------
# PMU events (validated against this platform)
# ----------------------------

PMU_COMMON="cycles,instructions,L1-dcache-loads,L1-dcache-load-misses,LLC-loads,LLC-load-misses,branch-instructions,branch-misses,cache-references,cache-misses,context-switches,cpu-migrations,dTLB-loads,dTLB-load-misses,l2_rqsts.all_demand_miss,l2_rqsts.all_demand_data_rd,offcore_requests.all_data_rd,offcore_requests.demand_data_rd"

check_perf_available() {
  if [[ "${ENABLE_SUDO}" != "1" ]]; then return 1; fi
  LANG=C sudo -n perf stat -I 1000 -e cycles sleep 2 2>&1 | grep -q "cycles" || return 1
  return 0
}

validate_event() {
  local ev="$1"
  LANG=C sudo -n perf stat -I 1000 -e "$ev" sleep 2 2>&1 | grep -qv "parser error\|event syntax\|not supported\|cannot resolve"
}

build_pmu_events() {
  local events="${PMU_COMMON}"
  # same_smt: try TMA events
  if [[ "${PLACEMENT}" == "same_smt" ]]; then
    local tma="cpu/event=0x9c,umask=0x01,name=FRONTEND_BOUND/,cpu/event=0xc2,umask=0x02,name=RETIRING/,cpu/event=0x0d,umask=0x03,name=BAD_SPECULATION/,cpu/event=0xa3,umask=0x04,name=BACKEND_BOUND/"
    if validate_event "cpu/event=0x9c,umask=0x01/"; then
      events="${events},${tma}"
      log "TMA events: OK"
    else
      log "TMA events: UNSUPPORTED (skipping)"
    fi
  fi
  PMU_EVENTS="${events}"
  log "PMU events (${PMU_EVENTS//,/$'\n'  })"
}

# ----------------------------
# perf launcher (sleep-based, no kill)
# ----------------------------

start_perf() {
  local cid="$1"
  local pmu_dir="${RUN_DIR}/pmu/${cid}"
  mkdir -p "${pmu_dir}"

  if [[ "${ENABLE_SUDO}" != "1" ]]; then
    log "SKIP perf (ENABLE_SUDO=0)"
    return 0
  fi

  log "Starting perf for ${PERF_DURATION}s..."
  LANG=C sudo -n perf stat -I 1000 -x, -e "${PMU_EVENTS}" -a \
    sleep "${PERF_DURATION}" \
    2> "${pmu_dir}/host_perf.csv" &

  echo $! > "${pmu_dir}/perf.pid"
  log "  perf PID=$(cat ${pmu_dir}/perf.pid)"
}

wait_perf() {
  local cid="$1"
  local pmu_dir="${RUN_DIR}/pmu/${cid}"
  local pid_file="${pmu_dir}/perf.pid"

  if [[ ! -f "${pid_file}" ]]; then return 0; fi
  local pid; pid=$(cat "${pid_file}")

  # Wait for perf to finish naturally (sleep expired)
  wait "${pid}" 2>/dev/null || true

  if [[ -f "${pmu_dir}/host_perf.csv" ]]; then
    local lines; lines=$(wc -l < "${pmu_dir}/host_perf.csv")
    log "  perf: ${lines} samples"
    if [[ "${lines}" -lt 2 ]]; then
      log "  WARNING: perf produced too few samples! First lines:"
      head -3 "${pmu_dir}/host_perf.csv" 2>/dev/null | while read -r l; do log "    ${l}"; done
    fi
  else
    log "  ERROR: perf CSV not found: ${pmu_dir}/host_perf.csv"
  fi
}

# ----------------------------
# Container management
# ----------------------------

create_containers() {
  log "Creating containers..."
  bash "${CBS_ROOT}/containers/create_taobench_server.sh"
  bash "${CBS_ROOT}/containers/create_taobench_loadgen.sh"
  bash "${CBS_ROOT}/containers/create_offline.sh"
  log "Containers created."
}

recreate_offline_container() {
  cleanup_offline || true
  bash "${CBS_ROOT}/containers/create_offline.sh"
}

verify_binding() {
  local c="$1" exp_cpus="$2" exp_mems="$3" label="$4"
  local act_cpus; act_cpus=$(docker inspect "$c" --format '{{.HostConfig.CpusetCpus}}' 2>/dev/null || echo '')
  local act_mems; act_mems=$(docker inspect "$c" --format '{{.HostConfig.CpusetMems}}' 2>/dev/null || echo '')
  [[ "$act_cpus" == "$exp_cpus" ]] || die "$c ($label) cpuset MISMATCH: $act_cpus != $exp_cpus"
  [[ "$act_mems" == "$exp_mems" ]] || die "$c ($label) mems MISMATCH: $act_mems != $exp_mems"
  log "Binding verified: $c ($label) cpus=$act_cpus mems=$act_mems"
}

# ----------------------------
# Sudo
# ----------------------------

start_sudo_keepalive() {
  if [[ "${ENABLE_SUDO}" != "1" ]]; then return 0; fi

  # Verify perf works via sudo (NOPASSWD is scoped to /usr/bin/perf only)
  if ! LANG=C sudo -n perf stat -e cycles true 2>&1 | grep -q "cycles"; then
    log "WARNING: sudo perf did not work. Check NOPASSWD: /usr/bin/perf."
    log "  Fix: echo '${USER} ALL=(ALL) NOPASSWD: /usr/bin/perf' | sudo tee /etc/sudoers.d/perf-nopasswd"
    ENABLE_SUDO=0; return 0
  fi

  log "sudo + perf verified OK"
  (while true; do sudo -n true 2>/dev/null || exit; sleep 60; done) &
  SUDO_KEEPALIVE_PID="$!"
}

# ----------------------------
# Server + prewarm
# ----------------------------

start_server() {
  local slog="/workspace/results/$(basename "${RUN_DIR}")/logs/server.log"
  bash "${CBS_ROOT}/online/taobench/start_server.sh" "${slog}" "${TAO_SERVER_WARMUP_TIME}" "${TAO_SERVER_TEST_TIME}"
  sleep "${SERVER_BOOTSTRAP_WAIT}"
}

prewarm() {
  log "Prewarm: ${PREWARM_ROUNDS} rounds"
  for r in $(seq 1 "${PREWARM_ROUNDS}"); do
    local plog="${RUN_DIR}/raw/prewarm_${r}.log"
    bash "${CBS_ROOT}/online/taobench/run_client.sh" "${PREWARM_CLIENTS}" "${PREWARM_TEST_TIME}" "${plog}" || true
    log "Prewarm ${r}/${PREWARM_ROUNDS} done"
    sleep 10
  done
}

# ----------------------------
# Offline workload
# ----------------------------

start_offline() {
  local ot="$1" op="$2" oi="$3" olog="$4" sz="$5" sc="$6" sb="$7"
  case "$ot" in
    none) log "No offline workload." ;;
    ibench_cpu)    IBENCH_CPU_ARG="${oi:-30}"    bash "${CBS_ROOT}/offline/ibench/start_cpu.sh"    "${op:-8}"  "${olog}" ;;
    ibench_membw)  IBENCH_MEMBW_ARG="${oi:-30}"  bash "${CBS_ROOT}/offline/ibench/start_membw.sh"  "${op:-8}"  "${olog}" ;;
    ibench_l3)     IBENCH_L3_ARG="${oi:-30}"     bash "${CBS_ROOT}/offline/ibench/start_l3.sh"     "${op:-8}"  "${olog}" ;;
    ibench_memcap) bash "${CBS_ROOT}/offline/ibench/start_memcap.sh" "${op:-15}" "${olog}" ;;
    spec)
      [[ -n "$sb" ]] || die "spec requires spec_bench"
      SPEC_COPIES="$sc" bash "${CBS_ROOT}/offline/spec/start_runcpu.sh" "$sb" "$olog" "$sz" "${SPEC_CONFIG}" ;;
    *) die "Unknown offline_type=$ot" ;;
  esac
}

wait_for_offline_processes() {
  local max_wait=60 waited=0
  while [[ "$waited" -lt "$max_wait" ]]; do
    local n; n=$(docker top "${OFFLINE_CONTAINER}" 2>/dev/null | wc -l)
    if [[ "$n" -ge 4 ]]; then
      log "  offline processes: $n (after ${waited}s)"; return 0
    fi
    sleep 2; waited=$((waited+2))
  done
  log "  WARNING: offline processes may not have fully spawned after ${waited}s"
}

# ----------------------------
# Single condition
# ----------------------------

run_one_condition() {
  local cid="$1" ot="$2" op="$3" oi="$4" ol="$5" sz="$6" sc="$7" sb="$8"
  local olog="/workspace/results/$(basename "${RUN_DIR}")/logs/offline_${cid}.log"
  local clog="${RUN_DIR}/raw/${cid}.log"
  local json="${RUN_DIR}/parsed/${cid}.json"
  local perf_csv="${RUN_DIR}/pmu/${cid}/host_perf.csv"

  log "============================================================"
  log "Condition: ${cid}"
  log "  type=${ot} param=${op} intensity=${oi}"
  log "============================================================"

  recreate_offline_container
  verify_binding "${OFFLINE_CONTAINER}" "${OFFLINE_CPUSET}" "${OFFLINE_MEMS}" "offline"

  start_offline "$ot" "$op" "$oi" "$olog" "$sz" "$sc" "$sb"

  if [[ "$ot" != "none" ]]; then
    wait_for_offline_processes
    log "Waiting stabilize: ${OFFLINE_STABILIZE_WAIT}s"
    sleep 3  # small buffer after process check
    local remaining=$((OFFLINE_STABILIZE_WAIT - 3))
    [[ "$remaining" -lt 0 ]] && remaining=0
    sleep "$remaining"
  fi

  # Start perf (background, exits naturally via sleep)
  start_perf "$cid"

  # Run client (same as Stage 1-A)
  log "Running client..."
  bash "${CBS_ROOT}/online/taobench/run_client.sh" "${CLIENTS}" "${CLIENT_TEST_TIME}" "${clog}" || {
    log "WARNING: client failed for ${cid}"
    record_failure "${cid}" "client_failed"
  }

  python3 "${CBS_ROOT}/parsers/parse_taobench_client.py" "${clog}" --json-out "${json}" || true

  local qps; qps=$(parse_json_field "${json}" qps)
  local p99; p99=$(parse_json_field "${json}" gets_p99_ms)

  # Wait for perf to finish
  wait_perf "$cid"

  if [[ "$ot" != "none" ]]; then
    cleanup_offline || true
  fi
  sleep "${OFFLINE_COOLDOWN_WAIT}"

  # Write summary
  python3 - "${SUMMARY}" "$(date -Iseconds)" "${EXP_NAME}" "${PLACEMENT}" \
    "${cid}" "${ot}" "${op}" "${oi}" "${ol}" "${sz}" "${sc}" "${sb}" \
    "${CLIENTS}" "${CLIENT_TEST_TIME}" "${qps}" "${p99}" \
    "${perf_csv}" "${clog}" "${olog}" "${RUN_DIR}" <<'PY'
import csv, sys
with open(sys.argv[1],"a",newline="") as f:
    csv.writer(f).writerow(sys.argv[2:])
PY

  log "  QPS=${qps}  P99=${p99}"
  save_progress "${cid}"
}

# ----------------------------
# Matrix reader
# ----------------------------

read_matrix() {
  tail -n +2 "${MATRIX_FILE}" | tr -d '\r' | grep -v '^[[:space:]]*$'
}

# ----------------------------
# Main sweep
# ----------------------------

run_sweep() {
  [[ -f "${MATRIX_FILE}" ]] || die "MATRIX_FILE not found: ${MATRIX_FILE}"
  local completed; completed=$(load_completed)
  local total=0 skipped=0 ran=0 failed=0

  while IFS=',' read -r cid ot op oi ol sz sc sb rest; do
    [[ "$cid" == "condition_id" ]] && continue
    [[ -z "$cid" ]] && continue
    total=$((total+1))

    if echo "$completed" | grep -qFx "$cid"; then
      skipped=$((skipped+1))
      log "[${total}] SKIP ${cid} (done)"; continue
    fi

    log "[${total}] RUN ${cid}"
    if run_one_condition "$cid" "$ot" "$op" "$oi" "$ol" "$sz" "$sc" "$sb"; then
      ran=$((ran+1))
    else
      failed=$((failed+1))
      record_failure "$cid" "condition_failed"
    fi
    log "Progress: ${ran} ran, ${failed} failed, ${skipped} skipped, ${total} total"
  done < <(read_matrix)

  log "Sweep complete: ${ran}/${total} ran, ${failed} failed, ${skipped} skipped"
}

# ----------------------------
# Main
# ----------------------------

log "=== Stage 1-B ==="
log "PLACEMENT=${PLACEMENT}  MATRIX=${MATRIX_FILE}"
log "PERF_DURATION=${PERF_DURATION}s"

# Guard
if docker ps --format '{{.Names}}' 2>/dev/null | grep -qE '^clab-(server|loadgen|offline)$'; then
  die "Containers already running. Another experiment may be active."
fi

start_sudo_keepalive
build_pmu_events

echo "PLACEMENT=${PLACEMENT}" > "${PMU_META}"
echo "PMU_EVENTS=${PMU_EVENTS}" >> "${PMU_META}"
echo "PERF_DURATION=${PERF_DURATION}" >> "${PMU_META}"

create_containers
verify_binding "${SERVER_CONTAINER}" "${SERVER_CPUSET}" "${SERVER_MEMS}" "server"
verify_binding "${LOADGEN_CONTAINER}" "${LOADGEN_CPUSET}" "${LOADGEN_MEMS}" "loadgen"

sudo -n sysctl -w net.ipv4.ip_local_port_range="1024 65535" 2>/dev/null || true
sudo -n sysctl -w net.ipv4.tcp_tw_reuse=1 2>/dev/null || true
sudo -n sysctl -w net.ipv4.tcp_fin_timeout=15 2>/dev/null || true

write_summary_header
start_server
prewarm
run_sweep

log "=== Stage 1-B completed ==="
log "Run directory: ${RUN_DIR}"
