# Intel PT Trace Processing Notes

External Intel PT processing repo:

- Path: /home/lilinzhen/Intel_PT_Trace_Processing
- Upstream: https://github.com/phoenix-ZY/Intel_PT_Trace_Processing

This repository is kept outside `colocation-bench-suite` to avoid nested Git repositories.

Current plan:

1. Use `perf record -e intel_pt//u` to collect short Intel PT traces.
2. Store raw PT data under each experiment run directory:
   - `$RUN_DIR/pt/perf_pt_*.data`
   - `$RUN_DIR/pt/perf_pt_*.script`
3. Use `/home/lilinzhen/Intel_PT_Trace_Processing` as an external post-processing tool.
4. Only commit scripts, notes, and summarized results to `colocation-bench-suite`.
