# Item 2: Revert freelivfix_slope from 0.5e-4 to 6.0e-4

## Background
The Cleveland et al. (1999) global regression for free-living BNF:
  `FFIX = slope × AnnET + intercept`
  - Original slope = 6.0e-4 kgN kgH₂O⁻¹ (Cleveland+99)
  - Was changed to 0.5e-4 (ca. 12× smaller) to try to bump BNF diagnostics
  - User decision: the reduction was incorrect; revert to literature value

## Action Taken
Reverted `freelivfix_slope = 0.5e-4_r8` → `freelivfix_slope = 6.0e-4_r8` in:

### source_codes directories (5 files):
1. `source_codes/noACC_fixed_funp_nfix/NitrogenDynamicsMod.F90` (line 194)
2. `source_codes/ACC_fixed_funp_nfix/NitrogenDynamicsMod.F90` (line 194)
3. `source_codes/fun_fpg1_nfix/NitrogenDynamicsMod.F90` (line 194)
4. `source_codes/noACC_temperate_funp_nfix/NitrogenDynamicsMod.F90` (line 194)
5. `source_codes/ACC_temperate_funp_nfix/NitrogenDynamicsMod.F90` (line 194)

### 0521 spinup SourceMods (9 case directories):
- `acc_transient_{bon,ha1,manaus}_20260521_*_ad_spinup/SourceMods/src.clm/NitrogenDynamicsMod.F90`
- `noacc_transient_{bon,ha1,manaus}_20260521_*_ad_spinup/SourceMods/src.clm/NitrogenDynamicsMod.F90`
- `fun_transient_only_{bon,ha1,manaus}_20260521_*_ad_spinup/SourceMods/src.clm/NitrogenDynamicsMod.F90`

Note: 0521 transient runs have EMPTY SourceMods/src.clm (only README), so they used the
base E3SM slope of 6.0e-4 already — no change needed there.

## Verification
All 5 source_codes files and all 9 spinup SourceMods confirmed to show 6.0e-4 after change.

## Next Steps
- Spinups with corrected slope must be re-run before transient runs are submitted
- FFIX values should be reviewed against literature after re-run
  (expected: ~50-200 mgN m⁻² yr⁻¹ for boreal, ~500-1500 mgN m⁻² yr⁻¹ for tropical)
