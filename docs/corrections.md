# Scientific Corrections Applied to ELM-FUN

This document records all bug fixes and parameter corrections applied before the
final BNFMIP submission. Each entry documents the problem, fix, affected code,
and expected impact.

---

## Correction 1 — `fpg_p` Double P-Limitation

**File:** `AllocationMod.F90`  
**Function:** allocation P-limitation scaling  
**Affects:** All FUN experiments (`use_funp = .true.`)

### Problem

When `use_funp = .true.`, the variable `fpg_p` (fractional plant growth limited
by phosphorus) was computed as `fpg_p = sminp / demand` regardless of whether
FUN phosphorus cycling was active. This caused a double P-limitation: once
through the explicit FUN-P uptake pathway and once through the `fpg_p` scaling,
artificially depressing GPP, NPP, and N fixation in all FUN runs.

### Fix

```fortran
! Before (buggy):
fpg_p = sminp / demand

! After (fixed):
if (.not. use_funp) then
    fpg_p = sminp / demand
else
    fpg_p = 1.0_r8   ! FUN-P handles P limitation explicitly
end if
```

### Affected SourceMods

All `*_fixed_funp_nfix` and `fun_fpg1_nfix` directories contain the fix.

### Affected Runs

| Phase | Affected? |
|-------|-----------|
| AD spinup (`use_funp=.false.`) | NO |
| nofun FN spinup (`use_funp=.false.`) | NO |
| FUN FN spinup (`use_funp=.true.`) | YES → must use fixed exe |
| All FUN transients (Exps 3/4/5) | YES |
| nofun_baseline (Exp 1) | NO (`use_funp=.false.`) |

---

## Correction 2 — `freelivfix_slope` Free-Living N Fixation Rate

**File:** `NitrogenDynamicsMod.F90`  
**Variable:** `freelivfix_slope`  
**Affects:** All FUN experiments

### Problem

`freelivfix_slope = 6.0e-4_r8` produced unrealistically high free-living N
fixation rates. At Manaus, this gave `FFIX_TO_SMINN ≈ 718 mgN m⁻² yr⁻¹`,
roughly 10× the expected observational range (~50–100 mgN m⁻² yr⁻¹ for tropical
forests).

### Fix

```fortran
! Before:
real(r8), parameter :: freelivfix_slope = 6.0e-4_r8

! After:
real(r8), parameter :: freelivfix_slope = 0.5e-4_r8
```

**Expected post-fix value at Manaus:** `FFIX_TO_SMINN ≈ 72 mgN m⁻² yr⁻¹`

### Affected SourceMods

`fun_fpg1_nfix`, `noACC_fixed_funp_nfix`, `noACC_temperate_funp_nfix`,
`ACC_fixed_funp_nfix`, `ACC_temperate_funp_nfix`

---

## Correction 3 — `s_fix` Symbiotic N Fixation Cost Parameter

**File:** `clm_params_*.nc` (parameter netCDF)  
**Variable:** `s_fix` (slope of BNF temperature response)  
**Affects:** All FUN experiments

### Problem

`s_fix = -0.1` produced a near-flat, very cheap N fixation cost curve, giving
`COST_NFIX ≈ 0.12 gC gN⁻¹` at Manaus (~31°C). Observed values are typically
6–12 gC gN⁻¹. This caused runaway N fixation and unrealistically high GPP/NPP.

### Fix

Updated parameter file with biome-aware `s_fix`:
- Warm/productive PFTs (tropical/temperate trees): `s_fix = -6.0`
- Cold-region PFTs (1, 2, 3, 8, 11, 12): `s_fix = -1.0`

Parameter file used: `clm_params_fun3_sfix1_cold_pft.nc` (for cold-PFT experiments)
and `clm_params_fun3_sfix6_manaus_tuned.nc` / `clm_params_fun3_sfix6.nc`

**Expected post-fix value at Manaus (~31°C):** `COST_NFIX ≈ 7.2 gC gN⁻¹`

---

## Correction 4 — Section 5.4 Ndep Not Locked to 2015

**File:** `user_nl_clm` (IRCP85 cases)  
**Namelist group:** `ndepdyn_nml`  
**Affects:** Section 5.4 (fixed CO₂+Ndep) runs only

### Problem

The `IRCP85CNPRDCTCBC` compset sets CO₂ to fixed (via `DATM_CO2_TSERIES=none`),
but the CLM `ndepdyn_nml` stream defaults to the full transient range
(`stream_year_first_ndep = 1850`, `stream_year_last_ndep = 2100`). This meant
Ndep was NOT fixed despite the protocol requirement.

### Fix

Add to `user_nl_clm` for all IRCP85 cases:

```fortran
stream_year_first_ndep = 2015
stream_year_last_ndep  = 2015
```

Combined with `DATM_CO2_TSERIES = none` and `CCSM_CO2_PPMV = 398.87`, this
properly implements Section 5.4: CO₂ at 2015 level, Ndep at 2015 level,
climate following SSP5-8.5.

### Affected Runs

All 12 IRCP85 (Section 5.4) cases: 4 experiments × 3 sites.

---

## Sanity Check Values (Manaus, annual mean)

| Variable | Expected (corrected) | Pathological (uncorrected) |
|----------|---------------------|---------------------------|
| `COST_NFIX` | ~7.2 gC gN⁻¹ | ~0.12 gC gN⁻¹ |
| `FFIX_TO_SMINN` | ~2.3×10⁻⁹ gN m⁻² s⁻¹ (~72 mgN m⁻² yr⁻¹) | ~2.3×10⁻⁸ (~718 mgN m⁻² yr⁻¹) |
| `NFIX_TO_SMINN` | growing over spinup years | near zero throughout |
| `SMINN` | declining from ~5.7 toward ~0.5 gN m⁻² | stuck at ~5.7 gN m⁻² |
| `GPP` (Manaus) | ~2000–2800 gC m⁻² yr⁻¹ | inflated |

Use `scripts/utils/check_bnf_sanity.py` to verify these after each spinup.
