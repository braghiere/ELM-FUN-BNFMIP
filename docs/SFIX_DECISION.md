# s_fix decision: physical value (-6), do not retune — evidence summary (2026-09)

After fixing the inherited FUN N-cost defects (see docs/FUN_PARAMETER_AUDIT.md), symbiotic BNF
changed and the pre-existing `s_fix` tuning had to be re-evaluated. Three runs were compared
(all: corrected pathway code; differ only in the symbiotic-fixation cost scalar `s_fix`):

| run | folder | s_fix | fixation cost (gC/gN) |
|-----|--------|------:|----------------------:|
| OLD (delivered, buggy code) | data_csv_corrected/ | -0.1 | 0.12-0.18 |
| v2 (fixed code, tuned s_fix) | data_csv_corrected_v2/ | -0.1 | 0.12-0.18 |
| **v3 (fixed code, physical s_fix)** | **data_csv_sfixorig/** | **-6** | **7.2-10.6** |

## Verdict: v3 (s_fix = -6). Do NOT tune s_fix up.
`-6` is the CLM5/CLM6 default and the physically-nominal cost (Houlton 2008 / Fisher 2010:
7.5-12.5 gC/gN; Menge 2026 obs ~5). `-0.1`/`-1` charge 0.1-1 gC/gN, below every observation.

Three independent lines agree on v3:
1. **Cost physics** (analysis/figs/sfix_cost_physics.png): only s_fix=-6 reaches 7.5-12.5 gC/gN.
2. **Pathway partitioning** (analysis/figs/pathways_across_runs.png): v3 mycorrhizal ~80% of N
   uptake (obs ~80%, van der Heijden 2015; Braghiere 2022 78%); v2 inflates fixation to 20%,
   dragging mycorrhizae to 62%; OLD is backwards (myc 3.5%, non-myc 68%).
3. **Flux magnitude vs 2026 synthesis** (analysis/figs/bnf_verdict_2026.png): ELM TOTAL BNF
   (symbiotic+free-living), present-day gN/m2/yr:
   - Manaus  OLD 3.40 / v2 5.28 / **v3 0.91**  vs measured total 0.2-0.7
   - Harvard OLD 2.18 / v2 2.59 / **v3 0.54**  vs measured total 0.1-0.6
   - Bonanza 0.21 (all) vs measured total 0.15-0.20
   v3 lands in/just above range; OLD/v2 sit 4-8x high in the superseded-Cleveland zone.

## Key literature (2026 authoritative synthesis)
- Reis et al. 2025 (Nature, 10.1038/s41586-025-09201-w): global natural BNF 65 (52-77) Tg N/yr,
  ~half of Cleveland 1999 (195); Cleveland ET/NPP slopes ~2x too high.
- Sullivan et al. 2014 (PNAS, 10.1073/pnas.1320646111): mature Amazon SYMBIOTIC BNF ~0.02
  gN/m2/yr (0.1-0.5 kgN/ha/yr), 30-100x below regression estimates; total free-living-dominated.
- DeLuca et al. 2002 (Nature): boreal upland symbiotic ~0; N input is feather-moss cyanobacteria
  ~0.15-0.20 gN/m2/yr (ELM's free-living ET term already captures this).
- Menge et al. 2026 (GBC, 10.1029/2026GB009098): symbiotic BNF only 0.29% of natural NPP.
- Kou-Giesbrecht et al. 2025 (PNAS, 10.1073/pnas.2514628122): CMIP6/TRENDY models OVERESTIMATE
  natural BNF ~54% (100 vs 65 Tg), exaggerating CO2 fertilization ~11%. Recommends: separate
  symbiotic from free-living, and charge symbiotic a C cost -- exactly what ELM-FUN(s_fix=-6) does.

## MIP framing (why ELM looked low)
Definitional, not physical. ELM's `NFIX` diagnostic is symbiotic-only; ORCHIDEE/CLASSIC/JULES/LPJ
report lumped TOTAL; QUINCY at Amazon is free-living-dominated. Compare ELM TOTAL
(SNFIX+FNFIX: v3 = 0.91/0.54/0.21) against other models' totals, niche-by-niche. ELM's
free-living is the standard Cleveland (1999) ET term (NitrogenDynamicsMod::FreeLivingFixation:
ffix = 6e-4*AnnET + 1.17e-2 gN/m2/yr), s_fix-independent.

## Manuscript framing
Corrected ELM-FUN has realistically LOW symbiotic BNF (Sullivan/Reis-consistent) and avoids the
~54% BNF overestimate of the empirical-scheme models -- a strength to highlight (Kou-Giesbrecht 2025).
Note: tuning symbiotic up to match total-reporting models is the documented error; free-living is
represented separately.

Figures: analysis/figs/{bnf_verdict_2026, bnf_magnitude_vs_lit, sfix_cost_physics,
pathways_across_runs, tom_bnf_schemes, tom_metrics_impact, eval_v2_literature, eval_v2_trajectories}.png
