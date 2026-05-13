#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/../../conf/env.sh"
source "$(dirname "$0")/../../scripts/common.sh"

BENCH="${1:?Usage: start_runcpu.sh <bench> <out_log> [size] [config]}"
OUT_LOG="${2:-/workspace/results/spec.log}"
SIZE="${3:-test}"
CONFIG="${4:-${SPEC_CONFIG:-my_test.cfg}}"
COPIES="${SPEC_COPIES:-1}"

log "Starting SPEC CPU: bench=${BENCH}, size=${SIZE}, config=${CONFIG}, copies=${COPIES}"

docker exec -d "${OFFLINE_CONTAINER}" bash -lc "
cd /workspace/cpu2017
mkdir -p \$(dirname '${OUT_LOG}')

cat > /tmp/run_spec_loop.sh <<'EOS'
#!/usr/bin/env bash
set -u

cd /workspace/cpu2017
source shrc

BENCH='${BENCH}'
SIZE='${SIZE}'
CONFIG='${CONFIG}'
COPIES='${COPIES}'
OUT_LOG='${OUT_LOG}'

echo \"[spec] bench=\${BENCH}, size=\${SIZE}, config=\${CONFIG}, copies=\${COPIES}\" >> \"\${OUT_LOG}\"
echo \"[spec] wrapper start_time=\$(date '+%F %T')\" >> \"\${OUT_LOG}\"

while true; do
  echo \"[spec] run begin \$(date '+%F %T')\" >> \"\${OUT_LOG}\"
  runcpu --config=\"\${CONFIG}\" --size=\"\${SIZE}\" --iterations=1 --copies=\"\${COPIES}\" \"\${BENCH}\" >> \"\${OUT_LOG}\" 2>&1
  ec=\$?
  echo \"[spec] run end \$(date '+%F %T') exit_code=\${ec}\" >> \"\${OUT_LOG}\"
  sleep 1
done
EOS

chmod +x /tmp/run_spec_loop.sh
nohup /tmp/run_spec_loop.sh >> '${OUT_LOG}' 2>&1 &

echo \$! > /tmp/spec_runcpu_wrapper.pid
echo '[spec] wrapper pid:' >> '${OUT_LOG}'
cat /tmp/spec_runcpu_wrapper.pid >> '${OUT_LOG}'
ps -ef | grep -E 'run_spec_loop|runcpu|${BENCH}' | grep -v grep >> '${OUT_LOG}' || true
"
