#!/usr/bin/env bash

cleanup_taobench() {
  echo "[cleanup] stopping TaoBench related processes..."

  docker exec clab-server pkill -9 -f tao 2>/dev/null || true
  docker exec clab-server pkill -9 -f benchpress 2>/dev/null || true
  docker exec clab-server pkill -9 -f memcached 2>/dev/null || true

  docker exec clab-loadgen pkill -9 -f tao 2>/dev/null || true
  docker exec clab-loadgen pkill -9 -f benchpress 2>/dev/null || true

  pkill -f "mpstat" 2>/dev/null || true
  pkill -f "pidstat" 2>/dev/null || true
  pkill -f "vmstat" 2>/dev/null || true
  pkill -f "iostat" 2>/dev/null || true
}

cleanup_offline() {
  echo "[cleanup] stopping offline workloads..."

  docker exec clab-offline pkill -9 -f 'memCap' 2>/dev/null || true
  docker exec clab-offline pkill -9 -f 'memBw' 2>/dev/null || true
  docker exec clab-offline pkill -9 -f './src/cpu' 2>/dev/null || true
  docker exec clab-offline pkill -9 -f '/workspace/iBench/src/cpu' 2>/dev/null || true
  docker exec clab-offline pkill -9 -f 'iperf3' 2>/dev/null || true
  docker exec clab-offline pkill -9 -f 'stress' 2>/dev/null || true

  # For zombie/defunct processes, killing is not enough; remove the container.
  docker rm -f clab-offline 2>/dev/null || true

  pkill -f "perf stat" 2>/dev/null || true
}
