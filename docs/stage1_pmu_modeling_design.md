# Stage 1-B：PMU 采集设计（v5 — 基于调试经验修订）

## 0. Stage 1-A 完成状态

| 数据 | 条件数 | 退化范围 |
|---|---|---|
| iBench（三放置完整） | 135 | -2% ~ +55% |
| SPEC same_numa | 32 | -2% ~ +17% |
| SPEC cross_numa | 6 | -0.3% ~ +8% |
| SPEC same_smt | 4 | +2% ~ +26% |

Stage 1-B 候选矩阵：`docs/results/stage1_stageB_matrix.csv`（34 条件，涵盖 4 种资源维度、3 个放置）。

---

## 1. 核心目标

对每个 `(placement, condition)` 采集**系统级 PMU 指标**，记录离线负载在 TaoBench 满载环境下的微架构行为特征。

模型输入 X = PMU 特征向量，输出 y = Stage 1-A 的 QPS 退化 / P99 膨胀。

---

## 2. 调试教训：Stage 1-B 脚本的 5 个关键问题

| # | 问题 | 根因 | 解决方案 |
|---|---|---|---|
| 1 | perf 产出 0 行数据 | `kill` 杀 perf 导致缓冲区未刷新 | **不用 kill**，让 perf 自然退出：`perf stat ... sleep N` |
| 2 | 事件名不存在 | `l2_rqsts.miss` 不存在（正确名 `l2_rqsts.all_demand_miss`） | 用 `LANG=C perf list` 校验每个事件，不可用则降级 |
| 3 | sudo 不可用 | `perf_event_paranoid=4` 要求 root | 预先配置 `NOPASSWD: /usr/bin/perf` |
| 4 | PID 捕获时序 | 先启 perf 后启负载 → 抓不到 PID | 先启负载，等进程出现，再启 perf |
| 5 | log() 到 stdout 污染 $() 捕获 | tee 写 stdout 混入返回值 | log 写 stderr + 文件 |

---

## 3. 简化方案：采集 QPS + PMU 同一次跑

**原设计**：Stage 1-A（干净 QPS）+ Stage 1-B（PMU）分开跑，避免 perf 扰动 QPS。

**修订**：系统级 `perf stat` 只是**被动读取 PMU 寄存器**，不 attach 任何进程，不采样堆栈。在 60s + 900 clients 的测量尺度上，开销 << 0.5%，远小于测量噪声本身。分开跑徒增一倍的实验时间和时序对齐复杂度。

**新方案：在 Stage 1-B 中同时采集 QPS/P99。** Models 用同一跑里的 PMU 作为 X、QPS/P99 作为 y，时间严格对齐，无时序偏差。

---

## 4. Perf 采集方法

### 4.1 启动方式（自然退出，无需 kill）

```bash
# perf 以 sleep 为 workload，到时间自然退出，保证缓冲区落盘
sudo -n perf stat -I 1000 -x, -e "${PMU_EVENTS}" -a \
  sleep "${PERF_DURATION}" \
  > "${pmu_dir}/host_perf.csv" 2>"${pmu_dir}/host_perf_stderr.log" &
```

`PERF_DURATION` = `CLIENT_WARMUP_TIME + CLIENT_TEST_TIME + 60`（覆盖客户端完整运行窗口 + 余量）。

### 4.2 事件列表

所有放置共用以下 13 个通用事件（已验证在本机有效）：

```
cycles, instructions,
L1-dcache-loads, L1-dcache-load-misses,
LLC-loads, LLC-load-misses,
branch-instructions, branch-misses,
cache-references, cache-misses,
context-switches, cpu-migrations,
dTLB-loads, dTLB-load-misses
```

plus（在本机已验证有效）：

```
l2_rqsts.all_demand_miss, l2_rqsts.all_demand_data_rd,
offcore_requests.all_data_rd, offcore_requests.demand_data_rd
```

**共 17 个事件。**

same_smt 额外尝试 TMA Level 1（若 `_perf_event_ok` 通过，否则跳过）：

```
cpu/event=0x9c,umask=0x01,name=FRONTEND_BOUND/,
cpu/event=0xc2,umask=0x02,name=RETIRING/,
cpu/event=0x0d,umask=0x03,name=BAD_SPECULATION/,
cpu/event=0xa3,umask=0x04,name=BACKEND_BOUND/
```

### 4.3 派生特征

| 原始 Counter | 派生特征 |
|---|---|
| instructions / cycles | IPC |
| LLC-load-misses / LLC-loads | LLC miss rate |
| branch-misses / branch-instructions | Branch miss rate |
| L1-dcache-load-misses / L1-dcache-loads | L1 dcache miss rate |
| l2_rqsts.all_demand_miss / l2_rqsts.all_demand_data_rd | L2 miss rate |
| context-switches / time | context switches/sec |
| TMA Frontend/Backend/BadSpec ratio | 微架构瓶颈分析 |

---

## 5. 实验流程（每个条件）

```
1. 创建 offline 容器，验证绑核
2. 启动离线负载（iBench 或 SPEC），等待进程出现（最多 60s）
3. 启动 perf（后台，sleep PERF_DURATION 后自然退出）
4. 启动 TaoBench client（warmup + test，~180s）
5. client 完成 → 采集 QPS/P99（同 Stage 1-A）
6. 等待 perf 自然退出 → CSV 落地，验证行数 > 0
7. 停止离线负载，冷却
8. 写入 summary.csv（QPS + P99 + PMU CSV 路径）
```

---

## 6. 前置条件

```bash
# 一次性配置
echo 'lilinzhen ALL=(ALL) NOPASSWD: /usr/bin/perf' | sudo tee /etc/sudoers.d/perf-nopasswd

# 验证
LANG=C sudo -n perf stat -I 1000 -e cycles,instructions sleep 1 2>&1 | head -3
# 应看到类似输出：
#      1.000123     123456      cycles
#      1.000123      56789      instructions
```

---

## 7. Stage 1-B 矩阵

使用 `docs/results/stage1_stageB_matrix.csv`（34 条件）。每个 placement 11-12 条件：

```
same_numa:  membw w4/w6/w8, l3 w2/w4/w6/w8, lbm c8, mcf c8, gcc c8, bwaves c8
cross_numa: 同上
same_smt:   同上 + cpu w8
```

---

## 8. 时间估算

每个条件 ~4.5 min（90s 稳定 + 180s client + perf 余量 + 开销）。每个 placement ~55 min，3 个 ~3h。加上 server 预热每次 ~50 min，总计 **~5.5h**。

---

## 9. 脚本实现状态

`experiments/data_collection_experiment/stage1_sweep_pmu.sh` 已有骨架，需要重写 perf 启动逻辑：
- 用 `sleep $PERF_DURATION` 替代 kill
- 不再用连续 client 模式
- 改为每个条件独立跑 client + perf
- 同时采集 QPS/P99

这个重写应在 smoke 测试通过后进行。
