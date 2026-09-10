# ELM-FUN BNFMIP — CORRECTED runs (USE THIS SET)

**This is the corrected dataset. It supersedes `../data_csv_corrected/` (the delivered set) for
the fixation results.** Same layout/units as the delivered set:
`bnfmip_elmfun_table2_annual_long.csv` (tidy long, annual) and
`monthly/<site>_<experiment>_secNN.csv` (full 54-var C/N/P). Same 3 sites × 4 experiments ×
3 sections (§5.3/5.4/5.5).

Full story, figures, and references: **[../docs/POST_DELIVERY_CORRECTIONS.md](../docs/POST_DELIVERY_CORRECTIONS.md)**.

## What changed vs the delivered set (`data_csv_corrected/`)
Two independent corrections:
1. **FUN N-acquisition pathway bugs fixed** — the `kc_nonmyc`/`kn_nonmyc` swap (upstream
   [CTSM #2120](https://github.com/ESCOMP/CTSM/issues/2120)) and a PFT-index typo. N-only; the
   P code did not show these. See [../docs/FUN_PARAMETER_AUDIT.md](../docs/FUN_PARAMETER_AUDIT.md).
2. **`s_fix` reverted −0.1 → −6** (the physical CLM5/6 default). The delivered set's realized
   fixation cost was ~0.1–0.16 gC/gN (unphysically cheap, a tuning artifact); this set realizes
   ~6–10 gC/gN. See [../docs/SFIX_DECISION.md](../docs/SFIX_DECISION.md).

## Effect on the numbers
- **Symbiotic BNF (`NFIX_TO_SMINN` / SNFIX) drops ~93%** vs delivered (Manaus 2090s: 17–26 →
  1.2–2.0 kg N/ha/yr) and the realized C cost is now physical.
- **NPP, ecosystem C, and total N uptake change <1.5%** — nearly identical trajectories under both
  §5.4 (fixed CO₂) and §5.5 (transient); the plant compensates via other N-acquisition pathways.
- N-acquisition **pathway partitioning is corrected** (delivered had an ecologically-backwards
  ~3% mycorrhizal / ~66% non-myc split at Manaus/Harvard).
- Free-living fixation (`FFIX_TO_SMINN` / FNFIX) is unchanged (prescribed ET term, s_fix-independent).

## Status / caveats
- **noAcc and Houlton** are clean and ready to use.
- **ACC (acclimation) is provisional:** its cost routine currently uses a 10-day-mean temperature
  at 12 cm for the whole calculation, while noAcc/Houlton use the instantaneous per-layer profile —
  so the ACC↔noAcc contrast mixes acclimation with a temperature-basis difference. Pending a
  decision on the intended temperature roles. See
  [../docs/ACC_TEMPERATURE_CONFOUND.md](../docs/ACC_TEMPERATURE_CONFOUND.md).
- These are corrected **ELM model outputs**, not independent observational verification; no
  site-level "winner" vs other BNFMIP models is claimed (see POST_DELIVERY_CORRECTIONS.md §5).
- Boreal (Bonanza) SMINN over-accumulation, high soil C, and the P-pool definitions carry over
  from the delivered set (documented there) — unrelated to these corrections.

## FUN carbon-cost diagnostics
Same variables as the delivered set (NPP_NUPTAKE, NPP_NACTIVE, NPP_NFIX, COST_NFIX, COST_NACTIVE,
…). **Units note:** `COST_NFIX`/`COST_NACTIVE` are stored as **gN/gC efficiency** (= 1/cost); the
realized carbon cost is the flux-integrated **ΣNPP_NFIX / ΣSNFIX**, NOT `1/mean(COST_NFIX)`.
In this set the realized fixation cost is ~6–10 gC/gN (physical), vs ~0.1–0.16 in the delivered
set. See [../docs/corrections.md](../docs/corrections.md).
