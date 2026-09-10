# ELM-FUN BNFMIP

ELM-FUN contribution to the **Biological Nitrogen Fixation Model Intercomparison
Project (BNFMIP)** — evaluating how the temperature response of biological N
fixation (BNF) shapes model estimates of BNF, NPP, and land carbon storage at a
tropical, temperate, and boreal site under warming and elevated CO₂.

- **Model:** E3SM Land Model (ELM) with the FUN N/P cycling framework
- **Protocol:** Bytnerowicz et al. (2024), *Temperature Response of BNF MIP*
- **Compute:** CADES HPC (ORNL)

---

## Overview

Three single-point sites, four N-fixation schemes, three simulation periods:

| Sites | Experiments | Sections |
|-------|-------------|----------|
| Manaus, BR (tropical) | `nofun_baseline` — FUN off (Houlton default) | §5.3 historical 1850–2014 |
| Harvard Forest, US (temperate) | `fun_transient_only` — Houlton (2008) T-function | §5.4 warming only, fixed CO₂/Ndep @2014 (2015–2100) |
| Bonanza Creek, US (boreal) | `noacc_transient` — Bytnerowicz (2022), no acclimation | §5.5 warming + transient SSP5-8.5 CO₂/Ndep (2015–2100) |
| | `acc_transient` — Bytnerowicz (2022), with acclimation | |

→ 3 × 4 × 3 = **36 output files**. See [`PROTOCOL.md`](PROTOCOL.md) for the full protocol.

## Results

- **[`RESULTS.md`](RESULTS.md)** — headline table + key findings.
- **[`notebooks/BNFMIP_results.ipynb`](notebooks/BNFMIP_results.ipynb)** — headline figures (renders on GitHub):
  BNF latitudinal gradient, the temperature response of BNF, GPP/NPP, and 1850–2100 time series.
- **[`notebooks/BNFMIP_table2_gallery.ipynb`](notebooks/BNFMIP_table2_gallery.ipynb)** — **the full delivered
  Table-2 variable set** (every C/N/P pool & flux + physical vars) exactly as sent to the coordinators,
  plotted across all 3 sites × 4 experiments. This is what the intercomparison receives.

## Reproduce

The full clone-to-results workflow on CADES is in **[`REPRODUCE.md`](REPRODUCE.md)**.
In short:

```bash
git clone git@github.com:braghiere/ELM-FUN-BNFMIP.git
# 1. apply source_mods/ to your E3SM checkout   (the FUN scheme code)
# 2. scripts/per_site/*        create + spin up the cases
# 3. scripts/resubmit_BNFMIP_v2.sh   run §5.3 + §5.4 (all 4 experiments × 3 sites)
# 4. scripts/submit_ssp585_cases.py  run §5.5 (SSP5-8.5 transient)
# 5. scripts/package_table2.py       package raw output into Table-2 deliverables
```

## Repository layout

```
├── README.md              ├── PROTOCOL.md          # BNFMIP §5.3/5.4/5.5 spec
├── REPRODUCE.md            # step-by-step reproduction on CADES
├── RESULTS.md              # results summary
├── docs/                   # corrections, run matrix, site info, global-run plan
├── scripts/                # case creation, submission, packaging, utils  (see scripts/README.md)
│   ├── per_site/           #   per-site case-creation scripts
│   └── utils/              #   pre-flight checks, sanity checks, restart tools
├── source_mods/            # ELM Fortran source modifications (the FUN schemes)
├── namelists/              # user_nl_clm / user_nl_datm templates per phase
├── notebooks/              # results notebook + figures
└── action_log/             # dated scientific-decision log
```

## Scientific corrections

Six pre-delivery corrections are documented in **[`docs/corrections.md`](docs/corrections.md)**
(P double-limitation, free-living fixation rate, `s_fix` cost, §5.4 Ndep locking,
the Manaus §5.5 case-build fix, and the Harvard PFT caveat).

**Post-delivery (2026-09):** two inherited FUN code bugs were found and fixed, the cheap-cost
`s_fix` tuning was reverted to a physical value, and the results were re-evaluated. The full
step-by-step story — bugs → retuning reversal → corrected results → literature evaluation →
open issues — is in **[`docs/POST_DELIVERY_CORRECTIONS.md`](docs/POST_DELIVERY_CORRECTIONS.md)**
(with [FUN_PARAMETER_AUDIT](docs/FUN_PARAMETER_AUDIT.md), [SFIX_DECISION](docs/SFIX_DECISION.md),
and [ACC_TEMPERATURE_CONFOUND](docs/ACC_TEMPERATURE_CONFOUND.md)). Note: the headline table below
reflects the **delivered** runs and predates these corrections.

## Requirements

- **Runs:** CADES access; an E3SM/ELM checkout; [OLMT](https://github.com/dmricciuto/OLMT);
  the CADES `e3sm_inputdata` tree. See [`REPRODUCE.md`](REPRODUCE.md).
- **Post-processing:** Python ≥ 3.9 with `xarray`, `numpy`, `matplotlib`, `netCDF4`
  (and `nbformat`/`jupyter` for the notebook).

## Citation

If you use this configuration or output, please cite the BNFMIP protocol
(Bytnerowicz et al., 2024) and the ELM-FUN framework (Braghiere et al., 2022, *JAMES*).

## Contact

Renato Braghiere — renatob@caltech.edu

## References

- Bytnerowicz et al. (2024) — BNFMIP protocol & temperature-response parameterisation
- Houlton et al. (2008) — CLM default symbiotic N fixation
- Fisher et al. (2010) — FUN framework
- Shi et al. (2016) — FUNP (phosphorus) extension
- Braghiere et al. (2022), *JAMES* — ELM-FUN
