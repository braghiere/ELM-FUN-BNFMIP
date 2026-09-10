# Post-delivery corrections & evaluation — the full story (2026-09)

This is the step-by-step record of what changed **after** the 2026-07 BNFMIP delivery
([RESULTS.md](../RESULTS.md)), why, and what we can and cannot conclude from it. It is the
backbone document; each step links to the detailed doc, figure, and data.

**One-line status:** two inherited FUN code bugs were found and fixed; the pre-existing
"make fixation cheap" tuning was reverted to a physical cost; corrected symbiotic fixation is
much lower and its carbon-cycle footprint is small; whether ELM is *more correct* than the other
BNFMIP models is **not established** — only that its revised cost has a stronger physiological
basis than the cheap-cost configuration. One implementation issue (ACC temperature input) is
still open.

Data: `data_csv_corrected/` = delivered (buggy code, s_fix=−0.1); `data_csv_corrected_v2/` =
bugs fixed, s_fix still −0.1; `data_csv_sfixorig/` = bugs fixed + physical s_fix=−6 ("corrected").

---

## Step 1 — Two inherited FUN code bugs (nitrogen only)
Detail: [docs/FUN_PARAMETER_AUDIT.md](FUN_PARAMETER_AUDIT.md)

- **Defect A — `kc_nonmyc`/`kn_nonmyc` swapped.** This is a *documented upstream CLM/CTSM bug*
  ([ESCOMP/CTSM #2120](https://github.com/ESCOMP/CTSM/issues/2120), "Switched parameters for
  non-mycorrhizal N uptake costs in FUN"). It makes non-mycorrhizal uptake too cheap. Live at
  Manaus & Harvard (AM fraction > 0); Bonanza insulated (100% EcM).
- **Defect B — `ivt(p).eq.7` should be `.eq.17`** in the AM N-cost branch (a PFT-index typo).
  Hits Harvard (PFT 7) directly.
- Phosphorus pathway checked and **clean**. Fix applied to all variants and verified (compiles);
  see [docs/corrections.md](corrections.md).

These bugs distort the **N-acquisition pathway partitioning** (mycorrhizal vs non-myc vs
fixation) at Manaus & Harvard — the delivered runs show an ecologically-backwards ~3%
mycorrhizal / ~66% non-myc split.

---

## Step 2 — The "retuning that doesn't make sense" (`s_fix`)
Detail: [docs/SFIX_DECISION.md](SFIX_DECISION.md) · figure: [fixation_cost_two_panel.png](../analysis/figs/fixation_cost_two_panel.png)

Earlier, `s_fix` had been tuned to **−0.1** to lift symbiotic fixation, because the original
physical-cost rates looked implausibly low next to the other models. That tuning is **not
physically defensible**:

- The **realized** fixation cost (flux-integrated ΣNPP_NFIX/ΣSNFIX) under s_fix=−0.1 is
  **~0.1–0.16 gC/gN** — an order of magnitude below any synthesis estimate.
- Restoring the physical **s_fix=−6** (CLM5/6 default) gives a realized cost of **~6–10 gC/gN**
  (Bytnerowicz ~6.2; Houlton 7.5 present → 10.0 future as Manaus soil warms past the 25.15 °C
  cost-optimum). This is physiologically plausible: at/above Menge et al. 2026's synthesis
  central of ~5 (4–6), overlapping the lower Fisher 2010 nominal (7.5–12.5).

**This is the one clean verdict:** corrected ELM (s_fix=−6) is **more defensible than the
cheap-cost configuration** on fixation-cost plausibility. We keep −6 as a **reference**, not a
calibration. (Units caveat: the `COST_NFIX` diagnostic is stored as gN/gC efficiency, not gC/gN;
do not invert its mean — see [corrections.md](corrections.md).)

---

## Step 3 — What the correction does to the carbon cycle
Figure: [delivered_vs_corrected_trajectories.png](../analysis/figs/delivered_vs_corrected_trajectories.png)

Delivered → corrected at Manaus, future 2090s (**near-identical under §5.4 fixed-CO₂ and §5.5
transient**):

| variable | delivered → corrected | change |
|---|---|---|
| Symbiotic BNF | 17–26 → 1.2–2.0 kg N/ha/yr | **−93%** |
| NPP | 1032 → 1028 gC/m²/yr | −0.4% |
| Ecosystem C | 46,420 → 46,150 gC/m² | −0.6% |
| Total N uptake | 272 → 268 kg N/ha/yr | −1.5% |

A large fixation correction, a **small** C-cycle footprint (the plant compensates via other
N-acquisition pathways). Trajectories stay stable, same direction, scheme-ordered. Scheme
differences (Houlton/noAcc/Acc) **persist** and are slightly more distinguishable after the fix.

---

## Step 4 — Why "same FUN code" gives very different BNF across models
Figure: [sfix_sweep_brackets_panel.png](../analysis/figs/sfix_sweep_brackets_panel.png)

"Same FUN code" only means the same fixation-cost *subroutine*. The fixation *flux* is an
**emergent** outcome of an optimization (buy N from the cheapest source until demand is met), so
it depends on (a) fixation cost, (b) the cost of **every competing pathway**, and (c) how
**N-limited** the ecosystem is. Evidence: **ELM's own** Manaus symbiotic BNF spans ~2 → ~26
kg/ha just by flipping s_fix (−6 → −0.1), bracketing essentially the whole intermodel panel
(~20–45). ELM ≠ CLM5 in the surrounding machinery (ELM runs **FUN-P** phosphorus co-limitation;
different soil BGC/mineralization; the #2120 params; spinup). So the intermodel spread is
plausibly an **emergent-property difference (N/P limitation + parameterization within a shared
FUN framework), not an algorithmic one** — a hypothesis to test with each model's config, not a
verdict.

---

## Step 5 — Which model is "most correct"? (careful answer)
Observational basis (per site, with caveats): see table below.

**We can defend that low symbiotic fixation is plausible. We cannot, with verified evidence,
declare a model winner.** Four reasons the strong claim fails:

1. **Time mismatch.** The other models' 20–45 kg/ha are *future* (post-2015, under CO₂+warming);
   0.2 is a *contemporary* measurement. Present-day must be evaluated against contemporary obs;
   the future *response* is a separate question. Similar present-day totals can accompany very
   different CO₂ responses ([Meyerholt et al. 2016](https://bg.copernicus.org/articles/13/1491/2016/)).
2. **Sullivan (0.2) is unverified here** — sampling scope, stand-level and annual integration not
   confirmed. Conditional arithmetic is fine ("*if* comparable, ELM's 1–2 is closer than 20–45");
   an unconditional ranking is not.
3. **Global budgets ≠ site verdicts.** Reis 2025's downward global revision and Kou-Giesbrecht
   2025's ~54% global overestimate don't identify the best model at Manaus. Menge's 0.29%
   investment depends on assumed cost — not an independent validation of ELM.
4. **Feather-moss ≠ zero vascular symbiotic at Bonanza.** DeLuca supports another fixing niche's
   importance; matching its magnitude with an ET-based free-living term is context, not proof
   ELM's symbiotic suppression is correct.

### Time-matched present-day (2005–2014) corrected ELM (kg N/ha/yr)
| site | symbiotic (corr) | total (corr) | delivered symbiotic |
|---|---|---|---|
| Manaus | 1.5–2.1 | 9.1–9.6 | 26–30 |
| Harvard | 0.9–1.5 | 4.8–5.4 | 15–18 |
| Bonanza | 0.0 | 2.1 | 0.0 |

### Observational context (leads, several still need primary verification)
| site | relevant studies | rough magnitude | status |
|---|---|---|---|
| Manaus (mature tropical) | Sullivan 2014 (symbiotic); Cusack 2009 (indirect); terra-firme oxisol root-assoc. | symbiotic low (~0.2); total free-living-dominated (~2–15) | Sullivan value unverified for this stand/scale |
| Bonanza (boreal upland) | DeLuca 2002 (feather moss 1.5–2.0); Ruess (alder ~6.6, different niche) | free-living ~2; vascular symbiotic ~0 in mature black spruce | niche-dependent; ELM total consistent, not validated |
| Harvard (temperate) | no site BNF measurement (record is N-deposition); temperate BNF spans orders of magnitude | essentially unconstrained | cannot adjudicate |

### Honest assessment (do not overstate in the manuscript)
| question | defensible judgment |
|---|---|
| Corrected ELM more defensible than cheap-cost (~0.1 gC/gN) ELM? | **Yes** — fixation-cost plausibility |
| Is low present-day symbiotic fixation at mature Manaus plausible? | **Yes** — not to be rejected just because other curves are higher |
| Has ELM been shown closer to *comparable* Manaus observations? | **Not yet** with verified evidence |
| Is ELM's future response more accurate? | **Unresolved** |
| Does ELM "win" at Bonanza or Harvard? | **Not established** |

---

## Step 6 — Open implementation issue: ACC temperature input
Detail: [docs/ACC_TEMPERATURE_CONFOUND.md](ACC_TEMPERATURE_CONFOUND.md)

In v3 source, the ACC (acclimation) scheme feeds its cost function `tc_soila10` (10-day running
mean, single 12 cm layer) while noAcc and Houlton feed `tc_soisno(c,j)` (instantaneous,
per-layer rooting profile). So **ACC↔noAcc conflates acclimation formulation + temporal averaging
+ vertical treatment**; only noAcc-vs-Houlton is a clean contrast. Also a 30-day-comment /
10-day-code (`soila10`) mismatch. **Should be harmonized (or documented as a methods caveat)
before the ACC/noAcc contrast is presented as clean acclimation.** This outranks further
observational comparison.

---

## Step 7 — How to proceed (open questions)
1. **ACC temperature harmonization** — feed all three schemes the same temperature input and
   re-run (Manaus/Harvard FUN/noAcc/ACC), or document the confound as a methods caveat this round?
2. **Per-model manifest** — for the symbiotic-BNF panel, confirm each model's variable definition
   (symbiotic vs total), cost treatment, and forcing. This tests whether the high curves reflect a
   cheaper cost or higher N demand (Step 4), and whether the panel compares like with like.
3. **Present-day vs future evaluation, separated** — evaluate present-day BNF against contemporary
   obs first; treat the future response as its own analysis (Step 5, reason 1).
4. **Sullivan (and site-obs) audit** — verify sampling scope/scale before using any field value as
   a target.
