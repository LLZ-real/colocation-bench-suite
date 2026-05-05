#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/../conf/env.sh"

docker rm -f "${SERVER_CONTAINER}" 2>/dev/null || true
docker rm -f "${LOADGEN_CONTAINER}" 2>/dev/null || true
docker rm -f clab-offline 2>/dev/null || true

echo "All colocation containers removed."
