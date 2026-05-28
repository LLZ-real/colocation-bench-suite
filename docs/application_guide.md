# Application 实验框架使用指南

## 概述

`application/` 是一个可移植、参数驱动的混部实验框架，与旧版 `experiments/` 独立，目标是在不同机器上复现 TaoBench + 离线负载（iBench / SPEC CPU）的混部干扰实验。

核心改进：
- 可移植 Docker 镜像（DCPerf/TaoBench 打包在镜像内，无需宿主机挂载源码目录）
- 自动发现 CPU/NUMA/SMT 拓扑，自动生成 cpuset 绑定
- dry-run 模式预览完整流程
- 预留 Intel RDT CAT/LLC、MBA、网络整形、CPU 频率等资源控制 hooks

---

## 1. 环境准备

### 1.1 获取 TaoBench 镜像

**方式 A：导入预构建镜像**

```bash
bash scripts/import_taobench_image.sh dcperf-taobench-ready.tar
```

**方式 B：从 DCPerf 源码本地构建**

```bash
# 如果已有 DCPerf 源码目录
DCPERF_DIR=/home/lilinzhen/colocate_lab/DCPerf \
  bash application/bootstrap_dcperf_taobench.sh

# 如果没有 DCPerf，脚本会自动 clone（可配置代理）
PROXY="http://127.0.0.1:7900" \
DCPERF_DIR=/home/lilinzhen/colocate_lab/DCPerf \
  bash application/bootstrap_dcperf_taobench.sh
```

`bootstrap_dcperf_taobench.sh` 做的事：
1. clone DCPerf 仓库（如需要）
2. 安装 benchpress Python 依赖
3. 通过 `benchpress_cli.py install tao_bench_autoscale` 安装 TaoBench
4. 调用 `scripts/build_taobench_image.sh` 构建 `dcperf-taobench:ready` 镜像

关键环境变量：

| 变量 | 默认值 | 说明 |
|---|---|---|
| `DCPERF_REPO` | `https://github.com/facebookresearch/DCPerf.git` | DCPerf 仓库地址 |
| `DCPERF_DIR` | `/home/lilinzhen/colocate_lab/DCPerf` | DCPerf 本地路径 |
| `BUILD_IMAGE` | `1` | 是否构建 Docker 镜像 |
| `TAOBENCH_INSTALL` | `1` | 是否安装 TaoBench |
| `REINSTALL_TAOBENCH` | `0` | 设为 1 强制重装 |
| `PROXY` | 空 | HTTP 代理（构建镜像时需要） |

### 1.2 外部依赖目录

确保以下目录存在：

```
/home/lilinzhen/iBench/       # iBench 离线负载
/home/lilinzhen/cpu2017/      # SPEC CPU 2017
/home/lilinzhen/colocate_lab/results/cbs/  # 结果输出目录
```

---

## 2. 拓扑发现与配置

### 2.1 查看宿主机拓扑

```bash
# 文本格式
python3 application/topology.py --format text

# JSON 格式
python3 application/topology.py --format json
```

输出包含：NUMA 节点及 CPU 列表、Socket、SMT 配对、CPU0 cache 信息。

### 2.2 自动生成 env.sh

```bash
# 离线负载与 Server 共享 SMT 兄弟线程（默认）
python3 application/generate_env_from_topology.py \
  --offline-policy same_smt \
  --out conf/env.sh

# 离线负载与 Server 同 Socket 不同核心
python3 application/generate_env_from_topology.py \
  --offline-policy same_socket \
  --out conf/env.sh

# 离线负载与 Server 跨 NUMA
python3 application/generate_env_from_topology.py \
  --offline-policy cross_numa \
  --out conf/env.sh
```

关键参数：

| 参数 | 默认值 | 说明 |
|---|---|---|
| `--server-cores` | 8 | Server 使用的核心数 |
| `--loadgen-cores` | 16 | Loadgen 使用的核心数 |
| `--offline-cores` | 8 | 离线负载使用的核心数 |
| `--offline-policy` | `same_smt` | 放置策略：`same_smt` / `same_socket` / `cross_numa` |
| `--server-socket` | 自动选第一个 | 指定 server socket |
| `--loadgen-socket` | 自动选第二个 | 指定 loadgen socket |
| `--image` | `dcperf-taobench:ready` | Docker 镜像名 |
| `--dcperf-mount` | `0` | 0=使用镜像内置 DCPerf，1=挂载宿主机目录 |
| `--interface` | `eno1` | 网络接口名 |
| `--out` | 空（stdout） | 输出文件路径 |

生成的 `conf/env.sh` 是一个起点，**务必手动检查**网络接口、`RESULTS_ROOT`、`IBENCH_DIR`、`SPEC_DIR` 以及所有 CPU/NUMA 绑定。

---

## 3. 迁移前检查（preflight）

在新机器上部署后，运行 preflight 检查所有依赖：

```bash
bash application/preflight.sh
```

检查内容包括：
- 宿主机命令（docker、python3、lscpu、numactl）
- 配置变量完整性
- Docker daemon 可达性
- Docker 镜像存在性及内容校验（`DCPERF_MOUNT=1` 时检查 DCPerf 目录）
- 路径存在性
- CPU/NUMA 绑定合法性（CPU 编号、NUMA 节点是否在机器上存在）
- 最终执行一次 dry-run 验证完整流程

跳过特定检查：

```bash
# 不检查 Docker 镜像内容
CHECK_IMAGE_CONTENT=0 bash application/preflight.sh

# 不检查 iBench/SPEC 路径
CHECK_OFFLINE_PATHS=0 bash application/preflight.sh

# 使用自定义 env 文件
ENV_FILE=/tmp/cbs-env.sh bash application/preflight.sh
```

---

## 4. 运行实验

### 4.1 核心命令

```bash
# dry-run：预览流程，不真正启动容器和负载
ACTION=dry-run \
  EXP_NAME=my_experiment \
  OFFLINE_TYPE=none \
  bash application/run_taobench_colocation.sh

# 正式运行
ACTION=run \
  EXP_NAME=my_experiment \
  OFFLINE_TYPE=none \
  CLIENTS_PER_THREAD=900 \
  CLIENT_TEST_TIME=300 \
  bash application/run_taobench_colocation.sh
```

### 4.2 完整示例

**基线（无离线负载）：**

```bash
ACTION=run \
  EXP_NAME=baseline \
  OFFLINE_TYPE=none \
  SERVER_CPUSET=0,1,2,3,4,5,6,7 \
  SERVER_MEMS=0 \
  LOADGEN_CPUSET=32,33,34,35,36,37,38,39,96,97,98,99,100,101,102,103 \
  LOADGEN_MEMS=1 \
  OFFLINE_CPUSET=64,65,66,67,68,69,70,71 \
  OFFLINE_MEMS=0 \
  CLIENTS_PER_THREAD=900 \
  CLIENT_TEST_TIME=300 \
  SERVER_BOOTSTRAP_WAIT=180 \
  bash application/run_taobench_colocation.sh
```

**iBench 内存带宽干扰：**

```bash
ACTION=run \
  EXP_NAME=ibench_membw \
  OFFLINE_TYPE=ibench_membw \
  OFFLINE_PARAM=8 \
  OFFLINE_LABEL=w8 \
  SERVER_CPUSET=0,1,2,3,4,5,6,7 \
  SERVER_MEMS=0 \
  LOADGEN_CPUSET=32,33,34,35,36,37,38,39,96,97,98,99,100,101,102,103 \
  LOADGEN_MEMS=1 \
  OFFLINE_CPUSET=64,65,66,67,68,69,70,71 \
  OFFLINE_MEMS=0 \
  CLIENTS_PER_THREAD=900 \
  CLIENT_TEST_TIME=300 \
  SERVER_BOOTSTRAP_WAIT=180 \
  bash application/run_taobench_colocation.sh
```

**SPEC CPU mcf 干扰：**

```bash
ACTION=run \
  EXP_NAME=spec_mcf \
  OFFLINE_TYPE=spec_mcf \
  SPEC_SIZE=ref \
  SPEC_COPIES=1 \
  SERVER_CPUSET=0,1,2,3,4,5,6,7 \
  SERVER_MEMS=0 \
  LOADGEN_CPUSET=32,33,34,35,36,37,38,39,96,97,98,99,100,101,102,103 \
  LOADGEN_MEMS=1 \
  OFFLINE_CPUSET=64,65,66,67,68,69,70,71 \
  OFFLINE_MEMS=0 \
  CLIENTS_PER_THREAD=900 \
  CLIENT_TEST_TIME=300 \
  SERVER_BOOTSTRAP_WAIT=180 \
  bash application/run_taobench_colocation.sh
```

### 4.3 离线负载类型

| `OFFLINE_TYPE` | 说明 | `OFFLINE_PARAM` 含义 |
|---|---|---|
| `none` | 无离线负载（基线） | 不需要 |
| `ibench_cpu` | iBench CPU 压力 | worker 数量（默认 8） |
| `ibench_membw` | iBench 内存带宽压力 | worker 数量（默认 8） |
| `ibench_l3` | iBench L3 cache 压力 | worker 数量（默认 8） |
| `ibench_memcap` | iBench 内存容量压力 | 内存大小（默认 15） |
| `spec_mcf` | SPEC 505.mcf_r | 不需要（使用 `SPEC_SIZE`/`SPEC_COPIES`） |
| `spec_lbm` | SPEC 519.lbm_r | 不需要（使用 `SPEC_SIZE`/`SPEC_COPIES`） |

注意：`OFFLINE_WORKLOAD` 是 `OFFLINE_TYPE` 的别名，两者可互换。

### 4.4 常用参数速查

**实验控制：**

| 参数 | 默认值 | 说明 |
|---|---|---|
| `ACTION` | `run` | `run` 正式运行，`dry-run` 预览 |
| `EXP_NAME` | `app_taobench_colocation` | 实验名称，影响结果目录 |

**TaoBench：**

| 参数 | 默认值 | 说明 |
|---|---|---|
| `CLIENTS_PER_THREAD` | `900` | 每线程客户端数 |
| `CLIENT_TEST_TIME` | `60` | 客户端测量时长（秒） |
| `CLIENT_WARMUP_TIME` | `120` | 客户端预热时长（秒） |
| `SERVER_BOOTSTRAP_WAIT` | `180` | server 启动后等待（秒） |
| `TAO_SERVER_WARMUP_TIME` | `2400` | server 预热时长（秒） |
| `TAO_SERVER_TEST_TIME` | `10800` | server 总运行时长（秒） |
| `TAO_MEMSIZE` | `16` | server 内存大小（GB） |
| `TAO_SERVER_PORT` | `11211` | server 端口 |

**离线负载：**

| 参数 | 默认值 | 说明 |
|---|---|---|
| `OFFLINE_TYPE` | `none` | 离线负载类型 |
| `OFFLINE_PARAM` | 空 | 离线负载参数 |
| `OFFLINE_LABEL` | 自动生成 | 用于命名标签 |
| `OFFLINE_STABILIZE_WAIT` | `20` | 离线负载启动后稳定等待（秒） |
| `SPEC_CONFIG` | `my_test.cfg` | SPEC 配置文件 |
| `SPEC_SIZE` | `ref` | SPEC 数据集大小 |
| `SPEC_COPIES` | `1` | SPEC 并行副本数 |

**放置：**

| 参数 | 说明 |
|---|---|
| `SERVER_CPUSET` | Server CPU 绑定 |
| `SERVER_MEMS` | Server NUMA 节点绑定 |
| `LOADGEN_CPUSET` | Loadgen CPU 绑定 |
| `LOADGEN_MEMS` | Loadgen NUMA 节点绑定 |
| `OFFLINE_CPUSET` | 离线负载 CPU 绑定 |
| `OFFLINE_MEMS` | 离线负载 NUMA 节点绑定 |

---

## 5. Docker 资源控制

通过环境变量为每个容器设置 cgroup 资源限制，命名规则为 `<ROLE>_<资源类型>`。

### 5.1 CPU 与内存

```bash
# Server CPU 份额
SERVER_CPU_SHARES=2048 \
  # Server CPU 配额（每周期微秒）
  SERVER_CPU_QUOTA=400000 \
  SERVER_CPU_PERIOD=100000 \
  # Server 内存限制
  SERVER_MEMORY_LIMIT=16g \
  # 离线负载 CPU 限制
  OFFLINE_CPU_QUOTA=200000 \
  OFFLINE_MEMORY_LIMIT=8g \
  bash application/run_taobench_colocation.sh
```

每个 role 支持的参数：

| 参数后缀 | 说明 | Docker flag |
|---|---|---|
| `_CPU_SHARES` | CPU 相对权重 | `--cpu-shares` |
| `_CPU_QUOTA` | CPU 配额（微秒） | `--cpu-quota` |
| `_CPU_PERIOD` | CPU 周期（微秒） | `--cpu-period` |
| `_MEMORY_LIMIT` | 内存上限 | `--memory` |
| `_MEMORY_SWAP` | 内存+swap 上限 | `--memory-swap` |
| `_BLKIO_WEIGHT` | 块设备 IO 权重 | `--blkio-weight` |
| `_DEVICE_READ_BPS` | 磁盘读速率限制 | `--device-read-bps` |
| `_DEVICE_WRITE_BPS` | 磁盘写速率限制 | `--device-write-bps` |
| `_CGROUP_PARENT` | cgroup 父组路径 | `--cgroup-parent` |

### 5.2 容器网络模式

```bash
# 默认 host 网络
# 切换为 bridge
APP_DOCKER_NETWORK=bridge bash application/run_taobench_colocation.sh
```

---

## 6. 资源控制 Hooks（预留）

### 6.1 Intel RDT CAT/LLC（缓存分配）

```bash
RDT_ENABLE=1 \
  SERVER_LLC_MASK=0xf0 \
  LOADGEN_LLC_MASK=0x0c \
  OFFLINE_LLC_MASK=0x03 \
  bash application/run_taobench_colocation.sh
```

需要 `pqos` 命令或 `/sys/fs/resctrl` 挂载。

### 6.2 Intel MBA（内存带宽分配）

```bash
MBA_ENABLE=1 \
  SERVER_MBA_PERCENT=70 \
  LOADGEN_MBA_PERCENT=30 \
  OFFLINE_MBA_PERCENT=20 \
  bash application/run_taobench_colocation.sh
```

### 6.3 网络整形

```bash
NET_SHAPE_ENABLE=1 \
  NET_IFACE=eno1 \
  OFFLINE_NET_RATE=100mbit \
  bash application/run_taobench_colocation.sh
```

### 6.4 CPU 频率控制

```bash
CPU_FREQ_ENABLE=1 \
  CPU_FREQ_GOVERNOR=performance \
  CPU_FREQ_MIN=2.0GHz \
  CPU_FREQ_MAX=3.5GHz \
  bash application/run_taobench_colocation.sh
```

需要 `cpupower` 命令和 sudo 权限。

---

## 7. 结果输出

每次实验在 `RESULTS_ROOT` 下创建 `YYYYMMDD_HHMMSS_<EXP_NAME>_<OFFLINE_TYPE>_<OFFLINE_LABEL>/` 目录：

```
<run_dir>/
  summary.csv           # 单行结果：QPS、P99、所有参数
  config.env            # 实验时环境变量快照
  logs/
    server.log          # TaoBench server 日志
    offline_*.log       # 离线负载日志
  raw/
    client_*.log        # 客户端原始日志
  parsed/
    client_*.json       # 客户端解析结果（QPS, P99, 延迟分布等）
  machine_topology/
    lscpu.txt           # CPU 信息
    lscpu_e.txt         # CPU 详细拓扑
    numactl_H.txt       # NUMA 信息
    topology.json       # 完整拓扑 JSON
    *_container.inspect.json  # 容器 inspect 信息
```

---

## 8. 完整实验流程（新机器上手）

```bash
# Step 1: 导入或构建镜像
bash scripts/import_taobench_image.sh dcperf-taobench-ready.tar

# Step 2: 自动生成配置
python3 application/generate_env_from_topology.py \
  --offline-policy same_smt \
  --out conf/env.sh

# Step 3: 手动检查并修改 conf/env.sh
vim conf/env.sh

# Step 4: preflight 检查
bash application/preflight.sh

# Step 5: dry-run 验证
ACTION=dry-run \
  EXP_NAME=smoke_test \
  OFFLINE_TYPE=ibench_l3 \
  OFFLINE_PARAM=8 \
  CLIENTS_PER_THREAD=900 \
  CLIENT_TEST_TIME=60 \
  SERVER_BOOTSTRAP_WAIT=180 \
  bash application/run_taobench_colocation.sh

# Step 6: 正式运行
ACTION=run \
  EXP_NAME=baseline \
  OFFLINE_TYPE=none \
  CLIENTS_PER_THREAD=900 \
  CLIENT_TEST_TIME=300 \
  SERVER_BOOTSTRAP_WAIT=180 \
  bash application/run_taobench_colocation.sh
```

---

## 9. DCPERF_MOUNT 模式对比

| | `DCPERF_MOUNT=0`（推荐） | `DCPERF_MOUNT=1`（旧模式） |
|---|---|---|
| DCPerf 位置 | 镜像内 `/workspace/DCPerf` | 宿主机挂载 |
| `DCPERF_DIR` | 不需要 | 必须设置 |
| `CLAB_IMAGE` | `dcperf-taobench:ready`（含 TaoBench） | `clab-compute:latest`（不含） |
| 优点 | 可移植，镜像自包含 | 可以修改 DCPerf 源码 |
| 适用场景 | 多机器部署，固定版本实验 | 开发调试 DCPerf 本身 |

---

## 10. 注意事项

- `conf/env.sh` 被 `.gitignore` 忽略，每台机器需要独立配置
- perf/PMU 采集会干扰 TaoBench 性能，性能测量与 perf 采集应分开进行
- 生成的 cpuset 绑定如果策略不当可能产生重叠，`generate_env_from_topology.py` 会自动检测并报错
- 离线负载（尤其是 iBench memBw）启动后需要 `OFFLINE_STABILIZE_WAIT` 等待达到稳态
- 实验前确保没有残留容器：`bash containers/destroy_all.sh`