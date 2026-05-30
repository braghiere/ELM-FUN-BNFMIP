# Item 3: PFT-Dependent s_fix Parameter for Cold-Region Symbiotic BNF

## Background
- `s_fix` is the scaling parameter in the FUN symbiotic BNF cost function
- Cost equation: `cost = -s_fix / (temperature_factor × ...)`
- Larger |s_fix| → higher cost → less SNFIX
- Problem: Bonanza Creek SNFIX was too high due to `s_fix = -0.1` (small cost)
- All existing parameter files use uniform s_fix = -0.1 for ALL 25 PFTs

## Action Taken
Created new parameter file: `/home/braghiere/BNF_tom/clm_params_fun3_sfix1_cold_pft.nc`
- Copied from `clm_params_fun3_sfix01_bon_tuned.nc`
- Changed s_fix to -1.0 (10× larger cost = 10× less SNFIX tendency) for cold-region PFTs:
  - PFT  1: needleleaf_evergreen_temperate_tree → s_fix = -1.0
  - PFT  2: needleleaf_evergreen_boreal_tree   → s_fix = -1.0
  - PFT  3: needleleaf_deciduous_boreal_tree   → s_fix = -1.0
  - PFT  8: broadleaf_deciduous_boreal_tree    → s_fix = -1.0
  - PFT 11: broadleaf_deciduous_boreal_shrub   → s_fix = -1.0
  - PFT 12: c3_arctic_grass                   → s_fix = -1.0
  - All other PFTs remain at s_fix = -0.1

## Next Steps
- To use this file in Bonanza simulations, update user_nl_clm:
  ```
  paramfile = '/home/braghiere/BNF_tom/clm_params_fun3_sfix1_cold_pft.nc'
  ```
- Run a test Bonanza simulation and compare SNFIX against:
  - Literature: 0.01–0.08 gN m⁻² yr⁻¹ for boreal
  - Target value from Davies-Barnard & Friedlingstein (2020): ~0.03 gN m⁻² yr⁻¹
- If -1.0 is still too high, consider -2.0 or -3.0 for arctic/boreal PFTs
- Harvard Forest and Manaus are NOT affected (they use their own parameter files)

## Rationale
Bonanza Creek is dominated by boreal PFTs (PFT 2, 3, 8, 11). With s_fix = -0.1,
the symbiotic BNF cost was too low, allowing excessive SNFIX in cold conditions
where N-fixing trees (e.g., Alnus) are naturally limited. The 10× cost increase
aligns with the range covered by clm_params_fun3_cn25.nc (s_fix = -1.0).
