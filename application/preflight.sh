#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CBS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ENV_FILE="${ENV_FILE:-${CBS_ROOT}/conf/env.sh}"
if [[ -f "${ENV_FILE}" ]]; then
  source "${ENV_FILE}"
elif [[ -f "${CBS_ROOT}/conf/env.sh" ]]; then
  source "${CBS_ROOT}/conf/env.sh"
else
  echo "[WARN] ${ENV_FILE} and conf/env.sh not found; using conf/env.example.sh" >&2
  source "${CBS_ROOT}/conf/env.example.sh"
fi
source "${CBS_ROOT}/scripts/common.sh"

CHECK_DOCKER_IMAGE="${CHECK_DOCKER_IMAGE:-1}"
CHECK_IMAGE_CONTENT="${CHECK_IMAGE_CONTENT:-1}"
CHECK_OFFLINE_PATHS="${CHECK_OFFLINE_PATHS:-1}"
CHECK_DRY_RUN="${CHECK_DRY_RUN:-1}"

pass() {
  echo "[PASS] $*"
}

warn() {
  echo "[WARN] $*" >&2
}

fail() {
  echo "[FAIL] $*" >&2
  return 1
}

status=0

check_cmd() {
  if command -v "$1" >/dev/null 2>&1; then
    pass "command found: $1"
  else
    fail "missing command: $1" || status=1
  fi
}

check_dir() {
  local label="$1"
  local path="$2"
  if [[ -d "${path}" ]]; then
    pass "${label}: ${path}"
  else
    fail "${label} missing: ${path}" || status=1
  fi
}

check_cpuset() {
  local label="$1"
  local cpuset="$2"
  if python3 - "$label" "$cpuset" <<'PY'
import sys
from pathlib import Path

label, cpuset = sys.argv[1], sys.argv[2]
present = set()
text = Path("/sys/devices/system/cpu/present").read_text().strip()
for part in text.split(","):
    if "-" in part:
        a, b = map(int, part.split("-", 1))
        present.update(range(a, b + 1))
    else:
        present.add(int(part))

selected = []
for part in cpuset.split(","):
    part = part.strip()
    if not part:
        continue
    if "-" in part:
        a, b = map(int, part.split("-", 1))
        selected.extend(range(a, b + 1))
    else:
        selected.append(int(part))

missing = [c for c in selected if c not in present]
if missing:
    print(f"{label}: missing CPUs {missing}", file=sys.stderr)
    sys.exit(1)
PY
  then
    pass "${label} cpuset exists: ${cpuset}"
  else
    status=1
  fi
}

check_mems() {
  local label="$1"
  local mems="$2"
  local nodes
  nodes="$(ls -d /sys/devices/system/node/node* 2>/dev/null | sed 's/.*node//' | tr '\n' ' ')"
  for node in ${mems//,/ }; do
    if [[ " ${nodes} " != *" ${node} "* ]]; then
      fail "${label} NUMA node missing: ${node}; available: ${nodes}" || status=1
      return
    fi
  done
  pass "${label} mems exists: ${mems}"
}

echo "== Host commands =="
for cmd in docker python3 lscpu numactl; do
  check_cmd "${cmd}"
done

echo
echo "== Docker =="
if docker info >/dev/null 2>&1; then
  pass "docker daemon reachable"
else
  fail "docker daemon is not reachable" || status=1
fi

if [[ "${CHECK_DOCKER_IMAGE}" == "1" ]]; then
  if docker image inspect "${CLAB_IMAGE}" >/dev/null 2>&1; then
    pass "docker image exists: ${CLAB_IMAGE}"
  else
    fail "docker image missing: ${CLAB_IMAGE}" || status=1
  fi

  if [[ "${DCPERF_MOUNT:-1}" == "0" && "${CHECK_IMAGE_CONTENT}" == "1" ]]; then
    if docker run --rm "${CLAB_IMAGE}" bash -lc '
      set -euo pipefail
      cd /workspace/DCPerf
      test -x ./benchpress_cli.py
      test -d benchmarks/tao_bench
      test -d benchmarks/tao_bench_autoscale
      test -d packages/tao_bench
      test ! -d results
      test ! -d logs
      ! find . -maxdepth 1 \( -name "benchmark_metrics_*" -o -name "*.log" \) | grep -q .
    ' >/dev/null 2>&1; then
      pass "image-baked DCPerf/TaoBench verified"
    else
      fail "image does not contain a clean usable /workspace/DCPerf TaoBench install" || status=1
    fi
  fi
fi

echo
echo "== Paths =="
mkdir -p "${RESULTS_ROOT}" 2>/dev/null || true
check_dir "RESULTS_ROOT" "${RESULTS_ROOT}"
if [[ "${DCPERF_MOUNT:-1}" == "1" ]]; then
  check_dir "DCPERF_DIR" "${DCPERF_DIR}"
else
  pass "DCPERF_MOUNT=0, using image-baked /workspace/DCPerf"
fi

if [[ "${CHECK_OFFLINE_PATHS}" == "1" ]]; then
  check_dir "IBENCH_DIR" "${IBENCH_DIR}"
  check_dir "SPEC_DIR" "${SPEC_DIR}"
else
  warn "Skipping iBench/SPEC path checks."
fi

echo
echo "== Placement =="
check_cpuset "SERVER_CPUSET" "${SERVER_CPUSET}"
check_cpuset "LOADGEN_CPUSET" "${LOADGEN_CPUSET}"
check_cpuset "OFFLINE_CPUSET" "${OFFLINE_CPUSET}"
check_mems "SERVER_MEMS" "${SERVER_MEMS}"
check_mems "LOADGEN_MEMS" "${LOADGEN_MEMS}"
check_mems "OFFLINE_MEMS" "${OFFLINE_MEMS}"

echo
echo "== Topology =="
python3 "${SCRIPT_DIR}/topology.py" --format text | sed -n '1,80p'

if [[ "${CHECK_DRY_RUN}" == "1" ]]; then
  echo
  echo "== Harness dry-run =="
  ACTION=dry-run \
  EXP_NAME="${EXP_NAME:-preflight}" \
  OFFLINE_TYPE="${OFFLINE_TYPE:-none}" \
  CLIENTS_PER_THREAD="${CLIENTS_PER_THREAD:-1}" \
  CLIENT_WARMUP_TIME="${CLIENT_WARMUP_TIME:-0}" \
  CLIENT_TEST_TIME="${CLIENT_TEST_TIME:-1}" \
  TAO_SERVER_WARMUP_TIME="${TAO_SERVER_WARMUP_TIME:-1}" \
  TAO_SERVER_TEST_TIME="${TAO_SERVER_TEST_TIME:-2}" \
  SERVER_BOOTSTRAP_WAIT=0 \
  OFFLINE_STABILIZE_WAIT=0 \
  bash "${SCRIPT_DIR}/run_taobench_colocation.sh"
fi

echo
if [[ "${status}" == "0" ]]; then
  pass "preflight complete"
else
  fail "preflight found issues"
fi
exit "${status}"
