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
**N-limited** the ecosystem is. Evidence: **ELM's own** Manaus symbiotic BNF (future 2090s)
spans ~1.2 (corrected: bugs fixed + physical cost) → ~46–51 (v2: bugs fixed + cheap cost) →
~17–26 (delivered: buggy + cheap cost) — an **order-of-magnitude sensitivity to configuration**,
where the pathway-bug fix *raises* fixation and the physical scalar *lowers* it (opposite
directions; see [sfix_sweep_brackets_panel.png](../analysis/figs/sfix_sweep_brackets_panel.png)).
ELM ≠ CLM5 in the surrounding machinery too (ELM runs **FUN-P** phosphorus co-limitation;
different soil BGC/mineralization; the #2120 params; spinup). **What this shows:** the flux is set
by fixation cost *and* competing N-acquisition pathways, so both need examination. **What it does
NOT show:** it does not identify the cause of the intermodel spread or rule out implementation
differences — that needs each model's config (a hypothesis to test, not a verdict).

---

## Step 5 — Which model is "most correct"? (careful answer)
Observational basis (per site, with caveats): see table below.

**We can defend that low symbiotic fixation is plausible. We cannot, with verified evidence,
declare a model winner** — and there is genuine counterevidence. Five reasons the strong claim fails:

1. **Time mismatch.** The other models' 20–45 kg/ha are *future* (post-2015, under CO₂+warming);
   the field estimates are *contemporary*. Present-day must be evaluated against contemporary obs;
   the future *response* is a separate question. Similar present-day totals can accompany very
   different CO₂ responses ([Meyerholt et al. 2016](https://bg.copernicus.org/articles/13/1491/2016/)).
2. **No verified Manaus benchmark.** Sullivan 2014's field component is in **Costa Rica**, not
   Amazonia (and has a published correction); Cleveland 2010 is Rondônia (~4.5–6.8, not 0.2).
   There is no time-/niche-/scale-matched Manaus measurement to rank against.
3. **Counterevidence that mature tropical ≠ near-zero.** [Brookshire et al. 2019](https://doi.org/10.1038/s41598-019-43962-5)
   report ~4–24 kg N/ha/yr symbiotic in legume-rich Trinidad forest *including old-growth*. So a
   low value is niche-specific, not a mature-forest law.
4. **The FUN mechanism itself is challenged.** Menge et al. 2023 found tree symbioses *sustained*
   fixation after N additions relieved N limitation — so "soil N available ⇒ fixation shuts down"
   (ELM's instantaneous cost-competition) is a modeling approximation, not a demonstrated rule.
   Tom's 2025 data (31–138-day regulation lags) point the same way.
5. **Global budgets ≠ site verdicts.** Reis 2025 (downward global revision) and Kou-Giesbrecht 2025
   (>50% overestimate — but which *also* faults mechanistic models for over-responding to CO₂,
   135% vs 31%) constrain totals, not the best model at Manaus. Menge 2026's 0.29% depends on
   assumed cost — not an independent validation of ELM. And feather-moss (DeLuca) does not establish
   zero vascular symbiotic at Bonanza.

### Time-matched present-day (2005–2014) corrected ELM (kg N/ha/yr)
| site | symbiotic (corr) | total (corr) | delivered symbiotic |
|---|---|---|---|
| Manaus | 1.5–2.1 | 9.1–9.6 | 26–30 |
| Harvard | 0.9–1.5 | 4.8–5.4 | 15–18 |
| Bonanza | 0.0 | 2.1 | 0.0 |

### Observational context (leads, several still need primary verification)
| site | relevant studies | rough magnitude | status |
|---|---|---|---|
| Manaus (mature tropical) | Cleveland 2010 (Rondônia); Barron 2011; Sullivan 2014 (Costa Rica field); **counter:** Brookshire 2019 (Trinidad old-growth) | symbiotic estimates span a **very wide range**: ~0.2 (Sullivan, Costa Rica) → ~4.5–6.8 (Cleveland, Rondônia) → ~4–24 (Brookshire, legume-rich Trinidad old-growth). ELM corrected ~1.5–2.1 is at the **low end** | **no Manaus measurement**; location/niche/method differ; mature tropical is NOT universally low |
| Bonanza (boreal upland) | DeLuca 2002 (feather moss 1.5–2.0); alder chronosequence (different niche) | feather-moss free-living ~1.5–2; ELM total ~2.1 | DeLuca does **not** establish zero vascular symbiotic fixation; ELM's upland column does not represent alder; consistent, not validated |
| Harvard (temperate) | no site BNF measurement (record is N-deposition); temperate BNF spans orders of magnitude | essentially unconstrained | cannot adjudicate |

### Honest assessment (do not overstate in the manuscript)
| question | defensible judgment |
|---|---|
| Corrected ELM more defensible than cheap-cost (~0.1 gC/gN) ELM? | **Yes** — fixation-cost plausibility |
| Is low present-day symbiotic fixation at mature Manaus plausible? | **Yes** — not to be rejected just because other curves are higher |
| Is low symbiotic fixation the mature-tropical *norm*? | **No** — Brookshire 2019 (old-growth Trinidad ~4–24) shows it is niche-dependent |
| Is ELM's instantaneous cost-competition downregulation biologically demonstrated? | **No** — Menge 2023 (fixation persists when N relieved) + Bytnerowicz 2025 (multi-week regulation lags) |
| Has ELM been shown closer to *comparable* Manaus observations? | **Not yet** — no verified Manaus benchmark; Sullivan is Costa Rica |
| Is ELM's future response more accurate? | **Unresolved** (and Kou-Giesbrecht faults mechanistic CO₂ over-response) |
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

---

## References
Verification status noted where a value/claim still needs primary confirmation.

**FUN / cost framework**
- Fisher, J.B., et al. (2010). Carbon cost of plant nitrogen acquisition: a mechanistic, globally
  applicable model of plant N uptake, retranslocation, and fixation. *Global Biogeochem. Cycles*
  24, GB1014.
- Menge, D.N.L., et al. (2026). Global Carbon Investment in Terrestrial Biological Nitrogen
  Fixation. *Global Biogeochem. Cycles* 40, e2026GB009098. doi:10.1029/2026GB009098. *(0.29%
  investment depends on assumed BNF and cost — not an independent validation.)*

**Site / niche observations — support for lower fixation**
- Cleveland, C.C., Houlton, B.Z., Neill, C., Reed, S.C., Townsend, A.R., Wang, Y. (2010). Using
  indirect methods to constrain symbiotic N fixation rates: a case study from an Amazonian rain
  forest. *Biogeochemistry*. doi:10.1007/s10533-009-9392-y. *(Symbiotic BNF ~4.5 kg N/ha/yr by
  mass balance, ~6.8 by modeling, Rondônia — LOWER than old extrapolations but well ABOVE 0.2.
  Earlier drafts misattributed this as "Cusack 2009" and as corroborating a low value — corrected.)*
- Barron, A.R., et al. (2011). *(Canopy legumes in mature, N-rich tropical forest show near-zero
  fixation, with substantial fixation in disturbed forest/gaps.)* Supports the *plausibility of the
  downregulation mechanism*, not a Manaus magnitude. Needs primary confirmation.
- Sullivan, B.W., et al. (2014). *PNAS* 111, 8101–8106. doi:10.1073/pnas.1320646111. **Correction:**
  doi:10.1073/pnas.1511978112. *(Multi-site tropical study; the FIELD component is in Costa Rica
  (Piro), NOT Amazonia. Do NOT cite as "measured mature Amazon ~0.2"; a published correction
  exists and the exact quoted value still needs re-checking.)*
- DeLuca, T.H., et al. (2002). Quantifying nitrogen-fixation in feather moss carpets of boreal
  forests. *Nature* 419, 917–920. doi:10.1038/nature01051. *(Feather-moss niche ~1.5–2.0 kg
  N/ha/yr — exact passage unverified here; does NOT establish zero vascular symbiotic fixation.)*

**Site / niche observations — counterevidence (mature tropical is NOT universally near-zero)**
- Brookshire, E.N.J., et al. (2019). Symbiotic N fixation is sufficient to support net aboveground
  biomass accumulation in a humid tropical forest. *Scientific Reports* 9. doi:10.1038/s41598-019-43962-5.
  *(Legume-rich Trinidad forests INCLUDING an old-growth stand: plot-level symbiotic ~11.3, range
  4.1–24.2 kg N/ha/yr per the review. Direct counter to "mature tropical ⇒ near-zero." Not Manaus.)*
- Menge, D.N.L., et al. (2023). *(All six studied tree symbioses SUSTAINED fixation after multiyear
  N additions relieved N limitation.)* Challenges the FUN premise that "soil N available ⇒ fixation
  shuts down" as a general biological rule. Needs primary confirmation.
- Cunha, H.F.V., et al. (2022). *(Old-growth central-Amazon fertilization: productivity responds to
  P addition.)* Supports examining P co-limitation in the comparison; does not validate ELM's BNF.

**Fixation temperature response & regulation timescales (Tom's own data)**
- Bytnerowicz, T.A., et al. (2022). Temperature sensitivity of woody N fixation. *Nature Plants* 8,
  209–216. *(Woody-fixation temperature optima ~29–36.9 °C — ABOVE Houlton's conventional ~25 °C
  optimum. So Houlton's warming cost penalty at hot Manaus is a property of that scheme, not a
  demonstrated biological preference. "36 °C exceeds calibration" must distinguish GROWTH from
  instantaneous MEASUREMENT temperature.)*
- Bytnerowicz, T.A., et al. (2025). *(Regulation delays: ~31–51 days for 95% downregulation,
  ~108–138 days for upregulation.)* Instantaneous cost-competition (FUN) is a modeling
  approximation, not a demonstrated account of plant behavior — and motivates a running-mean
  temperature for acclimation (cf. ACC_TEMPERATURE_CONFOUND.md).

**Global budgets / model evaluation (constrain totals, NOT individual site verdicts)**
- Reis, et al. (2025). Global terrestrial N fixation and its modification by agriculture. *Nature*
  643, 705–711. doi:10.1038/s41586-025-09201-w. *(Natural BNF ~65 Tg N/yr, ~one-third of legacy
  195.)*
- Kou-Giesbrecht, S., et al. (2025). Overestimated biological N fixation translates to exaggerated
  CO₂ fertilization effect in Earth system models. *PNAS* 122, e2514628122.
  doi:10.1073/pnas.2514628122. *(>50% overestimate of present-day natural BNF confirmed; ALSO
  reports that mechanistic models OVER-respond to CO₂ — 135% vs 31% in the cited experimental
  meta-analysis. So it does NOT support "mechanistic models are right"; the exact 54% is unverified.)*
- Meyerholt, J., Zaehle, S., Smith, M.J. (2016). Variability of projected terrestrial biosphere
  responses to elevated CO₂ due to uncertainty in biological N fixation. *Biogeosciences* 13,
  1491–1518. doi:10.5194/bg-13-1491-2016. *(Similar present-day totals can accompany very
  different CO₂ responses — present ≠ future evaluation.)*

**Upstream code defect**
- ESCOMP/CTSM Issue #2120, "Switched parameters for non-mycorrhizal N uptake costs in FUN."
  https://github.com/ESCOMP/CTSM/issues/2120
