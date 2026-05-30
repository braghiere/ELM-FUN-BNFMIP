# Site-Specific Configuration

---

## Manaus (BNF-Man) — Tropical Rainforest

| Property | Value |
|----------|-------|
| **Lat/Lon** | −2.61°, −60.21° |
| **Biome** | Tropical evergreen broadleaf forest |
| **Soil order** | Oxisols (`SOIL_ORDER = 4`) |
| **CLM1PT forcing** | `/home/braghiere/BNF_tom/inputdata/BNFMIP_forcing_from_OCN/BNF_Man/CLM1PT_data` |
| **CLM param (Exp 1/3)** | `clm_params_fun3_sfix01_manaus_tuned.nc` |
| **CLM param (Exp 4/5)** | `clm_params_fun3_sfix6_manaus_tuned.nc` |
| **P-cycle file** | `CNP_parameters_manaus_oxisol_v2.nc` (`fsoilordercon`) |
| **SourceMods Exp 4** | `noACC_fixed_funp_nfix` |
| **SourceMods Exp 5** | `ACC_fixed_funp_nfix` |
| **Bytnerowicz Tmin** | 7.04 °C |
| **Bytnerowicz Topt** | 33.22 °C |
| **Bytnerowicz Tmax** | 45.35 °C |

**Notes:**
- `fsoilordercon` must be injected into `user_nl_clm` for FN and TR cases (not set by OLMT automatically for Manaus)
- Oxisol-specific weathering rate: `r_weather[4] = 0.0001`, `r_mort[4] = 0.01`

---

## Harvard Forest (BNF-Ha1) — Temperate Deciduous

| Property | Value |
|----------|-------|
| **Lat/Lon** | 42.54°, −72.17° |
| **Biome** | Temperate deciduous forest |
| **Soil order** | Inceptisols (`SOIL_ORDER = 5`, Typic Dystrudepts) |
| **CLM1PT forcing** | `/home/braghiere/BNF_tom/inputdata/BNFMIP_forcing_from_OCN/BNF_Har/CLM1PT_data` |
| **CLM param (Exp 1/3)** | `clm_params_fun3_sfix01.nc` |
| **CLM param (Exp 4/5)** | `clm_params_fun3_sfix6.nc` |
| **P-cycle file** | `CNP_parameters.nc` (US-Ha1, `--mod_parm_file_P` in OLMT) |
| **SourceMods Exp 4** | `noACC_temperate_funp_nfix` |
| **SourceMods Exp 5** | `ACC_temperate_funp_nfix` |
| **Bytnerowicz Tmin** | −2.04 °C |
| **Bytnerowicz Topt** | 32.10 °C |
| **Bytnerowicz Tmax** | 43.98 °C |

**Notes:**
- SOIL_ORDER corrected from global default (Alfisols = 3) to Inceptisols = 5 (Typic Dystrudepts for this site)
- `--mod_parm_file_P` passed to `site_fullrun.py` to inject site-specific CNP parameters

---

## Bonanza Creek (BNF-Bon) — Boreal

| Property | Value |
|----------|-------|
| **Lat/Lon** | 64.70°, −148.32° |
| **Biome** | Boreal forest |
| **Soil order** | Inceptisols (`SOIL_ORDER = 5`, Typic Cryepts) |
| **CLM1PT forcing** | `/home/braghiere/BNF_tom/inputdata/BNFMIP_forcing_from_OCN/BNF_Bon/CLM1PT_data` |
| **CLM param (Exp 1/3)** | `clm_params_fun3_sfix01.nc` |
| **CLM param (Exp 4/5)** | `clm_params_fun3_sfix6.nc` |
| **P-cycle file** | `CNP_parameters.nc` (US-Bon, `--mod_parm_file_P` in OLMT) |
| **SourceMods Exp 4** | `noACC_temperate_funp_nfix` |
| **SourceMods Exp 5** | `ACC_temperate_funp_nfix` |
| **Bytnerowicz Tmin** | −2.04 °C |
| **Bytnerowicz Topt** | 32.10 °C |
| **Bytnerowicz Tmax** | 43.98 °C |

**Notes:**
- SOIL_ORDER = 5 (Inceptisols, Typic Cryepts) appropriate for boreal mineral soils
- Uses same temperate SourceMods as Ha1 (same Bytnerowicz T parameters)
- Cold PFTs (1, 2, 3, 8, 11, 12) have `s_fix = -1.0` in cold-PFT parameter file

---

## Shared E3SM Paths

```
SRCROOT:      /home/braghiere/BNF_tom/E3SM_global_silent
CASEROOT:     /home/braghiere/BNF_tom/OLMT_BNF/cime_case_dirs/
RUNROOT:      /lustre/or-scratch/cades-ccsi/scratch/braghiere
PARAM_DIR:    /home/braghiere/BNF_tom/
INPUTDATA:    /lustre/or-scratch/cades-ccsi/proj-shared/project_acme/e3sm_inputdata
NDEP_FILE:    ${INPUTDATA}/lnd/clm2/ndepdata/fndep_clm_rcp8.5_simyr1849-2106_1.9x2.5_c100428.nc
ACCOUNT:      ccsi
PARTITION:    batch (run), burst (build)
MPI:          openmpi, 1 task
WALLTIME:     24 hr (spinup), 24 hr (transient)
```

---

## PFT Mapping at Each Site

| Site | Dominant PFT(s) | Notes |
|------|----------------|-------|
| Manaus | 2 (BET tropical) | Broadleaf Evergreen Tropical tree |
| Ha1 | 7 (BDT temperate), 8 (BDT boreal) | Broadleaf Deciduous Temperate/Boreal |
| Bon | 1 (NET boreal), 11/12 (Arctic shrubs) | Needleleaf Evergreen + shrubs |

Cold PFTs (s_fix = -1.0 in cold-PFT param file): 1, 2, 3, 8, 11, 12
