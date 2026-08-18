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

## FUN carbon-cost diagnostics (added 2026-08-17)
Component C costs of nutrient acquisition, for N/P limitation proxies:
- NPP_NUPTAKE / NPP_PUPTAKE : total C cost of N / P acquisition (kgC/m2/day). NPP_NUPTAKE INCLUDES symbiotic fixation cost.
- NPP_NACTIVE : mycorrhizal (active) N-uptake C cost only -> fixation-free N index (kgC/m2/day).
- NPP_NFIX    : symbiotic BNF C cost only (kgC/m2/day). Free-living fixation (FNFIX) has NO plant C cost.
- COST_NFIX / COST_NACTIVE : N acquired per unit C for fixation / active uptake (gN/gC); COST_PACTIVE (gP/gC).
                              NaN where pathway inactive (e.g. boreal symbiotic fixation ~ 0).
- NUPTAKE_NPP_FRACTION / PUPTAKE_NPP_FRACTION : model's own frac of AVAILABLE C spent on N / P uptake (-).
  NOTE: denominator is available C, so this is NOT equal to NPP_NUPTAKE/(NPP+costs).
Suggested proxies:
  N-vs-P balance   = NPP_NUPTAKE / NPP_PUPTAKE
  fixation-free N  = NPP_NACTIVE / (NPP_NUPTAKE + NPP_PUPTAKE + NPP)
  C cost per N fix = NPP_NFIX / SNFIX   (gC/gN)
CAVEAT: realized C cost per N fixed is ~0.1-0.3 gC/gN here, far below obs (Menge 2026 ~5 gC/gN) and FUN
nominal (Fisher 2010, 7.5-12.5). BNF fluxes are realistic but the C investment is low (s_fix tuning), so
cost-based limitation indices are meaningful relatively (trends, N-vs-P balance, scheme contrast), not as
absolute limitation intensity. See docs/LIMITATION_INDICES_EVALUATION.md.
