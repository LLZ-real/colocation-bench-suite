#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Stage 1-A Master Runner (v2 — supports ibench / spec / mixed).
#
# Usage:
#   bash experiments/data_collection_experiment/run_all.sh spec              # all 3 placements
#   bash experiments/data_collection_experiment/run_all.sh spec-same_numa    # single placement
#   bash experiments/data_collection_experiment/run_all.sh ibench
#   bash experiments/data_collection_experiment/run_all.sh ibench-same_numa
#   bash experiments/data_collection_experiment/run_all.sh smoke
#   bash experiments/data_collection_experiment/run_all.sh list
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CBS_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

MODE="${1:-list}"

# ----------------------------
# Shared defaults (override via env)
# ----------------------------

CLAB_IMAGE="${CLAB_IMAGE:-dcperf-taobench:ready}"
DCPERF_MOUNT="${DCPERF_MOUNT:-0}"
RESULTS_ROOT="${RESULTS_ROOT:-/home/lilinzhen/colocate_lab/results/cbs}"

SERVER_CPUSET="${SERVER_CPUSET:-0,1,2,3,4,5,6,7}"
SERVER_MEMS="${SERVER_MEMS:-0}"
LOADGEN_CPUSET="${LOADGEN_CPUSET:-32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47}"
LOADGEN_MEMS="${LOADGEN_MEMS:-1}"

CLIENTS_PER_THREAD="${CLIENTS_PER_THREAD:-900}"
CLIENT_TEST_TIME="${CLIENT_TEST_TIME:-60}"
CLIENT_WARMUP_TIME="${CLIENT_WARMUP_TIME:-120}"
PREWARM_ROUNDS="${PREWARM_ROUNDS:-8}"
PREWARM_TEST_TIME="${PREWARM_TEST_TIME:-60}"

TAO_SERVER_WARMUP_TIME="${TAO_SERVER_WARMUP_TIME:-2400}"

MEASURE_REPEATS="${MEASURE_REPEATS:-1}"
MEASURE_GAP="${MEASURE_GAP:-5}"
SPEC_CONFIG="${SPEC_CONFIG:-my_test.cfg}"
BASELINE_INTERVAL="${BASELINE_INTERVAL:-10}"

MATRIX_DIR="${CBS_ROOT}/docs"

# ----------------------------
# Per-mode overrides
# ----------------------------

case "${MODE%%-*}" in
  spec)
    TAO_SERVER_TEST_TIME="${TAO_SERVER_TEST_TIME:-18000}"
    SERVER_BOOTSTRAP_WAIT="${SERVER_BOOTSTRAP_WAIT:-180}"
    OFFLINE_STABILIZE_WAIT="${OFFLINE_STABILIZE_WAIT:-90}"
    OFFLINE_COOLDOWN_WAIT="${OFFLINE_COOLDOWN_WAIT:-5}"
    STAGE1_MATRIX="${MATRIX_DIR}/stage1_spec_matrix.csv"
    STAGE1_GEN_ARGS="--mode spec"
    STAGE1_PREFIX="stage1_sail3090_spec"
    ;;
  ibench)
    TAO_SERVER_TEST_TIME="${TAO_SERVER_TEST_TIME:-18000}"
    SERVER_BOOTSTRAP_WAIT="${SERVER_BOOTSTRAP_WAIT:-180}"
    OFFLINE_STABILIZE_WAIT="${OFFLINE_STABILIZE_WAIT:-30}"
    OFFLINE_COOLDOWN_WAIT="${OFFLINE_COOLDOWN_WAIT:-5}"
    STAGE1_MATRIX="${MATRIX_DIR}/stage1_ibench_keepers.csv"
    STAGE1_GEN_ARGS="--mode ibench"
    STAGE1_PREFIX="stage1_sail3090_ibench"
    ;;
  smoke)
    TAO_SERVER_TEST_TIME="${TAO_SERVER_TEST_TIME:-1200}"
    SERVER_BOOTSTRAP_WAIT="${SERVER_BOOTSTRAP_WAIT:-30}"
    OFFLINE_STABILIZE_WAIT="${OFFLINE_STABILIZE_WAIT:-60}"
    OFFLINE_COOLDOWN_WAIT="${OFFLINE_COOLDOWN_WAIT:-2}"
    CLIENTS_PER_THREAD=900
    CLIENT_TEST_TIME=10
    CLIENT_WARMUP_TIME=5
    PREWARM_ROUNDS=2
    PREWARM_TEST_TIME=10
    TAO_SERVER_WARMUP_TIME=60
    BASELINE_INTERVAL=10
    STAGE1_MATRIX="/tmp/stage1_smoke_matrix.csv"
    STAGE1_GEN_ARGS="--mode smoke"
    STAGE1_PREFIX="stage1_smoke"
    ;;
  list)
    echo "Usage: bash run_all.sh [spec|ibench|smoke|list]"
    exit 0
    ;;
  *)
    echo "Unknown mode: ${MODE}"
    echo "Usage: bash experiments/data_collection_experiment/run_all.sh [spec|ibench|smoke|list]"
    exit 1
    ;;
esac

# ----------------------------
# Placement dispatch
# ----------------------------

PLACEMENTS=("same_numa" "cross_numa" "same_smt")

if [[ "${MODE}" == *-* ]]; then
  # Single-placement mode (e.g. "spec-same_numa")
  TARGET="${MODE#*-}"
  PLACEMENTS=("${TARGET}")
fi

# ----------------------------
# Generate matrix
# ----------------------------

generate_matrix() {
  local gen="${CBS_ROOT}/tools/generate_stage1_full_matrix.py"
  echo "[generate] creating matrix: ${STAGE1_GEN_ARGS} → ${STAGE1_MATRIX}"
  python3 "${gen}" ${STAGE1_GEN_ARGS} --out "${STAGE1_MATRIX}"
}

# ----------------------------
# Resume check: if a placement already has a summary.csv with all conditions, skip
# ----------------------------

is_placement_done() {
  local exp_name="$1"
  # Find latest run dir for this exp_name
  local rundir
  rundir=$(ls -dt "${RESULTS_ROOT}/${exp_name}_"* 2>/dev/null | head -1)
  if [[ -z "${rundir}" ]]; then
    return 1  # no run dir exists → not done
  fi
  local summary="${rundir}/summary.csv"
  if [[ ! -f "${summary}" ]]; then
    return 1  # no summary → not done
  fi
  # Count completed rows (exclude header)
  local completed
  completed=$(tail -n +2 "${summary}" 2>/dev/null | wc -l)
  local expected
  expected=$(tail -n +2 "${STAGE1_MATRIX}" 2>/dev/null | grep -cv '^[[:space:]]*$')
  if [[ "${completed}" -ge "${expected}" && "${expected}" -gt 0 ]]; then
    return 0  # all conditions done
  fi
  return 1
}

# ----------------------------
# Run helpers
# ----------------------------

run_one() {
  local placement="$1"
  local exp_name="${STAGE1_PREFIX}_${placement}"

  if is_placement_done "${exp_name}"; then
    echo ""
    echo "================================================================================"
    echo "  SKIP: ${exp_name} (all conditions already completed)"
    echo "================================================================================"
    return 0
  fi

  echo ""
  echo "================================================================================"
  echo "  START: ${exp_name}"
  echo "  Placement: ${placement}"
  echo "  Matrix:    ${STAGE1_MATRIX}"
  echo "  Stabilize: ${OFFLINE_STABILIZE_WAIT}s"
  echo "  Started:   $(date -Iseconds)"
  echo "================================================================================"

  local ec=0
  MATRIX_FILE="${STAGE1_MATRIX}" \
    PLACEMENT="${placement}" \
    EXP_NAME="${exp_name}" \
    CLAB_IMAGE="${CLAB_IMAGE}" \
    DCPERF_MOUNT="${DCPERF_MOUNT}" \
    RESULTS_ROOT="${RESULTS_ROOT}" \
    SERVER_CPUSET="${SERVER_CPUSET}" \
    SERVER_MEMS="${SERVER_MEMS}" \
    LOADGEN_CPUSET="${LOADGEN_CPUSET}" \
    LOADGEN_MEMS="${LOADGEN_MEMS}" \
    CLIENTS_PER_THREAD="${CLIENTS_PER_THREAD}" \
    CLIENT_TEST_TIME="${CLIENT_TEST_TIME}" \
    CLIENT_WARMUP_TIME="${CLIENT_WARMUP_TIME}" \
    PREWARM_ROUNDS="${PREWARM_ROUNDS}" \
    PREWARM_TEST_TIME="${PREWARM_TEST_TIME}" \
    TAO_SERVER_WARMUP_TIME="${TAO_SERVER_WARMUP_TIME}" \
    TAO_SERVER_TEST_TIME="${TAO_SERVER_TEST_TIME}" \
    SERVER_BOOTSTRAP_WAIT="${SERVER_BOOTSTRAP_WAIT}" \
    OFFLINE_STABILIZE_WAIT="${OFFLINE_STABILIZE_WAIT}" \
    OFFLINE_COOLDOWN_WAIT="${OFFLINE_COOLDOWN_WAIT}" \
    BASELINE_INTERVAL="${BASELINE_INTERVAL}" \
    MEASURE_REPEATS="${MEASURE_REPEATS}" \
    MEASURE_GAP="${MEASURE_GAP}" \
    SPEC_CONFIG="${SPEC_CONFIG}" \
    bash "${SCRIPT_DIR}/stage1_sweep_clean.sh" || ec=$?

  echo "================================================================================"
  if [[ "${ec}" == "0" ]]; then
    echo "  DONE:  ${exp_name}"
  else
    echo "  FAIL:  ${exp_name} (exit code ${ec})"
  fi
  echo "  Ended: $(date -Iseconds)"
  echo "================================================================================"
}

# ----------------------------
# Main
# ----------------------------

echo "=== Stage 1-A Runner ==="
echo "Mode:     ${MODE}"
echo "Placements: ${PLACEMENTS[*]}"
echo "Started:  $(date -Iseconds)"
echo

# Guard: refuse if another experiment's containers are still alive
if docker ps --format '{{.Names}}' 2>/dev/null | grep -qE '^clab-(server|loadgen|offline)$'; then
  echo "[ERROR] Containers clab-server/clab-loadgen/clab-offline already exist."
  echo "        Another experiment may still be running. Stop it first, or run:"
  echo "        docker rm -f clab-server clab-loadgen clab-offline"
  exit 1
fi

generate_matrix

for pl in "${PLACEMENTS[@]}"; do
  run_one "${pl}" || true
done

echo ""
echo "=== ALL DONE ==="
echo "Ended: $(date -Iseconds)"
