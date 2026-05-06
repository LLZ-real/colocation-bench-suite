# Weekly Report Notes

## Goal

Build a reproducible TaoBench baseline automation flow for later colocation experiments.

## Implemented

- Docker-based TaoBench server/loadgen orchestration.
- Result directory auto-generation.
- TaoBench client log parser.
- Host-side perf stat collector.
- Prewarm mechanism.
- Repeated-measurement support without overwriting logs.
- ENABLE_PERF switch for perf/no-perf comparison.

## Important results

### Cold/semi-warm repeated clients=500

Same TaoBench server process, repeated clients_per_thread=500:

| run | QPS | P99 ms |
|---:|---:|---:|
| 1 | 21.6k | 268 |
| 2 | 24.3k | 268 |
| 3 | 27.8k | 248 |
| 4 | 32.2k | 237 |
| 5 | 39.6k | 204 |

Conclusion: cold/semi-warm results are not valid baseline.

### Prewarm clients=500

| prewarm round | QPS | P99 ms |
|---:|---:|---:|
| 1 | 29.9k | 247 |
| 2 | 37.0k | 211 |
| 3 | 48.3k | 182 |
| 4 | 69.8k | 129 |
| 5 | 112.8k | 89 |
| 6 | 168.2k | 60 |
| 7 | 167.3k | 60 |

Conclusion: clients=500 converges around round 6.

### Prewarm clients=900

| prewarm round | QPS | P99 ms |
|---:|---:|---:|
| 1 | 30.2k | 475 |
| 2 | 37.4k | 414 |
| 3 | 47.9k | 328 |
| 4 | 71.0k | 249 |
| 5 | 116.2k | 158 |
| 6 | 168.3k | 108 |
| 7 | 170.3k | 109 |
| 8 | 166.9k | 108 |

Conclusion: clients=900 converges around round 6~8.

## Methodology adjustment

Initial clients_per_thread sweep is used only for calibration.
Final colocation experiments will use a fixed online load, likely clients_per_thread=900.

## Open issue

Measured runs with host perf showed lower QPS than prewarm.
Currently running ENABLE_PERF=0 control experiment to check perf overhead.
