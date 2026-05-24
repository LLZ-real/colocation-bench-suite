#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CBS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

COMMON_ENV=(
  ENABLE_PERF=0
  SERVER_BOOTSTRAP_WAIT=180
  PREWARM_ROUNDS=8
  PREWARM_CLIENTS=900
  PREWARM_TEST_TIME=60
  CLIENTS_PER_THREAD=900
  CLIENT_TEST_TIME=300
  CLIENT_WARMUP_TIME=120
  MEASURE_REPEATS=3
  MEASURE_GAP=30
  OFFLINE_STABILIZE_WAIT=60
)

run_one() {
  echo
  echo "============================================================"
  echo "[RUN] $*"
  echo "============================================================"
  env "${COMMON_ENV[@]}" "$@" bash "${CBS_ROOT}/experiments/taobench_colocation_repeat_one.sh"
}

# 1. Baseline: more repeats
env \
  ENABLE_PERF=0 \
  SERVER_BOOTSTRAP_WAIT=180 \
  PREWARM_ROUNDS=8 \
  PREWARM_CLIENTS=900 \
  PREWARM_TEST_TIME=60 \
  CLIENTS_PER_THREAD=900 \
  CLIENT_TEST_TIME=300 \
  CLIENT_WARMUP_TIME=120 \
  MEASURE_REPEATS=5 \
  MEASURE_GAP=30 \
  EXP_NAME=stage1_baseline_repeat5 \
  OFFLINE_TYPE=none \
  OFFLINE_LABEL=none \
  bash "${CBS_ROOT}/experiments/taobench_colocation_repeat_one.sh"

# 2. iBench CPU sanity point
run_one \
  EXP_NAME=stage1_ibench_cpu_w8 \
  OFFLINE_TYPE=ibench_cpu \
  OFFLINE_PARAM=8 \
  OFFLINE_LABEL=w8

# 3. iBench memory bandwidth gradient
for W in 2 4 8; do
  run_one \
    EXP_NAME=stage1_ibench_membw_w${W} \
    OFFLINE_TYPE=ibench_membw \
    OFFLINE_PARAM="${W}" \
    OFFLINE_LABEL="w${W}"
done

# 4. iBench L3 gradient
for W in 2 4 8; do
  run_one \
    EXP_NAME=stage1_ibench_l3_w${W} \
    OFFLINE_TYPE=ibench_l3 \
    OFFLINE_PARAM="${W}" \
    OFFLINE_LABEL="w${W}"
done

# 5. SPEC mcf gradient
for C in 2 4 8; do
  run_one \
    SPEC_CONFIG=my_test.cfg \
    SPEC_SIZE=ref \
    SPEC_COPIES="${C}" \
    EXP_NAME=stage1_spec_mcf_ref_c${C} \
    OFFLINE_TYPE=spec_mcf \
    OFFLINE_LABEL="ref_c${C}"
done

# 6. SPEC lbm gradient
for C in 2 4 8; do
  run_one \
    SPEC_CONFIG=my_test.cfg \
    SPEC_SIZE=ref \
    SPEC_COPIES="${C}" \
    EXP_NAME=stage1_spec_lbm_ref_c${C} \
    OFFLINE_TYPE=spec_lbm \
    OFFLINE_LABEL="ref_c${C}"
done