# Item 1: Double P-Limitation Bug in fpg_p (AllocationMod.F90)

## Investigation Date
Current session

## Findings
- **Bug confirmed**: In base E3SM `AllocationMod.F90`, `fpg_p` is always computed as:
  ```fortran
  fpg_p(c) = sminp_to_plant(c) / col_plant_pdemand(c)
  ```
  regardless of `use_funp`, even when FUN-P is active.

- **Impact mechanism** (via `nu_com = 'RD'` — the default for 0521 runs):
  1. `fpg_p < 1` when soil P supply < plant P demand
  2. In RD mode: `plant_p_uptake_flux(c) += plant_pdemand(p) * fpg_p(c) * wtcol(p)`
     → *lowers* the P demand signal sent to soil competition
  3. Soil competition sets `sminp_to_plant_vr` lower (plants appear to demand less)
  4. CNFUNMod uses `sminp_pox_layer = sminp_to_plant_vr × dz × dt` as its available P pool
     → FUN gets *less* P to work with
  5. FUN additionally constrains P acquisition via C costs
  → **P limitation applied twice**: via competition (fpg_p path) AND via FUN C costs

- **The fix** (in `source_codes/*_fixed_funp_nfix/AllocationMod.F90`):
  ```fortran
  if (.not. use_funp) then
      fpg_p(c) = sminp_to_plant(c) / col_plant_pdemand(c)
  else
      fpg_p(c) = 1.0_r8   ! FUN handles P limitation via C costs
  end if
  ```
  Setting `fpg_p = 1.0` when `use_funp=.true.` signals full P demand to the competition,
  allowing FUN to be the sole P limitation mechanism.

- **Affected runs**: All 0521 transient runs (base E3SM, no SourceMods) are affected.
  - `nu_com = 'RD'` is default (not overridden in user_nl_clm)
  - `use_fun = .true.`, `use_funp = .true.` confirmed in user_nl_clm
  - Result: GPP/NPP are suppressed below what FUN alone would predict

## Status
- Fix is already implemented in `source_codes/*_fixed_funp_nfix/` directories
- 0521 transient runs still use base E3SM (no fix applied at runtime)
- **Action needed**: Rebuild experiments with fixed AllocationMod to remove double P-limitation

## Files Modified
None in this session (fix was pre-existing in source_codes)

## Impact Assessment
- 0521 transient runs: artificially suppressed GPP/NPP due to double P-limitation
- Fixed runs (0529_fixed etc.): use single FUN-based P limitation → higher productivity
- Comparison between date-batches must account for this structural difference
