# Stage 1 数据收集：PMU 建模实验设计（v3）

## 0. 数据质量诊断

当前 same_numa + cross_numa 数据：退化分布过于集中。

```
same_numa 退化分布:
  0%     ████████████████████████████████  (cpu 全部 + membw w1-w2 + l3 w1)
  ~3-5%  ████████                          (membw w4-w6)
  ~9%    ████                              (membw w8)
  ~25%   ████                              (l3 w4)
  ~33%   ████                              (l3 w6)
  ~39%   ████                              (l3 w8)
```

模型只有 5-6 个有效退化水平，25-39% 之间有断层。Random Forest 只能死记硬背，无法泛化。

---

## 1. 理论框架

### 1.1 Bubble-Up（MICRO'11）：解耦敏感性曲线

压力值 P（干扰源）× 敏感度 S（宿主对 P 的响应）= 性能退化。

- S（敏感度）：由 placement 决定。same_smt 对 core-private 资源敏感，same_numa 对 L3/内存敏感
- P（压力值）：由离线负载的 PMU 指标量化为多维向量（不再是单一的"内存带宽"或"LLC miss"）
- 模型学习 f(placement, PMU_vector) → degradation

### 1.2 SMiTe（MICRO'14）：多维资源解耦

SMT 内部资源冲突是多维且互不相关的（对 L1 敏感的应用不一定对浮点端口敏感）。解决方案：

- 分别压每个硬件资源维度（Port 0/1/5、L1、L2、L3），逐资源测敏感度和破坏力
- 多维回归综合预测

### 1.3 Pythia（Middleware'18）：多任务亚线性叠加

多个 Batch 共存时相互干扰，导致对 LS 的实际总压力**小于**简单求和。需要稀疏采样多任务组合来拟合亚线性权重。

---

## 2. Ruler 缺失与多重共线性规避

**风险**：SMiTe 用专用 Ruler 微基准逐资源解耦。我们跳过了这一步，靠 SPEC 的"自然 PMU 指纹"替代。如果所有 SPEC benchmark 的 PMU 特征高度相关（LLC miss 总是伴随高内存带宽），模型将无法区分退化来源。

### 2.1 任务 0：SPEC PMU 预筛（必须最先做）

**不需要 TaoBench 参与，~30 分钟**。

从 4 个资源类别中各选 2 个 benchmark，共 8 个：

| 类别 | Benchmark | 预计资源指纹 |
|---|---|---|
| 内存 | 505.mcf_r, 519.lbm_r | 高 LLC miss + 高内存带宽 |
| 计算 | 508.namd_r, 538.imagick_r | 高 IPC + 低 cache miss |
| 分支 | 502.gcc_r, 541.leela_r | 高 branch miss + 中等 cache miss |
| 混合 | 525.x264_r, 521.wrf_r | 中等各维度 |

流程：

```
for each benchmark:
  1. docker run --cpuset-cpus=16-23 --cpuset-mems=0 ... sleep infinity
  2. docker exec -d ... runcpu --copies=8 --size=ref <bench>
  3. sleep 30 (等越过初始化)
  4. perf stat -I 1000 -e <events> ... -p <pid> sleep 120
  5. docker rm -f <container>
```

对采集到的 8 × 120s PMU 数据，执行：

```python
import pandas as pd
# 提取每个 benchmark 的均值 PMU 向量 (LLC_miss_rate, Mem_BW, IPC, branch_miss_rate, ...)
corr = df[pmu_columns].corr()
# 如果某两个关键特征的 |r| > 0.85 → 多重共线性
```

### 2.2 共线性缓解策略

| 层面 | 方法 |
|---|---|
| 特征选择 | 用**置换重要性（Permutation Importance）**替代 Gini 重要性（MDI）。MDI 在共线特征间随机分配重要性，Permutation Importance 更稳健 |
| 特征归因 | 训练后计算 **SHAP 值**，识别每个预测中哪些物理资源贡献最大 |
| 降维 | 如果共线性无法消除（r > 0.9），对高相关特征组做 **ElasticNet 正则化**或前置 **PCA** 降低维度 |
| 数据补充 | 手动写 2-3 个简单 Ruler 微基准：一个纯分支压力（while 循环 + 随机跳转）、一个纯 TLB 压力（大页随机访问），填补 SPEC 覆盖不到的盲区 |

---

## 3. SMT 下的 PMU 事件集

### 3.1 核内 Pipeline 事件 vs Top-down TMA

`uops_dispatched_port` 等细粒度端口事件在不同 CPU 微架构（Skylake / IceLake / Sapphire Rapids）之间名称不兼容，且可能在虚拟化环境或非 root 场景被禁用。

**主方案**：先尝试采集核内端口事件：

```
perf stat -I 1000 -x, \
  -e cycles,instructions \
  -e L1-dcache-loads,L1-dcache-load-misses \
  -e L1-icache-loads,L1-icache-load-misses \
  -e l2_rqsts.miss,l2_rqsts.all_demand_data_rd \
  -e LLC-loads,LLC-load-misses \
  -e dTLB-loads,dTLB-load-misses,iTLB-loads,iTLB-load-misses \
  -e branch-instructions,branch-misses \
  -e uops_issued.any,uops_retired.retire_slots \
  -e resource_stalls.any \
  -e context-switches,cpu-migrations
```

**若端口事件不可用，立即切换到 Top-down TMA Level 1**（标准且稳定）：

```
perf stat -I 1000 -x, \
  -e cycles,instructions \
  -e cpu/event=0x9c,umask=0x01,name=IDQ_UOPS_NOT_DELIVERED.CORE/     # Frontend Bound
  -e cpu/event=0xc2,umask=0x02,name=UOPS_RETIRED.RETIRE_SLOTS/       # Retiring
  -e cpu/event=0x0d,umask=0x03,name=INT_MISC.RECOVERY_CYCLES/        # Bad Speculation
  -e cpu/event=0xa3,umask=0x04,name=CYCLE_ACTIVITY.STALLS_TOTAL/     # Backend Bound
  -e L1-dcache-loads,L1-dcache-load-misses \
  -e LLC-loads,LLC-load-misses \
  -e branch-instructions,branch-misses \
  -e context-switches,cpu-migrations
```

这 4 个 TMA 指标在 Haswell 到 Sapphire Rapids 所有代际都稳定有效：

| 事件 | 含义 | SMT 下的意义 |
|---|---|---|
| `IDQ_UOPS_NOT_DELIVERED.CORE` | 前端停顿 | 两线程争抢取指/解码带宽 |
| `UOPS_RETIRED.RETIRE_SLOTS` | 正常退役率 | SMT 下被压缩的退休槽位 |
| `INT_MISC.RECOVERY_CYCLES` | 分支预测失败恢复 | 两线程互相污染分支预测器 |
| `CYCLE_ACTIVITY.STALLS_TOTAL` | 后端停顿 | 执行端口、L1/L2 争抢的综合反映 |

### 3.2 same_numa / cross_numa 事件集

侧重 Uncore 和内存系统：

```
perf stat -I 1000 -x, \
  -e cycles,instructions \
  -e L1-dcache-loads,L1-dcache-load-misses \
  -e LLC-loads,LLC-load-misses \
  -e dTLB-loads,dTLB-load-misses \
  -e branch-instructions,branch-misses \
  -e cache-references,cache-misses \
  -e offcore_requests.all_data_rd,offcore_requests.demand_data_rd \
  -e l2_rqsts.miss,l2_rqsts.all_demand_data_rd \
  -e context-switches,cpu-migrations,page-faults
```

cross_numa 额外加（如果硬件支持）：
```
  -e uncore_imc/data_reads/,uncore_imc/data_writes/
  -e offcore_response.demand_data_rd.any_response
```

---

## 4. SPEC 运行开销控制

SPEC CPU 2017 的 `ref` 数据集一次完整运行可能需要 30 分钟到数小时。但我们只需要 60-120s 的稳态采样窗口。

### 4.1 策略

1. **不等待 SPEC 运行结束**。启动 SPEC 后，等待越过初始化阶段（30s），然后在 60-120s 采样窗口内采集 QPS/PMU
2. **采样结束后直接 `pkill` 或 `docker rm -f` 终止**，不等待自然结束
3. **考虑使用 `test` 或 `train` 规模数据集**以加快冷启动。只要保证其在采样窗口内处于活跃态（CPU 100%）即可。如果 `test` 数据集的资源特征与 `ref` 相同（内存/cache 压力比例一致），可以替代；否则保留 `ref`
4. **SPEC 的 `runcpu` 启动时有 ~15-30s 的 build/setup 阶段**，这段时间 CPU 利用率低，不算稳态。`OFFLINE_STABILIZE_WAIT` 需要设为 60-90s

### 4.2 实现

`start_runcpu.sh` 当前是无限循环。不需要改动——它启动后越过 setup 阶段自然进入稳定态，采样完直接 `cleanup_offline → docker rm -f clab-offline` 杀掉。

---

## 5. 混合负载的物理隔离

### 5.1 问题

如果 `membw_w4` 和 `l3_w4` 的 8 个 worker 挤在相同的物理核心上，它们会首先互相打架（core-private 资源争抢），无法向 L3/内存施加预期强度的压力。

### 5.2 交错绑定策略

`OFFLINE_CPUSET` 为 16-23（8 核），混合负载时按子类型交错分配：

```
membw_w4 → CPU 16, 18, 20, 22  (偶数核)
l3_w4    → CPU 17, 19, 21, 23  (奇数核)
```

在 `start_offline_workload()` 的 `mixed` case 中实现。子任务的 cpuset 通过 `taskset -c` 或 docker exec 中显式指定。

### 5.3 矩阵格式

混合负载条件在 CSV 中用 `offline_type=mixed`，`offline_param` 为 JSON：

```csv
mixed_membw4_l3w4_same_core,mixed,"[{\"t\":\"ibench_membw\",\"w\":4,\"a\":60},{\"t\":\"ibench_l3\",\"w\":4,\"a\":60}]",,same_core
mixed_membw4_l3w4_interleaved,mixed,"[{\"t\":\"ibench_membw\",\"w\":4,\"a\":60},{\"t\":\"ibench_l3\",\"w\":4,\"a\":60}]",,interleaved
```

`offline_label` 区分"挤在同一核"vs"交错绑定"，用于分析物理隔离的影响。

### 5.4 混合负载条件清单（每个 placement ~6 个）

```
membw_w4 + l3_w4           (内存 + 缓存)
membw_w4 + cpu_w4          (内存 + 计算)
l3_w4 + cpu_w4             (缓存 + 计算)
membw_w6 + l3_w4           (非对称 w6/w4)
membw_w4 + l3_w4 + cpu_w4  (三维)
membw_w8 + l3_w8           (对称极限)
```

---

## 6. 优化后的负载矩阵

### 6.1 iBench 校准曲线（11 条件 per placement）

砍掉冗余 intensity 级别（只保留 arg=60），cpu 从 15 条件砍到 3：

| 类型 | Workers | 强度 | 条件数 |
|---|---|---|---|
| ibench_cpu | 2, 4, 8 | 60 | 3 |
| ibench_membw | 2, 4, 6, 8 | 60 | 4 |
| ibench_l3 | 2, 4, 6, 8 | 60 | 4 |

### 6.2 SPEC 多样性（42 条件 per placement）

**内存密集型**：503.bwaves_r(4,8), 505.mcf_r(4,8), 519.lbm_r(4,8), 549.fotonik3d_r(4), 554.roms_r(4) — 11 条件

**计算密集型**：508.namd_r(4,8), 511.povray_r(4,8), 538.imagick_r(4,8), 526.blender_r(4) — 10 条件

**分支密集型**：502.gcc_r(4,8), 541.leela_r(4,8), 523.xalancbmk_r(4), 531.deepsjeng_r(4) — 10 条件

**混合型**：525.x264_r(4,8), 521.wrf_r(4), 527.cam4_r(4) — 8 条件

**SPEC 合计**：39 条件

### 6.3 混合负载（6 条件 per placement）

见 5.4 节。

### 6.4 总计

每个 placement：11 + 39 + 6 = **56 条件**。3 placements = **168 条件**。

每个 placement ~6h。Stage 1-A 总计 ~18h，Stage 1-B ~12h。合计 ~30h。

---

## 7. 实验流程（4 个阶段）

### Phase 0：SPEC PMU 预筛（最先做，30 分钟）

- 8 个 SPEC benchmark × 120s PMU 采集，不需要 TaoBench
- 计算 Pearson 相关系数矩阵
- 若 r > 0.85 批量出现，补充 2-3 个 Ruler 微基准填补盲区
- 产出：确认 SPEC 的 PMU 指纹多样性足够

### Phase 1：iBench 校准曲线（11 条件 × 3 placements）

same_numa + cross_numa 已完成（完整 45 条件包含了这 11 条件子集）。same_smt 用 11 条件裁减矩阵快速跑完。

### Phase 2：SPEC 多样性（39 条件 × 3 placements）

每个 benchmark c4/c8，跳过 c1/c2。`OFFLINE_STABILIZE_WAIT=90s`（SPEC 初始化长）。

### Phase 3：混合负载（6 条件 × 3 placements）

验证亚线性叠加。交错绑定策略在脚本中实现。

### Phase 4：Stage 1-B PMU（全部 56 条件 × 3 placements）

perf 事件集按 placement 分化（3.1/3.2 节）。`OFFLINE_STABILIZE_WAIT=120s`（留足 PMU 稳态余量）。

---

## 8. 模型架构

### 8.1 输入输出

| | 内容 | 来源 |
|---|---|---|
| X | 离线负载 PMU 特征向量（per placement 不同的事件集） | Stage 1-B |
| y | QPS degradation % + P99 slowdown | Stage 1-A |
| 辅助 | placement (categorical) | env |

### 8.2 特征工程（按 placement 分层计算）

| 原始 counter | 派生特征 |
|---|---|
| instructions / cycles | **IPC** |
| LLC-load-misses / LLC-loads | **LLC miss rate** |
| branch-misses / branch-instructions | **Branch miss rate** |
| L1-dcache-load-misses / L1-dcache-loads | **L1 dcache miss rate** |
| offcore_requests / time | **Offcore requests/sec** |
| uncore_imc events / time | **Memory bandwidth (GB/s)** |

same_smt 额外派生：
| TMA 事件 | 派生 |
|---|---|
| IDQ_UOPS_NOT_DELIVERED / cycles | **Frontend bound ratio** |
| CYCLE_ACTIVITY.STALLS_TOTAL / cycles | **Backend bound ratio** |
| INT_MISC.RECOVERY_CYCLES / cycles | **Bad speculation ratio** |

### 8.3 验证策略

**按负载类型留出**：
- 训练：iBench 全部 + SPEC 内存 + 计算 + 混合负载
- 验证：SPEC 分支密集型 + 混合型
- 测试：完全未参与训练的 Ruler 微基准或新程序

### 8.4 模型选择

| 模型 | 适用性 |
|---|---|
| Random Forest + Permutation Importance | 首选，~180 个训练点，非线性能捕捉 |
| XGBoost + SHAP | 精度最优但要调参 |
| ElasticNet | 共线性严重时的降级方案 |

---

## 9. 脚本改动清单

| 改动 | 涉及文件 | 说明 |
|---|---|---|
| SPEC PMU 预筛脚本 | 新建 `tools/prefilter_spec_pmu.sh` | Phase 0，逐个跑 8 个 SPEC 采 PMU |
| PMU 相关性分析 | 新建 `tools/analyze_pmu_correlation.py` | 计算 Pearson r，输出共线性报告 |
| iBench 矩阵裁减 | `generate_stage1_matrix.py` | 只保留 arg=60，cpu 只保留 3 条件 |
| 混合负载支持 | `stage1_sweep_clean.sh` 的 `start_offline_workload()` | 新增 `mixed` case，解析 JSON，交错绑核 |
| 混合负载启动逻辑 | 新建 `offline/mixed/start_mixed.sh` | 解析 JSON 配置，`taskset` 子任务到指定核 |
| SPEC stabilize wait | `stage1_sweep_clean.sh` | 默认改 90s（SPEC 初始化长） |
| Stage 1-B PMU | 新建 `stage1_sweep_pmu.sh` | 按 PLACEMENT 选择不同 perf 事件集 |
| TMA 事件检测 | `stage1_sweep_pmu.sh` | 先 `perf list` 检测端口事件是否存在，不存在则降级到 TMA |

---

## 10. SPEC 运行时间预估

以 `test` 数据集为例（跳过 `ref` 的漫长运行）：

| benchmark | test 集单次运行 | 8 copies |
|---|---|---|
| 505.mcf_r | ~2 min | ~3 min |
| 519.lbm_r | ~1 min | ~2 min |
| 502.gcc_r | ~5 min | ~6 min |
| 大部分 rate benchmark | 1-3 min | 2-5 min |

**总耗时**：39 × ~3.5 min ≈ 2.3h per placement，加上 server 预热 ~50 min + iBench ~40 min + mixed ~30 min ≈ **4.5h per placement**。

建议 SPEC 用 `test` 数据集先跑一轮，验证 PMU 指纹与 `ref` 一致（同一个 benchmark 在 test vs ref 下 cache/branch/IOS 特征比例应相同）。如果一致则全部用 test；如果不一致则保留 ref 并为耗时长的 benchmark（gcc, xalancbmk）单独设 `OFFLINE_STABILIZE_WAIT=120s`。
