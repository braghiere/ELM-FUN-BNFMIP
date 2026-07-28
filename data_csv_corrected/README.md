# ELM-FUN BNFMIP — CORRECTED (spun-up) site results — CSV export
Corrected version of the site simulations (replaces gen-1 data_csv/ once verified).
Same layout/units as data_csv/: bnfmip_elmfun_table2_annual_long.csv (tidy long, annual)
and monthly/<site>_<experiment>_secNN.csv (full 54-var C/N/P).

## What changed vs gen-1
Full C-N-P cycle equilibrated in spin-up (P cycle previously not), transients re-run:
- Pre-industrial "U-shape" drift eliminated across all carbon pools (stable trajectories).
- GPP, NPP, BNF (incl. temperature response) essentially unchanged, literature-consistent.
- Carbon pools ~8-14% lower (true P-limited level).

## Caveats (documented)
- Boreal (Bonanza) soil mineral N over-accumulates (SMINN) - known ELM cold-soil limit; does not affect fixation/flux/C.
- Soil C runs high (ELM/CTC bias). 
- Available P = SOLUTIONP (small, P-limited); SMINP = solution+labile+secondary P (large by defn).
- TOTSOMN can be negative (diagnostic quirk) - use TOTVEGN/SMINN.
See notebooks/BNFMIP_corrected_vs_gen1.ipynb for the full comparison + verdict.
