# ELM-FUN BNFMIP

**ELM-FUN participation in the Biological Nitrogen Fixation Model Intercomparison Project (BNFMIP)**

> Protocol: Bytnerowicz et al. (in prep), March 2024  
> Model: E3SM Land Model (ELM) with FUN N/P cycling framework  
> Contact: Renato Braghiere (braghiere@gmail.com / braghiere@jpl.nasa.gov)  
> Compute: CADES HPC (ORNL), `batch` partition, account `ccsi`

---

## Overview

This repository contains all scripts, source-code modifications, namelist templates, and documentation for running ELM-FUN at three BNFMIP sites as part of the BNF MIP. Four experiments are run at each site following the protocol's Sections 5.3, 5.4, and 5.5.

### Sites

| Code | Site | Biome | Soil Order | P-cycle file |
|------|------|-------|------------|-------------|
| `BNF-Man` | Manaus, Brazil | Tropical | Oxisols (order 4) | `CNP_parameters_manaus_oxisol_v2.nc` |
| `BNF-Ha1` | Harvard Forest, MA | Temperate | Inceptisols (order 5) | `CNP_parameters.nc` (US-Ha1) |
| `BNF-Bon` | Bonanza Creek, AK | Boreal | Inceptisols (order 5) | `CNP_parameters.nc` (US-Bon) |

### Experiments

| # | Label | N-fixation | FUN/FUNP | SourceMods |
|---|-------|------------|----------|------------|
| 1 | `nofun_baseline` | Houlton CLM default (off) | OFF | `control_fixed_funp_nfix` |
| 3 | `fun_transient_only` | Houlton (ELM-FUN default) | ON | `fun_fpg1_nfix` |
| 4 | `noacc_transient` | Bytnerowicz no-acclimation | ON | `noACC_fixed_funp_nfix` (Manaus) / `noACC_temperate_funp_nfix` (Ha1, Bon) |
| 5 | `acc_transient` | Bytnerowicz with acclimation | ON | `ACC_fixed_funp_nfix` (Manaus) / `ACC_temperate_funp_nfix` (Ha1, Bon) |

> **Exp 2** (FUN with FPG=1 global) is excluded from this submission set.

### Protocol Phases

| Phase | Compset | Period | CO₂ | Ndep |
|-------|---------|--------|-----|------|
| 5.3 — Historical transient | `I20TRCNPRDCTCBC` | 1850–2014 | Transient | Transient (RCP8.5) |
| 5.4 — Fixed CO₂+Ndep | `IRCP85CNPRDCTCBC` | 2015–2100 | Fixed at 2015 | Fixed at 2015 |
| 5.5 — Varying CO₂+Ndep | `I20TRCNPRDCTCBC` | 2015–2100 | SSP5-8.5 | RCP8.5 |

---

## Run Matrix

Full 45-run matrix → [`docs/run_matrix.md`](docs/run_matrix.md)

**Per-site spinup chain** (Exp 1 = nofun_baseline):
```
AD Spinup (200 yr, FUN OFF)
  └─ iniadjust
      └─ Regular FN Spinup (600 yr, FUN OFF)   ──→ yr-751 restart
          └─ [Exps 3/4/5] FUN Spinup (FUN ON, branches from FN yr-751)
              └─ Historical 5.3 (1850–2014)
                  ├─ Future 5.5 (2015–2100, transient CO₂+Ndep)
                  └─ Future 5.4 (2015–2100, fixed CO₂+Ndep)
```

---

## Repository Structure

```
ELM-FUN-BNFMIP/
├── README.md                          # This file
├── PROTOCOL.md                        # BNFMIP protocol summary
├── .gitignore
├── docs/
│   ├── run_matrix.md                  # Full 45-run table
│   ├── corrections.md                 # Scientific bug fixes applied
│   └── site_info.md                   # Site-specific configuration details
├── scripts/
│   ├── submit_all_BNFMIP.sh           # Master launcher (all sites × all exps)
│   ├── submit_section54_fixed.sh      # Section 5.4: fixed CO₂+Ndep future runs
│   ├── sites/
│   │   ├── manaus/                    # Per-experiment scripts for Manaus
│   │   ├── ha1/                       # Per-experiment scripts for Harvard Forest
│   │   └── bon/                       # Per-experiment scripts for Bonanza Creek
│   └── utils/
│       ├── check_bnf_sanity.py        # Verify key output variables
│       ├── verify_submit_env.sh       # Pre-flight environment check
│       └── adjust_restart.py          # Restart file utilities
├── source_mods/
│   ├── README.md                      # Explains each SourceMods set
│   ├── control_fixed_funp_nfix/       # Exp 1: nofun_baseline
│   ├── fun_fpg1_nfix/                 # Exp 3: fun_transient_only (Houlton)
│   ├── noACC_fixed_funp_nfix/         # Exp 4: Manaus (tropical params)
│   ├── noACC_temperate_funp_nfix/     # Exp 4: Ha1 + Bon (temperate/boreal)
│   ├── ACC_fixed_funp_nfix/           # Exp 5: Manaus (tropical params)
│   ├── ACC_temperate_funp_nfix/       # Exp 5: Ha1 + Bon (temperate/boreal)
│   └── _shared_elm_fun_col_es/        # Shared ELM col_es wiring (all exps)
├── namelists/
│   ├── README.md
│   ├── user_nl_clm.spinup_nofun.template
│   ├── user_nl_clm.spinup_fun.template
│   ├── user_nl_clm.transient_nofun.template
│   ├── user_nl_clm.transient_fun.template
│   ├── user_nl_clm.section54_fixed.template
│   └── user_nl_datm.clm1pt.template
└── action_log/
    ├── 01_double_p_limitation.md
    ├── 02_freelivfix_slope.md
    ├── 03_sfix_cold_pfts.md
    ├── 04_nuptake_analysis.md
    ├── 05_notebook_time_month.md
    ├── 06_notebook_lit_refs.md
    └── 07_summary.md
```

---

## Quick Start

### Prerequisites

```bash
# Must run on a compute node (not login node)
srun -A ccsi -p burst -N 1 -n 1 -t 4:00:00 --mem 32G \
     --exclude=or-condo-c105,or-condo-c67,or-condo-c04 --pty bash

# Source environment
source ~/elm_env_cades_gcc12.sh

# Verify environment
cd /home/braghiere/ELM-FUN-BNFMIP/scripts
bash utils/verify_submit_env.sh
```

### Submit ALL experiments (Phases 5.3 + 5.5)

```bash
cd /home/braghiere/BNF_tom/OLMT_BNF
bash /home/braghiere/ELM-FUN-BNFMIP/scripts/submit_all_BNFMIP.sh
```

This submits:
1. Exp 1 (nofun_baseline) full pipeline for all 3 sites in parallel
2. Builder jobs (wait for nofun FN spinup yr-751), then launch Exps 3/4/5

### Submit Section 5.4 (fixed CO₂+Ndep)

```bash
# After I20TR transients reach 2015-01-01
bash /home/braghiere/ELM-FUN-BNFMIP/scripts/submit_section54_fixed.sh \
     <NOFUN_CASEID_MANAUS> <NOFUN_CASEID_HA1> <NOFUN_CASEID_BON>
```

### Monitor

```bash
squeue -u $USER --format="%.10i %.8P %.40j %.2t %.10M %R"
```

---

## Key Configuration Parameters

### Forcings

| Site | CLM1PT directory |
|------|-----------------|
| Manaus | `/home/braghiere/BNF_tom/inputdata/BNFMIP_forcing_from_OCN/BNF_Man/CLM1PT_data` |
| Harvard Forest | `/home/braghiere/BNF_tom/inputdata/BNFMIP_forcing_from_OCN/BNF_Har/CLM1PT_data` |
| Bonanza Creek | `/home/braghiere/BNF_tom/inputdata/BNFMIP_forcing_from_OCN/BNF_Bon/CLM1PT_data` |

### Parameter Files

| Use | File |
|-----|------|
| Manaus CLM params (Exps 1/3) | `clm_params_fun3_sfix01_manaus_tuned.nc` |
| Ha1/Bon CLM params (Exps 1/3) | `clm_params_fun3_sfix01.nc` |
| All sites — Exps 4/5 | `clm_params_fun3_sfix6_manaus_tuned.nc` / `clm_params_fun3_sfix6.nc` |
| Cold-PFT s_fix params | `clm_params_fun3_sfix1_cold_pft.nc` |
| Manaus oxisol CNP | `CNP_parameters_manaus_oxisol_v2.nc` |

### Bytnerowicz Temperature Parameters

| Biome | Site | Tmin (°C) | Topt (°C) | Tmax (°C) |
|-------|------|-----------|-----------|-----------|
| Tropical | Manaus | 7.04 | 33.22 | 45.35 |
| Temperate | Harvard Forest | −2.04 | 32.10 | 43.98 |
| Boreal | Bonanza Creek | −2.04 | 32.10 | 43.98 |

---

## Scientific Corrections Applied

See [`docs/corrections.md`](docs/corrections.md) for full details.

| # | Bug | Fix | Affects |
|---|-----|-----|---------|
| 1 | `fpg_p` double P-limitation when `use_funp=.true.` | `if(.not. use_funp) fpg_p = sminp/demand; else fpg_p = 1.0` | All FUN spinup + transients |
| 2 | `freelivfix_slope` too high → unrealistic free-living N fixation | Reduced from `6.0e-4` to `0.5e-4` | All FUN experiments |
| 3 | `s_fix` too low → near-zero symbiotic N fixation cost | Increased to `-6.0` for warm PFTs, `-1.0` for cold PFTs (1,2,3,8,11,12) | All FUN experiments |
| 4 | Section 5.4 Ndep not locked to 2015 | Added `stream_year_first_ndep = 2015` + `stream_year_last_ndep = 2015` | IRCP85 cases only |

---

## E3SM / CIME Setup

```
SRCROOT:   /home/braghiere/BNF_tom/E3SM_global_silent
CASEROOT:  /home/braghiere/BNF_tom/OLMT_BNF/cime_case_dirs/
RUNROOT:   /lustre/or-scratch/cades-ccsi/scratch/braghiere
ACCOUNT:   ccsi
PARTITION: batch (submit) / burst (build)
```

---

## References

- Bytnerowicz et al. (in prep) — BNFMIP protocol and temperature-response parameterisation
- Houlton et al. (2008) — CLM default symbiotic N fixation
- Fisher et al. (2010) — FUN (Fixation and Uptake of Nitrogen) framework
- Shi et al. (2016) — FUN P extension (FUNP)
- Ricciuto et al. — OLMT (Offline Land Model Testbed)
