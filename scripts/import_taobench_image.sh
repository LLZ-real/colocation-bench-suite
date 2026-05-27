#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CBS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${CBS_ROOT}/scripts/common.sh"

TAR_PATH="${1:?Usage: bash scripts/import_taobench_image.sh <dcperf-taobench-ready.tar>}"
EXPECTED_IMAGE="${EXPECTED_IMAGE:-dcperf-taobench:ready}"

require_cmd docker
[[ -f "${TAR_PATH}" ]] || die "Image tar not found: ${TAR_PATH}"

log "Loading Docker image from ${TAR_PATH}"
docker load -i "${TAR_PATH}"

log "Checking ${EXPECTED_IMAGE}"
docker image inspect "${EXPECTED_IMAGE}" >/dev/null 2>&1 || die "Expected image not found after load: ${EXPECTED_IMAGE}"

docker run --rm "${EXPECTED_IMAGE}" bash -lc '
set -euo pipefail
cd /workspace/DCPerf
test -x ./benchpress_cli.py
test -d benchmarks/tao_bench
test -d benchmarks/tao_bench_autoscale
test -d packages/tao_bench
test ! -d results
test ! -d logs
! find . -maxdepth 1 \( -name "benchmark_metrics_*" -o -name "*.log" \) | grep -q .
openssl version
ldconfig -p | grep -E "libgflags|libssl" >/dev/null
'

log "Import verified: ${EXPECTED_IMAGE}"
