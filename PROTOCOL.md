# BNFMIP Protocol Summary — ELM-FUN Participation

> Source: Bytnerowicz et al. (March 2024 draft)  
> This file summarises the sections relevant to ELM-FUN site simulations.

---

## Section 5 — Site Simulations

### 5.1 — Model Configuration

All ELM-FUN simulations use:
- Compset base: `CNPRDCTCBC` (C, N, P cycling + RDCTBC land-use)
- `use_nitrif_denitrif = .true.`
- `use_nofire = .true.`
- AD spinup: 200 yr (`I1850CNRDCTCBC`)
- Regular FN spinup: 600 yr (`I1850CNPRDCTCBC`, FUN OFF for Exp 1; FUN ON for Exps 3–5)
- Transient and future runs start from yr-751 FN spinup restart

### 5.2 — Sites

| Site | Code | Lat | Lon | Biome |
|------|------|-----|-----|-------|
| Manaus, Brazil | BNF-Man | ~−2.6° | ~−60.2° | Tropical rainforest |
| Harvard Forest, MA | BNF-Ha1 | 42.54° | −72.17° | Temperate deciduous |
| Bonanza Creek, AK | BNF-Bon | 64.70° | −148.32° | Boreal forest |

### 5.3 — Historical Transient (1850–2014)

- Compset: `I20TRCNPRDCTCBC`
- CO₂: transient (historical)
- Ndep: transient (RCP8.5 1849–2014 from `fndep_clm_rcp8.5_simyr1849-2106_1.9x2.5_c100428.nc`)
- Climate: CLM1PT site forcing
- Start: yr-751 FN spinup restart, branched at `RUN_REFDATE=0751-01-01`
- End: 2014-12-31

### 5.4 — Fixed CO₂ and Ndep (2015–2100)

- Compset: `IRCP85CNPRDCTCBC`
- CO₂: **fixed** at 2015 level → `DATM_CO2_TSERIES=none`, `CCSM_CO2_PPMV=<2015 value>`
- Ndep: **fixed** at 2015 level → `stream_year_first_ndep = 2015`, `stream_year_last_ndep = 2015` in `user_nl_clm`
- Climate: SSP5-8.5 forcing (transient — only CO₂ and Ndep are fixed)
- Start: `finidat` = 2015-01-01 restart from the corresponding Exp's I20TR run
- Purpose: isolate the effect of climate change (CO₂ and Ndep held constant)

**ELM-FUN namelist key lines:**
```fortran
! user_nl_clm — section 5.4
stream_year_first_ndep = 2015
stream_year_last_ndep  = 2015
```
```xml
<!-- env_run.xml — section 5.4 -->
DATM_CO2_TSERIES = none
CCSM_CO2_PPMV    = 398.87   ! 2015 global mean CO2 (ppm)
```

### 5.5 — Transient CO₂ and Ndep (2015–2100)

- Compset: `I20TRCNPRDCTCBC` (continuation of 5.3 run)
- CO₂: transient SSP5-8.5
- Ndep: transient RCP8.5
- Climate: SSP5-8.5 forcing
- Start: continues from 5.3 end (2015-01-01 restart)
- Purpose: full future scenario with all forcings varying

---

## Experiments

### Exp 1 — nofun_baseline

- N fixation: CLM/ELM default Houlton (offline regression, FUN OFF)
- `use_fun = .false.`, `use_funp = .false.`
- SourceMods: `control_fixed_funp_nfix`
- Full spinup chain: AD → iniadjust → FN (600 yr) → TR

### Exp 3 — fun_transient_only

- N fixation: Houlton (ELM-FUN, `nu_com = 'RD'` default)
- `use_fun = .true.`, `use_funp = .true.`
- SourceMods: `fun_fpg1_nfix`
- Spinup: reuses nofun_baseline FN yr-751 restart
- **Note**: FUN spinup (FUN ON) is added before transient for proper pool equilibration

### Exp 4 — noacc_transient

- N fixation: Bytnerowicz temperature response, **no acclimation**
- Fixed T params: Tmin, Topt, Tmax from biome lookup (site-specific)
- SourceMods: `noACC_fixed_funp_nfix` (Manaus) / `noACC_temperate_funp_nfix` (Ha1, Bon)
- Biome temperature parameters:

| Site | Tmin (°C) | Topt (°C) | Tmax (°C) |
|------|-----------|-----------|-----------|
| Manaus | 7.04 | 33.22 | 45.35 |
| Ha1 | −2.04 | 32.10 | 43.98 |
| Bon | −2.04 | 32.10 | 43.98 |

### Exp 5 — acc_transient

- N fixation: Bytnerowicz temperature response, **with acclimation**
- T params shift with 10-day mean soil temperature (`tc_soila10`):

| tc_soila10 | Tmin (°C) | Topt (°C) |
|-----------|-----------|-----------|
| < 18.5 | 2.37 | 30.34 |
| 18.5–28.5 | 0.932×tc − 14.87 | 0.574×tc + 19.72 |
| ≥ 28.5 | 11.69 | 36.08 |

- SourceMods: `ACC_fixed_funp_nfix` (Manaus) / `ACC_temperate_funp_nfix` (Ha1, Bon)

---

## Output Variables (Required by Protocol)

| Variable | Description | Units |
|----------|-------------|-------|
| `GPP` | Gross primary production | gC m⁻² yr⁻¹ |
| `NPP` | Net primary production | gC m⁻² yr⁻¹ |
| `NFIX_TO_SMINN` | Total N fixation → soil mineral N | gN m⁻² yr⁻¹ |
| `FFIX_TO_SMINN` | Free-living N fixation | gN m⁻² yr⁻¹ |
| `SMINN` | Soil mineral N | gN m⁻² |
| `COST_NFIX` | Carbon cost of N fixation | gC gN⁻¹ |
| `NUPTAKE` | Total plant N uptake | gN m⁻² yr⁻¹ |
| `ELAI` | Exposed leaf area index | m² m⁻² |
| `QVEGT` | Canopy transpiration | mm yr⁻¹ |
| `LEAFN` | Leaf N content | gN m⁻² |
| `LEAFP` | Leaf P content | gP m⁻² |

---

## Data Submission

Output frequency: **daily** (`hist_nhtfrq = -24`, `hist_mfilt = 365`)

Submission target: BNFMIP data repository (TBD by protocol coordinators)
