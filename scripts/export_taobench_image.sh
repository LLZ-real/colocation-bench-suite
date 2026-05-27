#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CBS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${CBS_ROOT}/scripts/common.sh"

IMAGE="${IMAGE:-dcperf-taobench:ready}"
ARTIFACT_DIR="${ARTIFACT_DIR:-/home/lilinzhen/colocate_lab/artifacts}"
OUT="${1:-${OUT:-${ARTIFACT_DIR}/dcperf-taobench-ready.tar}}"

require_cmd docker

docker image inspect "${IMAGE}" >/dev/null 2>&1 || die "Docker image not found: ${IMAGE}"

out_abs="$(readlink -m "${OUT}")"
case "${out_abs}" in
  "${CBS_ROOT}"/*)
    die "Refusing to export image tar inside source repo: ${out_abs}. Use ARTIFACT_DIR or an absolute path outside ${CBS_ROOT}."
    ;;
esac

mkdir -p "$(dirname "${out_abs}")"
log "Exporting ${IMAGE} -> ${out_abs}"
docker save "${IMAGE}" -o "${out_abs}"
ls -lh "${out_abs}"
log "Export done."
