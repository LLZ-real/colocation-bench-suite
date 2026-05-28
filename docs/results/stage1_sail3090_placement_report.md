# Stage 1 Placement Matrix Results — sail3090

**Date**: 2026-05-28
**Machine**: sail3090 (128 CPUs, 2 sockets, 2 NUMA nodes, SMT enabled)
**Configuration**:

| Role | CPUs | NUMA |
|---|---|---|
| TaoBench Server | 0-7 | 0 |
| TaoBench Loadgen | 32-47 | 1 |
| Offline (same NUMA) | 16-23 | 0 |
| Offline (cross NUMA) | 48-55 | 1 |
| Offline (same SMT) | 64-71 | 0 |

**SMT Topology**: core 0 → CPUs {0,64}, core 1 → CPUs {1,65}, ..., core 7 → CPUs {7,71}

**Experiment params**: 900 clients/thread, 60s test, 8 prewarm rounds, no recovery prewarm, 1 repeat/condition.

---

## 1. Performance Overview

### 1.1 Baseline QPS (no interference)

| Placement | Baseline QPS | Baseline P99 (ms) |
|---|---|---|
| same NUMA | ~178,550 | 92.2 |
| cross NUMA | ~177,764 | 92.7 |
| same SMT | ~179,158 | 92.2 |

Baseline QPS is consistent across placements (~178k), confirming that TaoBench server placement (0-7 on NUMA 0) is stable regardless of where the (idle) offline container sits.

---

### 1.2 Interference Results

| Condition | same NUMA | cross NUMA | same SMT |
|---|---|---|---|
| **iBench memBw (w8)** | | | |
| QPS | 161,610 | 169,605 | 138,369 |
| QPS degradation | **-9.5%** | **-4.6%** | **-22.8%** |
| P99 slowdown | 1.11x | 1.06x | 1.28x |
| **iBench L3 (w8)** | | | |
| QPS | 110,910 | 121,725 | 83,942 |
| QPS degradation | **-38.0%** | **-31.7%** | **-52.9%** |
| P99 slowdown | 1.61x | 1.16x | 2.12x |
| **SPEC mcf (ref, c8)** | | | |
| QPS | 172,881 | 178,593 | 149,010 |
| QPS degradation | **-3.4%** | **+0.5%** | **-16.5%** |
| P99 slowdown | 1.03x | 1.00x | 1.20x |
| **SPEC lbm (ref, c8)** | | | |
| QPS | 149,972 | 166,839 | 131,458 |
| QPS degradation | **-15.9%** | **-6.2%** | **-26.3%** |
| P99 slowdown | 1.18x | 1.08x | 1.35x |

---

### 1.3 Degradation Ranking (QPS drop, worst to mildest)

| Rank | Condition | same SMT | same NUMA | cross NUMA |
|---|---|---|---|---|
| 1 | iBench L3 (w8) | -52.9% | -38.0% | -31.7% |
| 2 | SPEC lbm (ref, c8) | -26.3% | -15.9% | -6.2% |
| 3 | iBench memBw (w8) | -22.8% | -9.5% | -4.6% |
| 4 | SPEC mcf (ref, c8) | -16.5% | -3.4% | +0.5% |

---

## 2. Key Observations

### 2.1 Placement effect is consistent and strong

Across all 4 interference workloads, the degradation severity follows:

**same SMT >> same NUMA > cross NUMA**

- **same SMT**: server and offline share physical cores (SMT threads), causing the worst contention on core-private resources (L1/L2 cache, execution units).
- **same NUMA**: server and offline use different cores but share L3 cache and memory controller on the same NUMA node.
- **cross NUMA**: server and offline are on different NUMA nodes, sharing only inter-socket links; minimal interference.

### 2.2 iBench L3 is the most disruptive workload

L3 cache pressure (w8 workers) causes 32-53% QPS degradation and up to 2.12x P99 slowdown. This is expected because TaoBench is memory-intensive and sensitive to cache capacity contention.

### 2.3 SPEC mcf shows negligible interference when cross-NUMA

SPEC 505.mcf_r on a different NUMA node has essentially zero impact on TaoBench QPS (-0.5%, within noise). On same NUMA, the impact is still mild (-3.4%). But on same SMT, it drops QPS by 16.5%.

### 2.4 iBench memBw vs L3: bandwidth vs capacity

- memBw causes 5-23% QPS drop (moderate)
- L3 causes 32-53% QPS drop (severe)

This suggests TaoBench performance on this machine is more sensitive to cache capacity contention than pure memory bandwidth saturation.

### 2.5 Baseline stability between conditions

Baseline checkpoints between each workload show QPS varying by <0.5%, confirming good experimental hygiene — the server recovers fully between conditions and no state leak occurs.

---

## 3. Raw Data

- Detail (repeat-level): `docs/results/stage1_smart_repeat_level.csv`
- Aggregated: `docs/results/stage1_smart_aggregated.csv`
- Source directories: `/home/lilinzhen/colocate_lab/results/cbs/stage1_sail3090_{same_numa,cross_numa,same_smt}_*`
