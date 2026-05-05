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
clients_per_threadQPSP99 msIPCcache miss ratebranch miss ratecontext switches
10021872.1753.2470.94130.04720.016491863445
20024293.21109.0550.97770.05220.016586233226
30028009.19148.4791.02790.05510.015285323764
40032581.86191.4871.04780.06490.014180540313
50039813.21203.7751.07230.06420.014178073646
60050585.29203.7751.11720.08080.013174844166
70070136.77181.2471.11710.09700.013171999180
800102102.90144.3831.13640.14530.012066989181
Observations
QPS increases monotonically from 21.9k to 102.1k.
P99 latency increases until around clients_per_thread=500/600, then decreases at higher client pressure.
IPC increases from 0.94 to 1.13 as request pressure increases.
Cache miss rate increases substantially from 4.7% to 14.5%.
Branch miss rate decreases slightly as load increases.
Context switches decrease as load increases.
Tentative Week 2 online load choice

Use clients_per_thread=500 as the primary fixed online load for initial offline interference experiments.

Also keep clients_per_thread=700 as a high-throughput secondary point.
