#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CBS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${CBS_ROOT}/scripts/common.sh"

IMAGE="${IMAGE:-dcperf-taobench:ready}"
OUT="${1:-${OUT:-dcperf-taobench-ready.tar}}"

require_cmd docker

docker image inspect "${IMAGE}" >/dev/null 2>&1 || die "Docker image not found: ${IMAGE}"

log "Exporting ${IMAGE} -> ${OUT}"
docker save "${IMAGE}" -o "${OUT}"
ls -lh "${OUT}"
log "Export done."
