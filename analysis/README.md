# analysis/ — FUN N-cost fix + s_fix evaluation (2026-09)

Supporting analysis for the FUN parameter fix (docs/FUN_PARAMETER_AUDIT.md) and the s_fix
decision (docs/SFIX_DECISION.md).

- scripts/  : analysis + packaging-comparison scripts
    apply_fun_fix.py     - applies the two N-cost fixes to a CNFUNMod.F90 (typo + nonmyc swap)
    evaluate_v2.py       - corrected(v2) fluxes/pools vs literature
    compare_v3.py        - 3-way OLD/v2/v3 vs literature
    compare_and_email.py - v2 pathway partitioning (before/after)
    compare_bon.py       - Bonanza corrected-code verification
    make_figures.py      - regenerates all comparison figures from the three CSV sets
- figs/     : all comparison figures (also mirrored in notebooks/figs/)
- comparisons/ : text comparison dumps (COMPARISON*.txt)

Data sets (repo root):
  data_csv_corrected/     OLD delivered (buggy code + s_fix=-0.1) -- what Tom has
  data_csv_corrected_v2/  fixed code + s_fix=-0.1 (tuned) -- overshoots symbiotic BNF
  data_csv_sfixorig/      fixed code + s_fix=-6 (physical) -- RECOMMENDED (see docs/SFIX_DECISION.md)
