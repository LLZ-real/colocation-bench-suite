#!/usr/bin/env bash
set -euo pipefail

CBS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 "${CBS_ROOT}/application/topology.py" --format text
echo
bash "${CBS_ROOT}/application/preflight.sh"
