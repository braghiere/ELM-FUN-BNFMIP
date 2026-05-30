# ELM-FUN BNFMIP

**ELM-FUN participation in the Biological Nitrogen Fixation Model Intercomparison Project (BNFMIP)**

> Protocol: Bytnerowicz et al. (in prep), March 2024  
> Model: E3SM Land Model (ELM) with FUN N/P cycling framework  
> Contact: Renato Braghiere (braghiere@gmail.com)  
> Compute: CADES HPC (ORNL), `batch` partition, account `ccsi`

---

## Canonical Cases

All production runs use date stamp **`20260521`** (spinup + 5.3/5.5 transients)
and **`20260529_fixed`** (Section 5.4, fixed CO₂+Ndep). Older date-stamped cases
(0226, 0302, 0313–0325, 0403, 0404, 0519, 0520) are superseded.

| Phase | Date stamp | Compset | Period | CO₂ | Ndep |
|-------|-----------|---------|--------|-----|------|
| AD spinup | `20260521` | `I1850CNRDCTCBC` | 200 yr | pre-ind | pre-ind |
| FN spinup (nofun) | `20260521` | `I1850CNPRDCTCBC` | 600 yr | pre-ind | pre-ind |
| FUN spinup | `20260521_funsp` | `I1850CNPRDCTCBC` | 200 yr | pre-ind | pre-ind |
| Sec. 5.3 / 5.5 historical+future | `20260521` | `I20TRCNPRDCTCBC` | 1850–2100 | transient | RCP8.5 |
| **Sec. 5.4 fixed CO₂+Ndep** | **`20260529_fixed`** | `I20TRCNPRDCTCBC` | 2015–2100 | **397.7641 ppmv constant** | **locked at 2014** |

> Section 5.4 cases are **cloned** from the 0521 transients at the 2015-01-01 restart.
> CO₂ = 397.7641 ppmv (from `fco2_datm_rcp4.5_1765-2500_c130312.nc`, year 2014).
> Ndep: `stream_year_first_ndep = 2014`, `stream_year_last_ndep = 2014`.

---

## Sites

| Code | Site | Biome | Soil Order | CNP file |
|------|------|-------|------------|----------|
| `BNF-Man` | Manaus, Brazil | Tropical | Oxisols (order 4) | `CNP_parameters_manaus_oxisol_v2.nc` |
| `BNF-Ha1` | Harvard Forest, MA | Temperate | Inceptisols (order 5) | `CNP_parameters.nc` |
| `BNF-Bon` | Bonanza Creek, AK | Boreal | Inceptisols (order 5) | `CNP_parameters.nc` |

---

## Experiments

| # | Label | N-fixation scheme | FUN/FUNP | SourceMods |
|---|-------|-------------------|----------|------------|
| 1 | `nofun_baseline` | Houlton CLM default (FUN off) | OFF | `control_fixed_funp_nfix` |
| 3 | `fun_transient_only` | Houlton (ELM-FUN default) | ON | `fun_fpg1_nfix` |
| 4 | `noacc_transient` | Bytnerowicz no-acclimation | ON | `noACC_fixed_funp_nfix` (Man) / `noACC_temperate_funp_nfix` (Ha1, Bon) |
| 5 | `acc_transient` | Bytnerowicz with acclimation | ON | `ACC_fixed_funp_nfix` (Man) / `ACC_temperate_funp_nfix` (Ha1, Bon) |

> Exp 2 (global FPG=1) is not in this submission set.

---

## Spinup Chain

```
AD Spinup  (I1850CNRDCTCBC, 200 yr, FUN OFF)
  └─ iniadjust
      └─ FN Spinup  (I1850CNPRDCTCBC, 600 yr, FUN OFF)  →  yr-751 restart
          │
          ├─ [Exp 1 only]  Historical 5.3/5.5  (I20TRCNPRDCTCBC, 1850–2100)
          │                    └─ Fixed 5.4 clone  (2015–2100, CO₂+Ndep @2014)
          │
          └─ [Exps 3/4/5]  FUN Spinup  (I1850CNPRDCTCBC, ~200 yr, FUN ON)
                               └─ Historical 5.3/5.5  (I20TRCNPRDCTCBC, 1850–2100)
                                    └─ Fixed 5.4 clone  (2015–2100, CO₂+Ndep @2014)
```

---

## Parameter Files (0521 canonical runs)

| Site + Experiment | Paramfile | Location |
|-------------------|-----------|----------|
| Manaus, all exps | `clm_params_fun3_sfix01_manaus_tuned.nc` | `PARAMDIR=/home/braghiere/BNF_tom/` |
| Ha1, all exps | `clm_params_fun3_sfix01.nc` | same |
| Bon, nofun_baseline | `clm_params_fun3_sfix01.nc` | same |
| Bon, Exps 3/4/5 | `clm_params_fun3_sfix01_bon_tuned.nc` | same |
| All sites, Bon only surfdata | `surfdata_bon_gelisol.nc` | same |

---

## Scientific Corrections Applied

See [`docs/corrections.md`](docs/corrections.md) for full details.

| # | Bug | Fix | Affects |
|---|-----|-----|---------|
| 1 | `fpg_p` double P-limitation when `use_funp=.true.` | `else fpg_p = 1.0_r8` branch added to AllocationMod | All FUN runs |
| 2 | `freelivfix_slope` too high → free-living NFIX ~718 mgN/m²/yr (×10 too large) | `6.0e-4` → `0.5e-4` in NitrogenDynamicsMod | All FUN runs |
| 3 | `s_fix` too low → near-zero symbiotic NFIX cost | Increased: warm PFTs → `-6.0`, cold PFTs (1,2,3,8,11,12) → `-1.0` in param file | All FUN runs |
| 4 | Sec. 5.4 Ndep was transient (defaulting 1850–2100) | `stream_year_first_ndep = 2014`, `stream_year_last_ndep = 2014` + `CLM_CO2_TYPE=constant` | 0529_fixed cases |

---

## Repository Structure

```
ELM-FUN-BNFMIP/
├── README.md
├── PROTOCOL.md                          # BNFMIP sections 5.3/5.4/5.5 summary
├── .gitignore
├── docs/
│   ├── run_matrix.md                    # Full run table
│   ├── corrections.md                   # Scientific corrections
│   └── site_info.md                     # Site configs
├── scripts/
│   ├── README.md                        # Workflow guide (START HERE)
│   ├── resubmit_BNFMIP_v2.sh           # THE canonical script: Phases 1–4
│   ├── resubmit_phase4_fixed.sh         # Phase 4 standalone (fixed 0529 cases)
│   ├── resubmit_missing6.sh             # Emergency re-queue for 6 failed cases
│   ├── per_site/                        # Initial case creation scripts
│   │   ├── run_manaus_{nofun_baseline,fun_transient_only,noacc_transient,acc_transient}.sh
│   │   ├── run_ha1_{fun_transient_only,noacc_transient,acc_transient}.sh
│   │   └── run_bon_{fun_transient_only,noacc_transient,acc_transient}.sh
│   └── utils/
│       ├── verify_BNFMIP_submit_env.sh  # Pre-flight checks
│       ├── check_bnf_sanity.py          # Sanity-check output NFIX/FFIX
│       ├── adjust_restart.py            # Restart file utilities
│       ├── compare_cases.py             # Diff namelist/env between two cases
│       └── SESSION_NOTES_20260527.md    # Engineering log: bugs + job IDs
├── source_mods/
│   ├── README.md
│   ├── control_fixed_funp_nfix/         # Exp 1: nofun_baseline
│   ├── fun_fpg1_nfix/                   # Exp 3: fun_transient_only
│   ├── noACC_fixed_funp_nfix/           # Exp 4: Manaus
│   ├── noACC_temperate_funp_nfix/       # Exp 4: Ha1 + Bon
│   ├── ACC_fixed_funp_nfix/             # Exp 5: Manaus
│   ├── ACC_temperate_funp_nfix/         # Exp 5: Ha1 + Bon
│   └── _shared_elm_fun_col_es/          # clm_driver + clm_initializeMod
├── namelists/
│   ├── user_nl_clm.section54_fixed.template   # Section 5.4 (CO₂=397.7641, Ndep@2014)
│   └── ...other templates
└── action_log/                          # Scientific decision log (01–07)
```

---

## Quick Start

### Run the canonical BNFMIP submission

```bash
# Dry-run first (no changes, just preview)
bash /home/braghiere/ELM-FUN-BNFMIP/scripts/resubmit_BNFMIP_v2.sh --dry-run

# Full run (submits all 33 jobs: 9 funsp + 9 transient + 3 nofun + 12 fixed)
bash /home/braghiere/ELM-FUN-BNFMIP/scripts/resubmit_BNFMIP_v2.sh
```

### Monitor

```bash
squeue -u braghiere --format="%.10i %.8P %.40j %.2t %.10M %R"
```

### Sanity-check output

```bash
CASE=fun_transient_only_manaus_20260521_funsp_BNF-Man_I1850CNPRDCTCBC
F=$(ls /lustre/or-scratch/cades-ccsi/scratch/braghiere/${CASE}/run/*.clm2.h0.*.nc | sort | tail -1)
python3 /home/braghiere/ELM-FUN-BNFMIP/scripts/utils/check_bnf_sanity.py "${F}"
```

**Expected values at Manaus (annual mean):**

| Variable | Expected | Bad (old params) |
|----------|----------|-----------------|
| `COST_NFIX` | ~7.2 gC/gN | ~0.12 gC/gN |
| `FFIX_TO_SMINN` | ~2.3×10⁻⁹ gN/m²/s (~72 mgN/m²/yr) | ~2.3×10⁻⁸ (~718 mgN/m²/yr) |

---

## Key Paths

```
SRCROOT:   /home/braghiere/BNF_tom/E3SM_global_silent
CASEROOT:  /home/braghiere/BNF_tom/OLMT_BNF/cime_case_dirs/
RUNROOT:   /lustre/or-scratch/cades-ccsi/scratch/braghiere
PARAMDIR:  /home/braghiere/BNF_tom/
INPUTDATA: /lustre/or-scratch/cades-ccsi/proj-shared/project_acme/e3sm_inputdata
NDEP_FILE: ${INPUTDATA}/lnd/clm2/ndepdata/fndep_clm_rcp8.5_simyr1849-2106_1.9x2.5_c100428.nc
```

---

## References

- Bytnerowicz et al. (in prep) — BNFMIP protocol and temperature-response parameterisation
- Houlton et al. (2008) — CLM default symbiotic N fixation
- Fisher et al. (2010) — FUN framework
- Shi et al. (2016) — FUNP extension
