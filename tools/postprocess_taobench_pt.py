#!/usr/bin/env python3
import argparse
import sys
from pathlib import Path

def main():
    ap = argparse.ArgumentParser(description="Post-process TaoBench Intel PT perf.data using Intel_PT_Trace_Processing.")
    ap.add_argument("--pt-root", default="/workspace/Intel_PT_Trace_Processing")
    ap.add_argument("--perf-data", required=True)
    ap.add_argument("--prefix", required=True)
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--perf-tool", default="/usr/bin/perf")
    ap.add_argument("--max-insn-lines", type=int, default=500000)
    ap.add_argument("--line-size", type=int, default=64)
    ap.add_argument("--no-insn-portrait", action="store_true")
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()

    pt_root = Path(args.pt_root).resolve()
    perf_data = Path(args.perf_data).resolve()
    out_dir = Path(args.out_dir).resolve()

    if not pt_root.exists():
        raise SystemExit(f"PT root not found: {pt_root}")
    if not perf_data.exists():
        raise SystemExit(f"perf.data not found: {perf_data}")

    sys.path.insert(0, str(pt_root))

    from perf_pipeline import perf_postprocess_one

    result = perf_postprocess_one(
        script_dir=pt_root,
        perf_tool=args.perf_tool,
        perf_data=perf_data,
        prefix=args.prefix,
        intermediate_dir=out_dir / "intermediate",
        mem_dir=out_dir / "mem",
        report_dir=out_dir / "report",
        perf_max_insn_lines=args.max_insn_lines,
        line_size=args.line_size,
        analysis_rd_hist_cap_lines=262144,
        analysis_stride_bin_cap_lines=262144,
        recover_init_regs="random",
        recover_reg_staging="dwt",
        recover_mvs="on",
        recover_fill_seed=1,
        recover_page_init="zero",
        recover_page_init_seed=1,
        recover_progress_every=0,
        recover_salvage_invalid_mem=True,
        recover_salvage_reads=True,
        insn_portrait=not args.no_insn_portrait,
        verbose=args.verbose,
    )

    aux_lost, trace_errors, ninsn, perf_insn_trace, perf_rec_mem, perf_data_analysis, perf_inst_analysis, portrait_txt = result

    print("[OK] PT postprocess done")
    print(f"aux_lost={aux_lost}")
    print(f"trace_errors={trace_errors}")
    print(f"ninsn={ninsn}")
    print(f"perf_insn_trace={perf_insn_trace}")
    print(f"perf_rec_mem={perf_rec_mem}")
    print(f"perf_data_analysis={perf_data_analysis}")
    print(f"perf_inst_analysis={perf_inst_analysis}")
    print(f"portrait_txt={portrait_txt}")

if __name__ == "__main__":
    main()
