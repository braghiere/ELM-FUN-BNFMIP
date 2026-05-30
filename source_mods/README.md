# SourceMods README

Each subdirectory contains the ELM Fortran source files that override the base
E3SM checkout (`E3SM_global_silent`). During case setup, these files are copied
to `<CASEROOT>/SourceMods/src.clm/` before `case.build`.

---

## SourceMods Sets

### `control_fixed_funp_nfix/` — Exp 1: nofun_baseline

FUN and FUNP disabled. Contains the `fpg_p` guard fix so that when `use_funp`
is accidentally enabled the model does not double-limit P. Used for AD spinup,
FN spinup, and all transient/future phases of Exp 1.

Key changes vs. base ELM:
- `AllocationMod.F90`: `fpg_p = 1.0` guard when `use_funp=.true.` (safety only)
- Shared col_es wiring compatible with FUN data structures

### `fun_fpg1_nfix/` — Exp 3: fun_transient_only (Houlton default)

ELM-FUN with default Houlton N fixation parameterisation (`nu_com = 'RD'`).
`use_fun = .true.`, `use_funp = .true.`.

Key changes vs. base ELM:
- `AllocationMod.F90`: `fpg_p = 1.0` guard (**Correction 1**)
- `NitrogenDynamicsMod.F90`: `freelivfix_slope = 0.5e-4` (**Correction 2**)

### `noACC_fixed_funp_nfix/` — Exp 4: Manaus (tropical, no acclimation)

Bytnerowicz N fixation temperature response, no thermal acclimation.
Biome-specific T parameters for tropical forests.

T parameters:
- `Tmin_fix = 7.04°C`, `Topt_fix = 33.22°C`, `Tmax_fix = 45.35°C`

Key changes vs. base ELM:
- `AllocationMod.F90`: `fpg_p` guard (**Correction 1**)
- `NitrogenDynamicsMod.F90`: Bytnerowicz function + `freelivfix_slope = 0.5e-4` (**Corrections 2+**)

### `noACC_temperate_funp_nfix/` — Exp 4: Ha1 + Bon (temperate/boreal, no acclimation)

Same as `noACC_fixed_funp_nfix` but with temperate/boreal T parameters:
- `Tmin_fix = -2.04°C`, `Topt_fix = 32.10°C`, `Tmax_fix = 43.98°C`

### `ACC_fixed_funp_nfix/` — Exp 5: Manaus (tropical, with acclimation)

Bytnerowicz N fixation with thermal acclimation. Tmin and Topt shift with the
10-day mean soil temperature (`tc_soila10`).

Acclimation function:
```
if tc_soila10 < 18.5:
    Tmin = 2.37,  Topt = 30.34
elif 18.5 <= tc_soila10 < 28.5:
    Tmin = 0.932 * tc - 14.87
    Topt = 0.574 * tc + 19.72
else (tc >= 28.5):
    Tmin = 11.69, Topt = 36.08
```

### `ACC_temperate_funp_nfix/` — Exp 5: Ha1 + Bon (temperate/boreal, with acclimation)

Same acclimation logic as `ACC_fixed_funp_nfix` but with temperate/boreal
base parameters.

### `_shared_elm_fun_col_es/` — Shared ELM col_es wiring

`clm_driver.F90` and `clm_initializeMod.F90` modified to wire the ELM column
energy state (col_es) required by the FUN data structures. These two files are
copied into **every** experiment's SourceMods alongside the experiment-specific
files.

---

## File Inventory

| File | Purpose |
|------|---------|
| `AllocationMod.F90` | Carbon/N/P allocation; contains `fpg_p` fix |
| `CNFUNMod.F90` | FUN core module; N uptake cost functions |
| `ColumnDataType.F90` | Column-level data type definitions |
| `EcosystemBalanceCheckMod.F90` | Mass balance diagnostics |
| `initVerticalMod.F90` | Vertical soil layer initialisation |
| `NitrogenDynamicsMod.F90` | N fixation; contains `freelivfix_slope` and Bytnerowicz parameterisations |
| `PhenologyMod.F90` | Phenology; linked to N/P allocation |
| `SharedParamsMod.F90` | Shared parameters across BGC modules |
| `TemperatureType.F90` | Temperature data types (needed for acclimation) |
| `VegetationDataType.F90` | Vegetation data types |
| `clm_driver.F90` | *(shared only)* Main CLM driver; col_es wiring |
| `clm_initializeMod.F90` | *(shared only)* Initialisation; col_es wiring |
