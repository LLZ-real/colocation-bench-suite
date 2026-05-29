# Stage 1 第一阶段数据分析 & 后续计划

## 数据来源

| placement | 条件数 | baseline 漂移 | 路径 |
|---|---|---|---|
| same_numa | 45 (+6 baseline) | max 0.23% | `stage1_sail3090_ibench_same_numa_20260529_082831` |
| cross_numa | 45 (+6 baseline) | max 0.50% | `stage1_sail3090_ibench_cross_numa_20260529_121458` |
| same_smt | 45 (+6 baseline) | max 0.88% | `stage1_sail3090_ibench_same_smt_20260529_160218` |

**结论**：实验质量优秀，baseline 漂移全部 <1%。

---

## 关键发现

### 发现 1：worker 数量完全主导退化，intensity 几乎无影响

| 对比 | Δ(worker 1→8) | Δ(intensity 30→90) max |
|---|---|---|
| same_numa membw | +9.7pp | +1.5pp |
| same_numa l3 | +39.4pp | +1.4pp |
| same_smt membw | +19.6pp | +1.7pp |
| same_smt l3 | +53.5pp | +1.8pp |

**intensity 差异 100% 在 measurement noise 范围内（<2pp）→ 可以全砍，每种 worker 只保留一个中间值（arg=60）。**

### 发现 2：ibench_cpu 完全可以跳过

| placement | cpu 退化 | 有效吗 |
|---|---|---|
| same_numa | QPS **高于** baseline（负退化） | 零影响 |
| cross_numa | QPS **高于** baseline | 零影响 |
| same_smt | +3-5% | 有微弱影响但 worker 数不敏感（w1=3.5%, w8=4.8%） |

**same_numa / cross_numa 下全部砍掉。same_smt 保留 1 个条件（cpu_w4_a60）作为验证。**

### 发现 3：退化谱系缺口

```
same_numa:
  [0%] [3][5] [9]  ...............  [25][33][39]
        ^^^^^^^^^ 已覆盖           ^^^^^^^^^^^^^
                ↑ gap: 11-20% 完全空白

cross_numa:
  [0%] [1][4]  .........  [16][23][28]
        ^^^^^^ 已覆盖    ^^^^^^^^^^^^^
              ↑ gap: 6-15% 空白

same_smt:
  [3][5] [9][15][21]  [31]  [44][55]
   ^^^^^^^^^^^^^^^^  ^^^^  ^^^^^^^^
   ↑ cpu+membw 覆盖  ↑ l3  ↑ l3 w8 极端
   gap: 16-20%, 26-30%, 36-40%
```

**核心缺口**：10-20% 退化区间，三个 placement 全部空白。这正好是 SPEC 内存密集型 benchmark 的预期位置。

### 发现 4：放置效应规律

| 关系 | 退化比 |
|---|---|
| same_smt / same_numa | **~2×** |
| cross_numa / same_numa | **~0.4×** |

非常稳定的比例，在 membw 和 l3 上一致。说明不同放置之间的退化可以通过同一个模型学习（placement 作为 categorical feature）。

---

## 后续数据收集计划

### 原则

1. **iBench 已完成使命**——提供了清晰的校准曲线（w2→w4→w6→w8 在每个 placement 下的退化梯度）。不再需要更多 iBench 条件。
2. **SPEC 用来填缺口**——选择能在 10-20% 区间产生退化的 benchmark，以及能在 same_smt 下产生独特指纹的 benchmark。
3. **砍掉冗余**——intensity 维度全部砍，cpu 全部砍，w1 全部砍。

### Phase 2：SPEC 多样性矩阵

#### 选型逻辑

根据退化缺口，按优先级排列：

**P0 —— 填 10-20% gap（每个 placement 必跑）**：

| Benchmark | 资源指纹 | 预期 same_numa 退化 | 预期 cross_numa | 预期 same_smt |
|---|---|---|---|---|
| 505.mcf_r | 内存带宽杀手 | ~12-18% | ~5-8% | ~25-35% |
| 519.lbm_r | 内存带宽 + 浮点 | ~10-15% | ~4-7% | ~20-30% |
| 503.bwaves_r | 纯粹内存带宽 | ~15-20% | ~6-10% | ~25-35% |

**P1 —— 验证 same_smt 独特性**：

| Benchmark | 资源指纹 | 预期 same_smt 退化 |
|---|---|---|
| 502.gcc_r | 分支密集，BTB 污染 | ~15-25%（core 内分支预测器互冲） |
| 541.leela_r | 分支密集 + L1 压力 | ~12-20% |

**P2 —— 覆盖混合资源指纹**：

| Benchmark | 资源指纹 | 目的 |
|---|---|---|
| 508.namd_r | 计算密集 | 验证"低退化"区间的 PMU 多样性 |
| 525.x264_r | 混合型 | 中等压力，fill 中间区间 |
| 521.wrf_r | 混合型 | 中等压力 |

**P3 —— 填充剩余**：

| Benchmark | 目的 |
|---|---|
| 538.imagick_r | 极低退化区间 diversity |
| 511.povray_r | 同上 |
| 549.fotonik3d_r | 内存型，验证 mcf/lbm/bwaves 指纹差异 |
| 554.roms_r | 同上 |
| 523.xalancbmk_r | 分支型，same_smt 专属 |
| 531.deepsjeng_r | 同上 |
| 526.blender_r | 计算型 diversity |
| 527.cam4_r | 混合型 diversity |

#### copies

每个 benchmark 只跑 **c4 和 c8**（c1/c2 压力太小，数据已覆盖）。

#### 强度

全部 arg=60（单值，已确认 intensity 无效）。

### Phase 3：混合负载（每个 placement 6 个）

从 iBench 数据中选代表性的部分负载组合：

```
membw_w4 + l3_w4           (双重共享资源压力)
membw_w4 + cpu_w4          (内存 + 纯计算，SMT 下 CPU 可能放大 mem 干扰)
l3_w4 + cpu_w4             (L3 + 计算)
membw_w6 + l3_w4           (非对称压力)
membw_w4 + l3_w4 + cpu_w4  (三维)
membw_w8 + l3_w8           (极限对称)
```

目的：验证 Pythia 亚线性叠加假设。8 个混合条件 × 3 placements = 24 条件。

### 条件数统计

| 类别 | per placement | ×3 placements | 备注 |
|---|---|---|---|
| iBench 保底 | 6 | 18 | membw w4/w6/w8 + l3 w4/w6/w8（arg=60）+ cpu_w4（仅 same_smt） |
| SPEC P0+P1 | 5 | 15 | mcf, lbm, bwaves × c4/c8 + gcc, leela × c4/c8 |
| SPEC P2+P3 | 11 | 33 | 其余 benchmark × c4/c8 |
| 混合负载 | 6 | 18 | |
| baseline | 5 | 15 | |
| **合计** | | **~99** | Per placement: ~33 条件 |

### 时间估算

Per placement (~33 条件)：
- Server bootstrap + prewarm: ~50 min
- SPEC 条件（16 × ~3.5 min）：~56 min
- iBench 条件（6 × ~3 min）：~18 min
- 混合负载（6 × ~3 min）：~18 min
- Baseline checkpoints（~5 × ~3 min）：~15 min
- **每个 placement ~2.6h，3 个 ~8h**

### 执行顺序

```
1. same_numa SPEC P0 (mcf, lbm, bwaves, c4/c8)  ← 先验证退化位置
2. same_numa SPEC P1+P2+P3
3. same_numa 混合负载
4. cross_numa 同上顺序
5. same_smt 同上顺序
```

如果 P0 的 3 个 benchmark 在 same_numa 下退化与预期一致（10-20%），继续推进。如果偏差大则调整计划。
