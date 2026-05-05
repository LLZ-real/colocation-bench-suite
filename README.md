# Colocation Bench Suite

A lightweight framework for running colocation interference experiments with online and offline workloads.

## Current focus

Week 1:
- TaoBench baseline automation
- Docker cpuset isolation
- QPS curve collection
- Structured results

## Requirements

- Docker
- `clab-compute:latest` image
- DCPerf available on host
- privileged container support

## Quick start

```bash
cp conf/env.example.sh conf/env.sh
vim conf/env.sh

bash experiments/taobench_baseline_curve.sh

## Result layout

Each run creates:

results/<timestamp>_<experiment_name>/
  config.env
  machine_topology/
  logs/
  raw/
  parsed/
  summary.csv
## Notes

External benchmark suites such as DCPerf, SPEC CPU, Spark, and iBench are not committed into this repository. They are configured through conf/env.sh.