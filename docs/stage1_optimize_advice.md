# 2. 优化建议与规避策略

## 2.1 针对"Ruler 缺失与多重共线性（Multicollinearity）"的规避方案

如果 SPEC 任务的 PMU 特征在某些维度上高度相关（例如 LLC miss 总是伴随着高内存带宽），模型在划分特征重要性时会产生混淆。

### 数据层面的验证（您的缓解策略）

您提出的"30分钟不带 TaoBench 的 SPEC 预筛跑"极其必要。在分析这 8 个 benchmark 的 PMU 时，建议计算它们的**皮尔逊相关系数矩阵（Pearson Correlation Matrix）**。

如果某两个关键特征（如 `LLC_miss_rate` 与 `Mem_BW`）的相关系数 **r > 0.85**，说明多重共线性严重。

### 模型与算法层面的对策

1. **不要直接使用随机森林默认的 Gini 重要性（Mean Decrease Impurity）**  
   因为当特征高度相关时，MDI 会严重低估其中一个特征的重要性，并将其随机分配。

2. **改用置换重要性（Permutation Importance）或 SHAP 值来评估特征**  
   SHAP 能更好地处理协同特征，客观反映各物理资源的真实贡献。

3. **若共线性无法消除**，可以在模型前置引入一个轻量级的 **PCA（主成分分析）** 或进行特征正则化（**ElasticNet 惩罚项**），合并高度相关的物理指标。

---

## 2.2 SMT 维度下的 PMU 事件集（Stage 3）微调

在 `same_smt` 场景下，直接监控特定的执行端口（如 `uops_dispatched_port`）在虚拟化环境、多核云平台或者不同代际的 CPU 上可能存在以下问题：

- **事件名称不兼容**：Intel 不同微架构（如 Skylake vs. IceLake vs. Sapphire Rapids）的端口映射事件常有变动。
- **权限限制**：非 root 容器或普通用户态下，某些特定核内 Port PMU 可能由于安全原因（如 side-channel 漏洞防护）被内核禁用。

### 优化方案（Top-down 替代方案）

如果遇到硬件端口事件采集受限，推荐使用 **Top-down（自顶向下）微架构分析法（TMA）Level 1 指标**作为核心替代。这些指标在主流现代 CPU 上非常标准且稳定：

- `IDQ_UOPS_NOT_DELIVERED.CORE`：Frontend Bound / 前端瓶颈
- `UOPS_RETIRED.RETIRE_SLOTS`：Retiring / 正常退休率
- `INT_MISC.RECOVERY_CYCLES`：Bad Speculation / 分支预测失败开销
- `CYCLE_ACTIVITY.STALLS_TOTAL`：Backend Bound / 后端瓶颈，通常对应 SMT 资源争抢

---

## 2.3 混合负载脚本适配中的物理隔离（Stage 4）

在实现 `mixed` 负载（如同时运行 `membw_w4` 和 `l3_w4`）时：

### 规避 offline 任务自我相残

如果 8 个 worker 挤在相同的物理核心上，它们会首先发生剧烈的 core-private 资源冲突，导致它们无法向系统总线（L3/内存）施加预期强度的压力。

### 优化绑定策略

在 `start_offline_workload()` 中，如果是 `mixed` 模式，确保将子任务**均匀地交错绑定**。

**示例配置（OFFLINE_CPUSET 为 16-23，共 8 核）：**

- membw_w4 绑定到 16, 18, 20, 22
- l3_w4 绑定到 17, 19, 21, 23

这样可以最大程度保证它们各自全速运行，同时在末级缓存和内存控制器（Uncore 层面）形成合力，共同压迫同一 NUMA 节点下的 TaoBench。

---

## 2.4 SPEC 2017 运行开销控制

SPEC CPU 2017 的默认 `ref` 数据集运行一次可能需要几十分钟甚至数小时，这会极大地拉长测试周期。

### 优化方案

由于您只需要在 **120 秒（Stage 1-B）** 或 **60 秒（Stage 1-A）** 的窗口内获取其稳态指纹，因此不需要让 SPEC 运行到结束：

1. 在启动 SPEC 进程后，确保其已越过初始化阶段并进入主循环，即可开始采样。
2. 采样结束后，直接发送 SIGKILL 终止 SPEC 进程并清理容器。
3. 可以配置 SPEC 使用 `train` 或 `test` 规模的数据集以加快冷启动和初始化速度，只要保证其在采样窗口内处于活跃态即可。