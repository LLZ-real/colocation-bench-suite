# Week 1: TaoBench Baseline Automation

## Goal

Automate TaoBench baseline curve collection with Docker cpuset isolation and host-side perf stat collection.

## Current setup

- Online server container: clab-server
- Load generator container: clab-loadgen
- Docker image: clab-compute:latest
- Server workload: DCPerf TaoBench autoscale
- Client workload: DCPerf TaoBench custom client
- PMU collection: host-side perf stat attached to tao_bench_server host PID

## Default placement

Server cores:

```text
0,2,4,6,8,10,12,14
```
## Loadgen cores:

1,3,5,7,9,11,13,15,17,19,21,23,25,27,29,31
Run command

## Short run:

CLIENT_LIST="100 300 500" CLIENT_TEST_TIME=60 bash experiments/taobench_baseline_curve.sh

Full baseline curve:

CLIENT_LIST="100 200 300 400 500 600 700 800" CLIENT_TEST_TIME=60 bash experiments/taobench_baseline_curve.sh
Output

## Each run creates:

results/cbs/<timestamp>_taobench_baseline_curve/
  config.env
  machine_topology/
  logs/server.log
  raw/client_<clients>.log
  raw/perf_client_<clients>.log
  parsed/client_<clients>.json
  parsed/perf_client_<clients>.csv
  summary.csv
## Metrics

Online metrics:

QPS
Gets P99 latency

PMU metrics:

IPC
cache miss rate
branch miss rate
context switches
First successful PMU-enabled run

Run directory:

/home/lilinzhen/colocate_lab/results/cbs/20260505_231918_taobench_baseline_curve

Summary:

clients_per_threadQPSP99 msIPCcache miss rate
10021998.2653.5030.94990.0472
30024512.66161.7911.03080.0588
50028639.11243.7111.10710.0602
Notes

The current run shows lower QPS than earlier manual runs. Potential causes include perf overhead, insufficient warmup, system noise, or run-to-run variation. Repeat runs are required before using these numbers as stable baseline.

## Baseline curve with host-side perf

Run directory:

```text
/home/lilinzhen/colocate_lab/results/cbs/20260505_234755_taobench_baseline_curve
```

## Data Table

| clients_per_thread | QPS       | P99 ms   | IPC   | cache miss rate | branch miss rate | context switches |
|--------------------|-----------|----------|-------|----------------|------------------|------------------|
| 100                | 21872.17  | 53.247   | 0.9413 | 0.0472          | 0.0164           | 91863445         |
| 200                | 24293.21  | 109.055  | 0.9777 | 0.0522          | 0.0165           | 86233226         |
| 300                | 28009.19  | 148.479  | 1.0279 | 0.0551          | 0.0152           | 85323764         |
| 400                | 32581.86  | 191.487  | 1.0478 | 0.0649          | 0.0141           | 80540313         |
| 500                | 39813.21  | 203.775  | 1.0723 | 0.0642          | 0.0141           | 78073646         |
| 600                | 50585.29  | 203.775  | 1.1172 | 0.0808          | 0.0131           | 74844166         |
| 700                | 70136.77  | 181.247  | 1.1171 | 0.0970          | 0.0131           | 71999180         |
| 800                | 102102.90 | 144.383  | 1.1364 | 0.1453          | 0.0120           | 66989181         |

## Observations

- **QPS** increases monotonically from 21.9k to 102.1k.
- **P99 latency** increases until around `clients_per_thread = 500/600`, then decreases at higher client pressure.
- **IPC** increases from 0.94 to 1.13 as request pressure increases.
- **Cache miss rate** increases substantially from 4.7% to 14.5%.
- **Branch miss rate** decreases slightly as load increases.
- **Context switches** decrease as load increases.

## Tentative Week 2 Online Load Choice

- Use **`clients_per_thread = 500`** as the primary fixed online load for initial offline interference experiments.
- Also keep **`clients_per_thread = 700`** as a high-throughput secondary point.

## Final Week 1 baseline decision

A no-perf control experiment confirms that host-side `perf stat` significantly perturbs TaoBench measured performance.

Command:

```bash
ENABLE_PERF=0 \
SERVER_BOOTSTRAP_WAIT=180 \
PREWARM_ROUNDS=8 \
PREWARM_CLIENTS=900 \
PREWARM_TEST_TIME=60 \
CLIENT_LIST="900 900 900" \
CLIENT_TEST_TIME=60 \
bash experiments/taobench_baseline_curve.sh
Run directory:

/home/lilinzhen/colocate_lab/results/cbs/20260506_153919_taobench_baseline_curve

Prewarm converged at round 7:

roundQPSP99 ms
6167457.72109.055
7166761.14108.031

Measured results without perf:

idxclients_per_threadQPSP99 ms
1900166151.0198.303
2900166402.0598.303
3900166070.1698.815

Decision:

Use clients_per_thread=900 as the primary online load for Week 2.
Use request-driven prewarm before all measured runs.
Use ENABLE_PERF=0 for performance experiments.
Run PMU profiling separately from performance measurement.
