# ACC vs noAcc temperature-input confound (verified in v3 source, 2026-09)

**Status: OPEN.** Flagged from the 2026-08-06 correspondence; re-verified in the v3
`source_mods/` and still present. The ACC (acclimation) fixation-cost path is driven by a
*different temperature input* than the noAcc and Houlton paths, so the ACC↔noAcc contrast is
**not** a clean acclimation-only comparison.

## What each scheme feeds its fixation-cost function
Call sites in `CNFUNMod.F90` (loop `do j = 1, nlevdecomp`, i.e. over soil layers):

| scheme | cost routine | temperature argument | meaning |
|--------|--------------|----------------------|---------|
| Houlton (`fun_fpg1_nfix`) | `fun_cost_fix` | `tc_soisno(c,j)` | **instantaneous, per-layer** soil T over the rooting profile |
| noAcc (`noACC_*`) | `fun_cost_fix_Bytnerowicz_noAcc` | `tc_soisno(c,j)` | **instantaneous, per-layer** soil T over the rooting profile |
| ACC (`ACC_*`) | `fun_cost_fix_Bytnerowicz_Acc` | `tc_soila10(c)` | **single 10-day running-mean** of the **12 cm** layer, same value for every layer |

- `tc_soisno(c,j) = t_soisno(c,j) - tfrz` (per-layer instantaneous).
- `tc_soila10(c)  = soila10(c) - tfrz`, where `soila10` = "10-day running mean of the 12 cm soil
  layer temp" (col_es). Applied to all layers identically inside the j-loop.

## Consequence
The ACC↔noAcc difference conflates **three** changes, only the first of which is intended:
1. **Acclimation formulation** — Topt/Tmin shift with growth temperature (the science).
2. **Temporal averaging** — ACC uses a 10-day running mean; noAcc/Houlton use instantaneous T.
3. **Vertical treatment** — ACC uses a single 12 cm temperature; noAcc/Houlton use the full
   per-layer profile `tc_soisno(c,j)`.

Therefore **noAcc-vs-Houlton is the clean contrast** (identical temperature input; differ only in
functional form — Houlton exponential vs Bytnerowicz beta). The **ACC arm is confounded** and
should not be presented as a pure acclimation result until the temperature input is harmonized.

Materiality is site-dependent: at warm, thermally-stable Manaus the instantaneous-vs-10-day and
12cm-vs-profile gaps are likely small; at seasonal Harvard/Bonanza they can be large.

## Also note: comment/code mismatch
`ACC_fixed_funp_nfix/CNFUNMod.F90:1856` comments "30-day running mean soil temperature from
SOILTEMP30 accumulator", but the code on the next line uses `soila10` (**10-day**). The intended
averaging window (10 vs 30 day) should be confirmed.

## Recommended resolution (before calling ACC/noAcc a clean acclimation result)
Either (a) feed all three schemes the *same* temperature input (either all per-layer instantaneous
`tc_soisno(c,j)`, or all the same running-mean), so the contrast isolates the formulation; or
(b) keep as-is but document the confound explicitly in the manuscript methods and confine
acclimation claims to what the design can support. Resolving this outranks any further
observational comparison.
