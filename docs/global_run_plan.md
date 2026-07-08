# ELM-FUN BNFMIP — Global Run Plan (DRAFT — no jobs submitted)

Extend the 3-site BNFMIP protocol to the whole globe: a global map of the BNF
temperature response and how the Houlton vs Bytnerowicz (no-acclim / acclim)
functions reshape global BNF, NPP, and land C storage.

Status: **planning only.** Nothing submitted until approved.

---

## 1. Driver & recipe (already on server)

OLMT global driver: `/home/braghiere/BNF_tom/OLMT_BNF/global_fullrun.py`
Documented CADES recipe (from its header):

```
python global_fullrun.py --machine cades --res f19_f19 --cpl_bypass --np 384 \
  --tstep 1 --caseidprefix bnfmip_global --model_root /home/braghiere/BNF_tom/E3SM_global_silent \
  --pio_version 1 --mpilib openmpi --walltime 24 --nyears_final_spinup 600
```

`--cpl_bypass` runs the land model with offline meteorology (no active atm) — the
key to affordable global spinup. Phase flags: `--noad / --nofn / --notrans` gate
the AD-spinup / FUN-spinup / transient stages. Region subsetting via
`--lat_bounds / --lon_bounds / --mask`.

## 2. Resolution — recommend f19_f19 first

- **f19_f19 (1.9°×2.5°, ~2000 land cells)** — the OLMT example resolution, best-tested,
  cheapest global spinup. **Recommended for the first global study.**
- **ne30np4 (~1°)** — higher-res alternative; surfdata + SSP5-8.5 landuse are staged
  (`landuse.timeseries_ne30np4_*`). ~4× the cells/cost. Do as a follow-up if f19 looks good.
- Global surfdata carries the **correct PFT per gridcell** — the Harvard PFT issue is a
  single-point artifact and does not arise globally.

## 3. Forcing

- Use OLMT's standard global `--cpl_bypass` meteorology already on the server
  (GSWP3/CRUJRA-type reanalysis). CO₂/Ndep transient + SSP5-8.5 future via the same
  streams used for the site runs (`fco2_datm_ssp585_1765-2100`, RCP8.5 Ndep, SSP5-8.5 landuse).
- **Protocol deviation to note to Tom:** the protocol specifies ISIMIP3b GFDL-ESM4.
  OLMT's global forcing is reanalysis-based, not GFDL-ESM4. Acceptable for a global
  *sensitivity* study; sourcing/regridding GFDL-ESM4 globally is a separate data job if
  strict protocol fidelity is required.

## 4. Experiments (same source_mods as the site runs)

| # | Case | BNF scheme | source_mods |
|---|------|-----------|-------------|
| 1 | nofun_baseline | FUN off | control_fixed_funp_nfix |
| 2 | fun (Houlton) | §3.1 Houlton | fun_fpg1_nfix |
| 3 | noacc | §3.2 Bytnerowicz no-acclim | noACC_*_funp_nfix |
| 4 | acc | §3.3 Bytnerowicz acclim | ACC_*_funp_nfix |

All fixes from the site work carry over (fpg_p, freelivfix_slope, s_fix, use_lch4=.false.).

## 5. Simulation phases (per experiment)

1. **AD spin-up** (accelerated decomposition), CO₂/Ndep @1850, ~200 yr
2. **FN + FUN spin-up** to equilibrium — protocol §5.2: <1 gC/m²/yr (TOTECOC) & <0.5 gN/m²/yr (TOTECON) over 50 yr; `--nyears_final_spinup 600`
3. **§5.3** transient 1850–2014
4. **§5.4** 2015–2100, CO₂/Ndep fixed @2014, SSP5-8.5 warming
5. **§5.5** 2015–2100, transient SSP5-8.5 CO₂/Ndep

## 6. Rough resource estimate (f19, cpl_bypass, 384 cores)

- Spin-up dominates: ~800 model-yr (AD+FUN) × 4 experiments. With cpl_bypass, f19 runs
  fast (~hundreds of model-yr/day). Ballpark **a few days wall-clock per experiment**,
  parallelizable across the 4 → **~3–5 days** total with queue contention.
- Storage: global h0 with full Table-2 variables can be large. Plan **annual output**
  (`--hist_nhtfrq` monthly→annual post-process) and restrict to protocol variables.

## 7. Packaging (needs new code)

The site packager (`package_bnfmip_outputs.py`) collapses a single cell. Global needs a
new path: keep (lat, lon, year) dims, output gridded NetCDF per experiment×section, plus
biome-aggregated summaries (tropical/temperate/boreal bands) for the headline BNF-vs-T maps.

## 8. De-risking sequence (recommended)

1. **Regional test first**: `--lat_bounds -15,15` (tropics band) to validate the global
   setup end-to-end cheaply before committing to full global spinup.
2. Confirm spinup equilibrium on the test region → launch full global AD spin-up.
3. Run dirs on **or-scratch24** (or-scratch has been unstable); stage forcing there.

## 9. Decisions (locked 2026-07-07)

- **Resolution: f19_f19 (1.9°×2.5°)** — confirmed.
- **Forcing: GSWP3** (`--cpl_bypass` with GSWP3 offline meteorology). Note-to-Tom:
  deviates from protocol's ISIMIP3b GFDL-ESM4; acceptable for the global sensitivity study.
- Still open: include nofun_baseline globally (4 exp) or just the 3 BNF approaches — default to all 4 unless told otherwise.

## 10. Launch command (when approved, after site set closed)

```
python global_fullrun.py --machine cades --res f19_f19 --cpl_bypass --np 384 \
  --caseidprefix bnfmip_global_f19 --model_root /home/braghiere/BNF_tom/E3SM_global_silent \
  --pio_version 1 --mpilib openmpi --walltime 24 --nyears_final_spinup 600 --nofire \
  --metdir <GSWP3 forcing path> --runroot /lustre/or-scratch24/scratch/braghiere
```
Regional validation first: add `--lat_bounds -15,15` for a tropics-band shakedown.
