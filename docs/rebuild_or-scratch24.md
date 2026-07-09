# Rebuild on or-scratch24 (2026-07-08/09)

When `/lustre/or-scratch` went permanently offline (out of warranty), the site runs were
rebuilt from scratch on `/lustre/or-scratch24` using data preserved on `/home`. This is
both the recovery record and a reproducibility test: clone the repo, follow this, reproduce.

## Inputs preserved on /home (the rebuild depends on these)
- `BNF_tom/inputdata/BNFMIP_forcing_from_OCN/BNF_{Man,Har,Bon}/` — per-site point surfdata + CLM1PT met (1849–2100)
- `BNF_tom/surfdata_bon_gelisol.nc` — **Bonanza surfdata with full P/soil fields** (see below)
- `BNF_tom/inputdata/surfdata_BNF-Ha1_PFT7.nc` — **Harvard PFT7 surfdata** (built during rebuild)
- `BNF_tom/restart_opt/{man,bon}_optimized_restart_{fun,noacc,acc}_0751-*.nc` — year-751 post-spin-up restarts
- CO2/Ndep streams, params (`clm_params_fun3_sfix01*`), OLMT, the ELM source tree

## The 8-fix recipe (single-point runs via runcase.py, bypassing dead global data)
1. Stage `BNF_{site,soil,pft}data.txt` into `$CCSM_INPUT/lnd/clm2/PTCLM/`.
2. `runcase.py --nopointdata --surffile <point surfdata> --domainfile <1x1 domain>` (skips makepointdata,
   which needs the dead global surfdata_map/share/domains).
3. `export TMPDIR=/lustre/or-scratch24/scratch/braghiere/tmp_build` (container `/tmp` can't hold `.s` files).
4. Aerosol dep linked from `e3sm_inputdata_ha1`.
5–7. Build a **1×1 domain** with `xc==LONGXY`, `yc==LATIXY` exactly matched to the surfdata, and set
   `ATM_NX=ATM_NY=LND_NX=LND_NY=ROF_NX=ROF_NY=1` (+ `case.build --clean-all`) to fix the coupler gsmap check.
8. Remove any stale global `domainfile` line in `user_nl_datm`; point it at the 1×1 domain.

## Two scientific corrections applied in the rebuild
- **Harvard PFT6 → PFT7.** The delivered runs used PFT6 (broadleaf-deciduous *tropical*); the protocol
  wants PFT7 (*temperate*). Fixed by grafting the full P/soil field set onto a PFT7 surfdata
  (`surfdata_BNF-Ha1_PFT7.nc`).
- **§5.5 CO2 rcp4.5 → SSP5-8.5.** The delivered §5.5 used rcp4.5 CO2; the protocol specifies SSP5-8.5.
  The rebuild uses `fco2_datm_ssp585_1765-2100_c260519.nc` (a coordinate-variable graft was needed —
  see `scripts/rebuild_or-scratch24/` — DATM requires `lonc/latc/lonv/latv` on the CO2 stream file).

## Bonanza soil/P data
`surfdata_bon_gelisol.nc` carries `SOIL_ORDER=3` (gelisol/permafrost), boreal PFT2, and the full
FUNP phosphorus pools — the correct boreal soil for Bonanza Creek. It was preserved on `/home`;
the CN-only `BNF_Bon` point surfdata lacks these 11 fields.

## Spin-up chain (per combo)
`AD (I1850CN[P]RDCTCBC, 200yr) → FN (I1850CNPRDCTCBC, 750yr → r.0751) → transient (I20TRCNPRDCTCBC)`.
The boreal Bonanza noACC/ACC runs use the `_temperate_funp_nfix` source variant, which the code
labels "Temperate (and boreal)" and explicitly activates for `ivt==2` (boreal needleleaf evergreen).

## Restart shortcut (fast path to the corrected transients)
The year-751 restarts in `restart_opt/` are the same FN branch point the delivered runs used, so the
transient can branch directly from them, skipping the ~950-yr AD+FN spin-up. Each combo runs **one
continuous 1850–2100 transient** with SSP5-8.5 forcing; §5.3 (1850–2014) and §5.5 (2015–2100) are
sliced from it — making §5.5 **continuous at 2015 by construction** (this fixes the Bonanza §5.5
discontinuity). See `scripts/rebuild_or-scratch24/shortcut_all.sh`.

## Scripts
`scripts/rebuild_or-scratch24/` — the exact rebuild scripts: per-site AD re-runs (`rerun_{ha1,bon}.sh`),
the transient proof (`proof_bonfun_sec53.sh`), the restart-shortcut fan-out (`shortcut_all.sh`),
the AD→FN→transient autochainer (`fn_autochain.sh`), and the from-scratch finisher (`finish_all.sh`).
