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
