# Stage 1 数据采集实验手册

## 1. 背景

收集 TaoBench 在线负载在不同离线负载压力下的 QPS/P99，覆盖 3 种放置策略。

两个脚本：
- `stage1_sweep_clean.sh` — 跑单个放置
- `run_all.sh` — 依次跑多个放置（内部多次调用 sweep 脚本）

---

## 2. 场景一：全新实验

```bash
cd ~/colocation-bench-suite

# 生成矩阵
python3 tools/generate_stage1_matrix.py --mode ibench --out docs/stage1_ibench_matrix.csv

# 启动（后台）
nohup bash experiments/data_collection_experiment/run_all.sh ibench \
  > /tmp/stage1_master.log 2>&1 &

# 看进度
tail -f /tmp/stage1_master.log
```

`run_all.sh ibench` 会把 same_numa → cross_numa → same_smt 三个放置顺序跑完，每个 ~3.6h。

---

## 3. 场景二：查看进度

```bash
# 当前在跑第几个条件
tail -5 /tmp/stage1_master.log

# 已完成的条件数（需要知道 RUN_DIR 名字）
wc -l /home/lilinzhen/colocate_lab/results/cbs/stage1_sail3090_ibench_same_numa_*/progress/completed.csv

# 有哪些失败
cat /home/lilinzhen/colocate_lab/results/cbs/stage1_sail3090_ibench_*/progress/failures.csv
```

---

## 4. 场景三：中断后续跑（条件级）

机器重启、SSH 断开后，某个 placement 跑了一半。

**找到上次的 RUN_DIR**：

```bash
ls -lt /home/lilinzhen/colocate_lab/results/cbs/ | head -5
```

假设输出是 `stage1_sail3090_ibench_cross_numa_20260529_032047`，里面有 `progress/completed.csv` 记录已完成的条件。

**绕过 `run_all.sh`，直接调 sweep 脚本并将 RUN_DIR 指向旧目录**：

```bash
cd ~/colocation-bench-suite

RUN_DIR=/home/lilinzhen/colocate_lab/results/cbs/stage1_sail3090_ibench_cross_numa_20260529_032047 \
MATRIX_FILE=docs/stage1_ibench_matrix.csv \
PLACEMENT=cross_numa \
EXP_NAME=stage1_sail3090_ibench_cross_numa \
CLAB_IMAGE="dcperf-taobench:ready" \
DCPERF_MOUNT=0 \
SERVER_CPUSET="0,1,2,3,4,5,6,7" \
SERVER_MEMS="0" \
LOADGEN_CPUSET="32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47" \
LOADGEN_MEMS="1" \
CLIENTS_PER_THREAD=900 \
CLIENT_TEST_TIME=60 \
PREWARM_ROUNDS=8 \
TAO_SERVER_WARMUP_TIME=2400 \
TAO_SERVER_TEST_TIME=18000 \
nohup bash experiments/data_collection_experiment/stage1_sweep_clean.sh \
  > /tmp/stage1_resume_cross_numa.log 2>&1 &
```

关键：`RUN_DIR` 指向旧目录 → 脚本不创建新目录 → 读已有 `completed.csv` → 跳过已完成条件。

续跑完成后，剩余的 placement（same_smt）可以用 `run_all.sh` 启动——它检测到 same_smt 没完成会正常跑。

---

## 5. 场景四：只跑一个 placement（不用 run_all.sh）

```bash
cd ~/colocation-bench-suite

MATRIX_FILE=docs/stage1_ibench_matrix.csv \
PLACEMENT=same_numa \
EXP_NAME=stage1_sail3090_ibench_same_numa \
CLAB_IMAGE="dcperf-taobench:ready" \
DCPERF_MOUNT=0 \
SERVER_CPUSET="0,1,2,3,4,5,6,7" \
SERVER_MEMS="0" \
LOADGEN_CPUSET="32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47" \
LOADGEN_MEMS="1" \
CLIENTS_PER_THREAD=900 \
CLIENT_TEST_TIME=60 \
PREWARM_ROUNDS=8 \
TAO_SERVER_WARMUP_TIME=2400 \
TAO_SERVER_TEST_TIME=18000 \
nohup bash experiments/data_collection_experiment/stage1_sweep_clean.sh \
  > /tmp/stage1_same_numa.log 2>&1 &
```

---

## 6. 场景五：给已完成的 placement 追加新条件

旧数据不动。新建 exp_name 跑新矩阵，两个目录各自产出，汇总时合并。

```bash
# 创建裁减过的矩阵（只包含新增条件）
cat > /tmp/stage1_new_conditions.csv <<'EOF'
condition_id,offline_type,offline_param,offline_intensity,offline_label,spec_size,spec_copies,spec_bench,workload_category,resource_profile
ibench_l3_w10_a60,ibench_l3,10,60,w10_a60,,,,ibench,l3
ibench_l3_w12_a60,ibench_l3,12,60,w12_a60,,,,ibench,l3
EOF

# 用新 exp_name 跑
MATRIX_FILE=/tmp/stage1_new_conditions.csv \
PLACEMENT=same_numa \
EXP_NAME=stage1_sail3090_ibench_same_numa_ext \
... \
nohup bash experiments/data_collection_experiment/stage1_sweep_clean.sh \
  > /tmp/stage1_extra.log 2>&1 &
```

结果在 `stage1_sail3090_ibench_same_numa_ext_*` 目录下。汇总时 `summarize_stage1_smart.py` 会合并多个 run_dir。

---

## 7. 场景六：终止实验

```bash
# 找到进程
ps aux | grep stage1 | grep -v grep

# 杀（trap 自动清理容器）
kill <PID>

# 确认容器已清理
docker ps --format "{{.Names}}" | grep clab
```

---

## 8. 结果目录结构

```
RUN_DIR/
  summary.csv              # 每条件一行
  progress/
    completed.csv          # 已完成的 condition_id（一行一个）
    failures.csv           # 失败记录
    full.log               # 全部终端输出
  machine_topology/
    preflight.txt           # 系统快照（SMT/频率/THP/IRQ/...）
    *_container.inspect.json
  raw/    parsed/    logs/
```

---

## 9. 裁剪矩阵

same_numa 数据已证明 `ibench_cpu` 零影响、membw/l3 的 w1/w2 影响很小。后续放置可跳过这些条件以节省时间：

```bash
python3 <<'PY'
import csv
with open("docs/stage1_ibench_matrix.csv") as f:
    rows = list(csv.DictReader(f))
keep = []
for r in rows:
    cid = r['condition_id']
    if cid.startswith('ibench_cpu'): continue
    w = int(r['offline_param'])
    if r['offline_type'] in ('ibench_membw','ibench_l3') and w <= 2: continue
    keep.append(r)
with open("docs/stage1_ibench_matrix_trimmed.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=rows[0].keys()); w.writeheader(); w.writerows(keep)
print(f"{len(rows)} → {len(keep)} ({len(rows)-len(keep)} removed)")
PY
```

---

## 10. cpuset 覆盖

所有 cpuset 可通过环境变量覆盖：

```bash
SERVER_CPUSET="0,2,4,6,8,10,12,14" \
LOADGEN_CPUSET="32,34,36,38,40,42,44,46,96,98,100,102,104,106,108,110" \
bash experiments/data_collection_experiment/run_all.sh ibench
```

OFFLINE_CPUSET 由 PLACEMENT 自动选择，要改的话编辑 `stage1_sweep_clean.sh` 中的 case 语句。
