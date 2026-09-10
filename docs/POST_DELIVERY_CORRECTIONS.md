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

➡️ **Dataset to use: [`data_csv_sfixorig/`](../data_csv_sfixorig/)** (bugs fixed + physical
s_fix=−6). It supersedes the delivered `data_csv_corrected/` and has the same layout/units — see
its [README](../data_csv_sfixorig/README.md). (noAcc/Houlton ready; ACC provisional pending the
temperature-roles decision, Step 6.)

Data lineage: `data_csv_corrected/` = delivered (buggy code, s_fix=−0.1); `data_csv_corrected_v2/`
= bugs fixed, s_fix still −0.1; `data_csv_sfixorig/` = bugs fixed + physical s_fix=−6 ("corrected").
All ELM run values below (fluxes, the −93% response, the ~51 upper bound, the fixed/transient
agreement) are computed from these project CSVs — internally consistent model output, **not**
independent observational verification.

---

## Step 1 — Two inherited FUN code bugs (nitrogen only)
Detail: [docs/FUN_PARAMETER_AUDIT.md](FUN_PARAMETER_AUDIT.md)

- **Defect A — `kc_nonmyc`/`kn_nonmyc` swapped.** This is a *documented upstream CLM/CTSM bug*
  ([ESCOMP/CTSM #2120](https://github.com/ESCOMP/CTSM/issues/2120), "Switched parameters for
  non-mycorrhizal N uptake costs in FUN"). It makes non-mycorrhizal uptake too cheap. Live at
  Manaus & Harvard (AM fraction > 0); Bonanza insulated (100% EcM).
- **Defect B — `ivt(p).eq.7` should be `.eq.17`** in the AM N-cost branch (a PFT-index typo).
  Hits Harvard (PFT 7) directly.
- These two defects affect the **N** pathways; the corresponding **P** code did not show these
  errors. Fix applied to all variants and verified (compiles); see [docs/corrections.md](corrections.md).

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
   report ~4–24 kg N/ha/yr symbiotic **across legume-rich Trinidad forest plots, including an
   old-growth stand**. So a low value is niche-specific — not a mature-forest law.
4. **The FUN mechanism is an approximation.** Menge et al. 2023 found tree symbioses can *sustain*
   fixation after N limitation is relieved, showing that cost-based regulation is an approximation
   whose ecological consequences also need evaluation. Persistent fixation challenges *complete*
   downregulation; it does not by itself show ELM's particular allocation algorithm is wrong.
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
| Manaus (mature tropical) | Cleveland 2010 (Rondônia); Barron 2011; Sullivan 2014 (Costa Rica); **counter:** Brookshire 2019 (Trinidad plots incl. old-growth) | tropical symbiotic estimates span a **very wide range**: Cleveland ~4.5–6.8 (Rondônia); Sullivan (Costa Rica) *total* BNF ~1.2 (primary) / ~5.7 (gap-adjusted), corrections unaudited; Brookshire ~4–24 (across legume-rich Trinidad plots incl. old-growth). ELM corrected symbiotic ~1.5–2.1 is at/below the low end | **no verified comparable Manaus measurement identified here**; location/niche/method differ; **do not quote a single "0.2" benchmark** |
| Bonanza (boreal upland) | DeLuca 2002 (feather moss 1.5–2.0); alder chronosequence (different niche) | feather-moss free-living ~1.5–2; ELM total ~2.1 | DeLuca does **not** establish zero vascular symbiotic fixation; ELM's upland column does not represent alder; consistent, not validated |
| Harvard (temperate) | no site BNF measurement (record is N-deposition); temperate BNF spans orders of magnitude | essentially unconstrained | cannot adjudicate |

### Honest assessment (do not overstate in the manuscript)
| question | defensible judgment |
|---|---|
| Corrected ELM more defensible than cheap-cost (~0.1 gC/gN) ELM? | **Yes** — fixation-cost plausibility |
| Is low present-day symbiotic fixation at mature Manaus plausible? | **Yes** — not to be rejected just because other curves are higher |
| Is low symbiotic fixation *universal* in mature tropical forest? | **No** — Brookshire 2019 (legume-rich Trinidad plots incl. old-growth, ~4–24) is a counterexample. *(Disproves universality, not prevalence — the "norm" is unknown.)* |
| Is ELM's cost-based downregulation biologically demonstrated? | **Not fully** — Menge 2023 (fixation persists after N limitation relieved → challenges *complete* downregulation) + Bytnerowicz 2025 (multi-week lags); does not by itself show the algorithm is wrong |
| Has ELM been shown closer to *comparable* Manaus observations? | **Not yet** — no verified comparable Manaus measurement identified; Sullivan is Costa Rica |
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
Verification status is noted per entry. "Primary text checked" = confirmed against the article;
"abstract/record checked" = confirmed identity + headline result; "unverified" = numeric value
still a gap in this audit. **Do not mix quantity types** (leaf-N stocks vs nodule-specific rates
vs annual ecosystem fluxes) on the same axis.

**FUN / cost framework**
- Fisher, J.B., et al. (2010). Carbon cost of plant nitrogen acquisition. *Global Biogeochem.
  Cycles* 24, GB1014. **doi:10.1029/2009GB003621**. *(Model-framework reference; a nominal cost
  temperature response, not a universal physiological calibration.)*
- Menge, D.N.L., et al. (2026). Global Carbon Investment in Terrestrial BNF. *Global Biogeochem.
  Cycles* 40, e2026GB009098. doi:10.1029/2026GB009098. *Primary cost section checked.* *(Flags a
  unit issue: Gutschick's 8–12 g glucose/gN = 3.2–4.8 gC/gN. Synthesis avg ~3–6; models often use
  6–14; adopts **5 (4–6)** — a synthesis choice, not a measured SD. So ELM's 6–10 is much more
  credible than 0.1–0.16 but sits toward/above the synthesis range. 0.29% NPP investment uses
  assumed cost — not independent validation of ELM.)*

**Tropical field evidence — heterogeneous (support AND counter for "low")**
- Cleveland, C.C., Houlton, B.Z., Neill, C., Reed, S.C., Townsend, A.R., Wang, Y. (2010).
  *Biogeochemistry* 99, 1–13. doi:10.1007/s10533-009-9392-y. *Full text checked.* *(Symbiotic
  ~6.8 (model) / ~4.5 (N-balance) kg N/ha/yr, representative forest from central Rondônia; the
  model **assumes a 10 gC/gN fixation cost**. Lower than old extrapolations, NOT ~0.2. Earlier
  drafts misattributed this as "Cusack 2009" — corrected.)*
- Barron, A.R., Purves, D.W., Hedin, L.O. (2011). Facultative N fixation by canopy legumes in a
  lowland tropical forest. *Oecologia* 165, 511–520. *Abstract checked.* *(Near-zero fixation in
  mature N-rich forest; substantial in disturbed forest/gaps. Supports the *plausibility* of the
  downregulation mechanism — sampled trees/habitats, not an annual stand budget.)*
- Sullivan, B.W., et al. (2014). *PNAS* 111, 8101–8106. doi:10.1073/pnas.1320646111. Corrections:
  PMC4517255, PMC4522799 *(located; content not retrieved)*. *Indexed primary text checked.*
  *(Field sites are **Costa Rican, not Amazonian**. Original text: **total** BNF ~1.2 kg N/ha/yr
  undisturbed primary, ~5.7 after a gap-dynamics adjustment. **Do NOT quote "0.2"** — value +
  correction status unresolved. Useful point: spatial coverage & disturbance matter greatly.)*
- Brookshire, E.N.J., et al. (2019). Symbiotic N fixation is sufficient to support net aboveground
  biomass accumulation in a humid tropical forest. *Scientific Reports* 9, 7571.
  doi:10.1038/s41598-019-43962-5. *Full text checked.* *(Legume-rich Trinidad, incl. an old-growth
  stand: plot-mean symbiotic **11.3, plot range 4.1–24.2, subplots 0–67.8** kg N/ha/yr. COUNTER to
  "mature tropical ⇒ near-zero." Not Manaus; extract the exact old-growth plot value before any
  stand comparison.)*
- Costa, T.L., et al. (2024). BNF in young and old tropical forests under five edaphoclimatic
  conditions. *Nutrient Cycling in Agroecosystems* 128, 183–198. *Abstract checked.* *(Age, fixer
  density and environment matter; fixation continues in old forests. **NB: reported kg N/ha are
  leaf-N STOCKS, not annual fluxes** — cannot be placed on a kg N/ha/yr axis.)*

**Regulation & phosphorus — tests of the FUN mechanism**
- Menge, D.N.L., et al. (2023). Tree symbioses sustain N fixation despite excess N supply. *Ecol.
  Monographs* 93, e1562. *Abstract checked.* *(6 tree symbioses, 4–5 yr N addition, isotope
  dilution — all maintained some fixation after N relief. Challenges "cheap soil N ⇒ fixation → 0"
  as a universal rule. Particular trees/conditions, not a Manaus stand flux.)*
- Bytnerowicz, T.A., Griffin, K.L., Menge, D.N.L. (2025). Time lags in the regulation of symbiotic
  N fixation. *New Phytologist* 247, 1680–1693. *Primary text checked.* *(95% downregulation
  31–51 d; upregulation 108–138 d. Instantaneous optimal allocation (FUN) is an approximation;
  motivates growth-temperature memory for acclimation. Direction/magnitude of annual ELM bias
  needs a model experiment.)*
- Cunha, H.F.V., et al. (2022). Direct evidence for phosphorus limitation on Amazon forest
  productivity. *Nature* 608, 558–562. *Abstract checked.* *(Old-growth Amazon: productivity
  responds to **P** addition, not N/base cation. Take P co-limitation seriously; not a BNF
  measurement, and a P cycle in ELM ≠ quantitatively-correct P limitation.)*

**Temperature response (Tom's own data)**
- Bytnerowicz, T.A., Akana, P.R., Griffin, K.L., Menge, D.N.L. (2022). Temperature sensitivity of
  woody N fixation. *Nature Plants* 8, 209–216. *Abstract/figures checked.* *(Optima **29.0–36.9 °C**,
  warmer than the conventional 25.2 °C; acclimation esp. in tropical symbioses. Reproducing the
  executed Houlton function verifies *implementation*, not biological superiority of its warming
  decline. "36 °C exceeds calibration" is under-specified — distinguish GROWTH-temperature
  calibration from instantaneous MEASUREMENT-temperature coverage.)*

**Boreal / temperate**
- DeLuca, T.H., et al. (2002). Quantifying N-fixation in feather moss carpets of boreal forests.
  *Nature* 419, 917–920. doi:10.1038/nature01051. *Bibliographic ID only — 1.5–2.0 passage NOT
  retrieved.* *(Does NOT establish zero vascular symbiotic fixation.)*
- DeLuca, T.H., et al. (2007). Ecosystem controls on N fixation in boreal feather moss communities.
  *Oecologia* 152, 121–130. *Abstract checked.* *(Reciprocal moss transplants → fixation tracks the
  nutrient environment: a **regulated** moss pathway. An ET-derived "free-living" term is not a
  validated moss model; map moss-cyanobacteria explicitly to the model's operational free-living
  category.)*
- Alaska alder chronosequence (Mitchell-led; doi:10.1007/s10533-009-9332-x). *Lead only.* *(Author
  list, ~6.6 kg N/ha/yr, and area denominator UNVERIFIED — excluded as a benchmark. "Alder stand"
  ≠ "black-spruce column with an alder understory.")*
- Harvard Forest: no stand-level BNF measurement verified here (record is N-deposition). Absence in
  this audit is not evidence none exists.

**Global budgets / model evaluation (constrain totals, NOT individual site verdicts)**
- Reis, et al. (2025). Global terrestrial N fixation and its modification by agriculture. *Nature*
  643, 705–711. doi:10.1038/s41586-025-09201-w. Field dataset: doi:10.5066/P1MFBVHK. *Record
  checked.* *(Natural BNF 65 (52–77) Tg N/yr; corrects fixer-abundance oversampling. Global
  aggregate — not a per-site factor. The dataset (location/niche/method/abundance/rate) is the
  right resource for building comparable-observation rows.)*
- Kou-Giesbrecht, S., et al. (2025). Overestimated natural BNF → exaggerated CO₂ fertilization in
  ESMs. *PNAS* 122, e2514628122. doi:10.1073/pnas.2514628122. *Record checked.* *(>50% overestimate
  of present-day natural BNF; mechanistic reps **over-respond to CO₂ (135% vs 31%** experimental
  meta-analysis) — so it does NOT vindicate mechanistic models; ~11% CO₂-fertilization implication
  is an ensemble inference; exact 54% unverified.)*
- Meyerholt, J., Zaehle, S., Smith, M.J. (2016). *Biogeosciences* 13, 1491–1518.
  doi:10.5194/bg-13-1491-2016. *Abstract checked.* *(6 formulations, contemporary global 108–148
  Tg N/yr, but +200 ppm CO₂ response −3% to +42%. Baseline agreement ≠ perturbation agreement.)*

**Upstream code defect**
- ESCOMP/CTSM Issue #2120, "Switched parameters for non-mycorrhizal N uptake costs in FUN."
  https://github.com/ESCOMP/CTSM/issues/2120

## How to evaluate properly (method note)
- **One row per observation**, retaining: stand coordinates, forest age/disturbance, fixer
  abundance, niche, measured quantity, area denominator, observation period, conversion method,
  uncertainty. Never mix leaf-N stocks, nodule-specific rates, and annual ecosystem fluxes.
- Compare a **time-matched present-day** ELM distribution against comparable-observation
  distributions; assess **late-century change separately**, supported by perturbation experiments
  (Menge 2023; Bytnerowicz 2025), not by ratios to contemporary observations.
- Realized fixation cost = **flux-integrated ΣNPP_NFIX / ΣSNFIX** (matched area/time/units); do NOT
  invert an unweighted mean efficiency.
- ACC: **specify the mathematical temperature roles first** (growth-temperature memory vs reaction
  temperature); then align measurement temperature, vertical weighting and forcing while retaining
  intentional acclimation memory (cf. ACC_TEMPERATURE_CONFOUND.md).
