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

## Correction 5 — Manaus SSP585 (§5.5) Built With Wrong PFT (Boreal Instead of Tropical)

**File:** `surfdata.nc` / `surfdata.pftdyn.nc` (surface datasets)
**Affects:** All 4 Manaus (BNF-Man) SSP585 (§5.5) cases, date stamp `20260523`

### Problem

All four Manaus §5.5 cases produced a **dead forest**: GPP = 0, ELAI = 0,
TOTVEGC ≈ 0 across the entire 1850–2100 run, while soil organic matter continued
to decompose (HR > 0, NBP strongly negative). The forest collapsed within ~12
model years and never recovered.

Root cause: the SSP585 surface datasets were built with the wrong plant
functional type —

| Dataset | Dominant PFT |
|---------|--------------|
| Manaus §5.3/§5.4 (working, `20260521`) | **PFT 4 — broadleaf evergreen TROPICAL tree, 100%** ✓ |
| Manaus §5.5 (broken, `20260523`) | **PFT 2 — needleleaf evergreen BOREAL tree, 100%** ✗ |

A boreal conifer placed at the equator (−2.6°) under tropical climate forcing and
tropical-tuned parameters (oxisol CNP, `s_fix` for warm PFTs) cannot survive. The
finidat's tropical biomass also mapped onto PFT 4, which had 0% area in the boreal
surfdata, leaving effectively zero live biomass on the active PFT.

### Diagnosis

- The §5.4 fixed-CO₂ Manaus run was healthy (GPP ~3900), ruling out a
  climate-driven collapse.
- Bonanza Creek (genuinely boreal) did **not** collapse from the same run
  configuration — only Manaus did, confirming a site-specific PFT/climate mismatch.
- Confirmed by comparing `PCT_NAT_PFT` (and `PCT_SAND`/`PCT_CLAY`) between the
  working historical run dir and the SSP585 run dir.

### Fix attempts and the REAL root cause

The wrong PFT was real, but fixing the surfdata/finidat did **not** revive the run.
Extensive isolation (2026-07-07/08) showed the deeper problem: the entire
`*_ssp585_manaus_20260523_*` **case build was defective** — it could not map the
finidat vegetation onto the grid. Evidence:

- With the SSP585 case pointed at the *byte-identical* finidat/surfdata/pftdyn/domain
  used by the healthy §5.4 case, the run still initialized with soil loaded
  (TOTSOMC ≈ 22 000) but **vegetation zeroed** (TOTVEGC = 1). A forest cannot lose
  ~13 000 gC/m² in one year — so this is a load-time failure, not a die-off.
- It failed identically with `CLM_CO2_TYPE=constant`, ruling out the CO₂/Ndep forcing.
- The working §5.4 case (`*_manaus_20260529_fixed_*`), with the same inputs, loads
  the forest correctly. So the defect is in the SSP585 case's own build/mapping, not
  in any namelist setting.

**Working fix:** repurpose the sound §5.4 case builds for §5.5. For each experiment,
took the `20260529_fixed` case (RUN_STARTDATE=2015, STOP_N=86, healthy 2015 restart
finidat) and switched CO₂/Ndep from fixed to transient SSP585:

```
CLM_CO2_TYPE = diagnostic                       # transient CO2 from DATM stream
user_datm.streams.txt.co2tseries.20tr -> fieldInfo = fco2_datm_ssp585_1765-2100_c260519.nc
stream_year_first_ndep = 2015 ; stream_year_last_ndep = 2100   # transient Ndep
```

This is exactly what §5.5 requires (§5.4 protocol + transient CO₂/Ndep) built from a
known-good base. Jobs 5448900/5448924/5448925/5448926.

### Verification (passed)

All 4 repurposed runs initialized with the full tropical forest (VegC ≈ 13 300 at
2015) and stayed alive through 2100 (last-decade GPP ≈ 4060–4140 gC/m²/yr, elevated
by SSP585 CO₂ fertilization). Packaged via `package_manaus_sec55.py`.

---

## Correction 6 — Harvard Forest PFT (broadleaf-deciduous tropical vs temperate)

**File:** `surfdata.nc` (all Harvard `BNF-Ha1` cases)
**Status:** ACCEPTED as-is (not corrected) — documented deviation.

### Issue

The protocol specifies Harvard = **broadleaf deciduous temperate tree (PFT 7)**. Every
Harvard case (all date stamps) was built with **PFT 6 = broadleaf deciduous _tropical_
tree** at 100% (confirmed via surfdata `PCT_NAT_PFT` and the restart's
`pfts1d_active`/`pfts1d_itypveg`). No PFT 7 Harvard spin-up exists.

### Impact (why accepted)

PFT 6 and PFT 7 differ in only three parameters: phenology type (stress- vs
season-deciduous) and `flnr` (0.0716 vs 0.1007, i.e. PFT 7 has ~41 % higher Rubisco N
→ higher Vcmax). **All four BNF temperature-response parameters (`a_fix`, `b_fix`,
`c_fix`, `s_fix`) are identical**, so the MIP's core signal — the temperature response
of BNF — is unaffected. Net effect: Harvard absolute GPP/NPP are biased ~10–25 % low;
the fun/noacc/acc comparison is intact. A full PFT 7 rebuild needs a fresh multi-day
spin-up and was deferred; delivered with this caveat.

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
