# s_fix decision: physical value (-6), do not retune — evidence summary (2026-09)

After fixing the inherited FUN N-cost defects (see docs/FUN_PARAMETER_AUDIT.md), symbiotic BNF
changed and the pre-existing `s_fix` tuning had to be re-evaluated. NOTE the OLD->v3 sequence is
NOT single-variable: OLD (buggy code + tuned s_fix), v2 (corrected pathways + tuned s_fix),
v3 (corrected pathways + s_fix=-6). OLD->v2 changes competing pathway costs; v2->v3 changes the
scalar. The two move symbiotic fixation in OPPOSITE directions (see decomposition below).

Realized fixation cost = flux-integrated ΣNPP_NFIX / ΣSNFIX over the window (NOT 1/mean(COST_NFIX),
which over-states it; and NOT the raw COST_NFIX diagnostic, which is gN/gC — see docs/corrections.md):

| run | folder | s_fix | realized cost (gC/gN), Manaus |
|-----|--------|------:|------------------------------:|
| OLD (delivered, buggy code) | data_csv_corrected/ | -0.1 | 0.10-0.16 |
| v2 (fixed code, tuned s_fix) | data_csv_corrected_v2/ | -0.1 | 0.10-0.16 |
| **v3 (fixed code, physical s_fix)** | **data_csv_sfixorig/** | **-6** | **6.15-10.0** |

v3 realized (Manaus, ΣNPP_NFIX/ΣSNFIX): Bytnerowicz noAcc 6.15/6.24, Acc 6.82/6.28,
Houlton 7.54/10.00 (present 2005-2014 / future 2090-2099). Houlton rises under warming because
Manaus soil (TSOIBNF ~31->36 C) is ABOVE the Houlton cost-optimum (25.15 C).

## Verdict: v3 (s_fix = -6) is a defensible physical REFERENCE — not a unique calibration.
`-6` is the CLM5/CLM6 default. v3's realized cost (6.15-10.0 gC/gN) is physiologically plausible:
at/above Menge et al. 2026's synthesis central of ~5 (range 4-6; note Menge flags a glucose-vs-carbon
mis-citation that lowers Fisher 2010's 7.5-12.5), and overlapping the lower Fisher range. The tuned
`-0.1`/`-1` charge 0.10-0.16 gC/gN, an order of magnitude below any synthesis. `-6` is retained as a
reference; it has NOT been uniquely calibrated or site-validated. Do not present the cost/partition/
magnitude figures as three independent validations — they are coupled outputs of the same system.

Supporting lines (each with caveats, none a validation):
1. **Cost physics**: the EXECUTED Houlton cost function ((-s_fix)/(1.25*exp(a+b*T*(1-0.5T/c))),
   a=-3.62,b=0.27,c=25.15) gives 6.01@25C, 7.22@31C, ~11@36C for s_fix=-6, reproducing the realized
   costs above. NOTE the old analysis/figs/sfix_cost_physics.png plotted the paramfile "-2" form
   (superseded by the executed L3171 form) and must be rebuilt from the executed function.
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
  ~one-third of the older Cleveland 1999 (195) estimate (65/195 = 0.33). Downward revision
  attributed largely to abundance-aware extrapolation (N-fixers over-represented in sampled
  sites). NB: a global budget constrains totals, not any single site's future curve.
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
