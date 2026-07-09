# ELM-FUN BNFMIP — End-to-End Rebuild Plan (CADES `or-scratch24`)

**Purpose.** Reproduce the ELM-FUN BNFMIP simulations from surviving sources on the
writable `/lustre/or-scratch24` filesystem after `/lustre/or-scratch` died permanently.
The rebuild is a reproducibility test that *also* clears the two delivered caveats:

1. **Harvard PFT** — deliver on protocol **PFT 7** (broadleaf-deciduous *temperate*) instead
   of the PFT 6 (tropical) used in the caveated delivery. (`docs/corrections.md` #6)
2. **§5.5 discontinuity** — run §5.5 as a *clean continuation* of §5.4 (repurpose the §5.4
   case with transient SSP5-8.5 CO₂/Ndep) so the 2015 join is smooth. (`docs/corrections.md` #5)

**Scope.** 3 sites × 4 experiments × 3 protocol sections = 36 delivered files per format
(annual + Table-2). Plus the spin-up chains that feed them.

> **Ground truth for this plan.** Every path, command, error string, and value below was
> extracted from the real repro logs and the live case directory as of 2026-07-08:
> - Logs: `/home/braghiere/repro_man_nofun.log`, `repro_build_man.log`,
>   `repro_cleanbuild.log`, `repro_rebuild_submit.log`, `repro_run_nobatch.log`
> - Live repro case: `/home/braghiere/BNF_tom/OLMT_BNF/cime_case_dirs/nofun_baseline_manaus_repro20260708_BNF-Man_I1850CNRDCTCBC_ad_spinup`
> - Run dir: `/lustre/or-scratch24/scratch/braghiere/nofun_baseline_manaus_repro20260708_BNF-Man_I1850CNRDCTCBC_ad_spinup/run`

> **Current frontier (read this first).** The Manaus `nofun_baseline` AD case is fully
> configured with **all 8 fixes below applied** (verified in the live case dir and
> `user_nl_datm`). The last submitted attempts (jobs `5452444`/`5452476`, 22:14–22:16 on
> 2026-07-08) did **not** fail on a model error — they failed to launch with
> `srun: ... step creation ... (Requested nodes are busy)`. So the *recipe* is validated
> through the coupler-init gate; a first fully-successful AD completion is still pending a
> free compute node. Treat "get one clean AD run to completion" as the immediate next action.

---

## Fix legend (the 8 failure modes, baked into Phase 2 as gates)

| # | Symptom (real error string) | Root cause | Fix |
|---|------------------------------|-----------|-----|
| 1 | `ERROR: Site data file not found: .../PTCLM/BNF_sitedata.txt` | OLMT PTCLM metadata not in `$CCSM_INPUT` | Stage `BNF_{site,soil,pft}data.txt` into `$CCSM_INPUT/lnd/clm2/PTCLM/` |
| 2 | `PointCLM: Error creating point data. Aborting` (dead global surfdata_map/share/domain) | `makepointdata.py` needs the dead global tree | Bypass: pass `--nopointdata --surffile <point surfdata> --domainfile <1x1 domain>` to `site_fullrun.py`/`runcase.py` |
| 3 | `can't open /tmp/*.s` during build | container-overlay `/tmp` not writable by the compiler | `export TMPDIR=/lustre/or-scratch24/scratch/braghiere/tmp_build` before `case.build`; also `GMAKE_J=2` |
| 4 | runtime: missing `.../atm/cam/chem/trop_mozart_aero/aero/aerosoldep_*.nc` | aerosol dep not in local inputdata | symlink from `or-scratch24/e3sm_inputdata_ha1/` |
| 5 | DATM abort `data sizes 1 1 17520 55296` | provided `domain.nc` is GLOBAL (288×192) | use a **1×1 point** domain (Phase 1 helper) |
| 6 | CLM abort `surfdata/fatmgrid lon/lat mismatch` | 1×1 domain coords ≠ surfdata coords | build the 1×1 domain with `xc=LONGXY`, `yc=LATIXY` (exact copy, not nearest-cell) |
| 7 | coupler abort `(seq_map_gsmapcheck) different gsmap size` | atm grid still 288×192 vs lnd=1 | `ATM_NX=ATM_NY=LND_NX=LND_NY=1` (+`ROF_NX/NY=1`) → **requires** `case.build --clean-all` |
| 8 | coupler *still* global after #7 | `user_nl_datm` had a hard-coded global `domainfile=".../domain.nc"` | set `domainfile` in `user_nl_datm` to the 1×1 domain (and the same in `user_datm.streams.txt.CLM1PT.CLM_USRDAT` `<domainInfo>`) |

Diagnostic → log mapping for the iteration loop is in **§Iteration Loop** at the end.

---

## Phase 0 — Prerequisites & path setup

### 0.1 Fixed environment variables (put at the top of every driver script)

```bash
source ~/elm_env_cades_gcc12.sh          # GCC 12.2.0 + OpenMPI 4.1.6 + parallel HDF5/NetCDF/PnetCDF

export MODEL_ROOT=/home/braghiere/BNF_tom/E3SM_global_silent      # surviving ELM/E3SM source
export OLMT=/home/braghiere/BNF_tom/OLMT_BNF                        # OLMT driver
export CASEROOT=/home/braghiere/BNF_tom/OLMT_BNF/cime_case_dirs     # case dirs (home, survived)
export SRCMODS=$CASEROOT/source_codes                              # SourceMods sets (survived)
export RUNROOT=/lustre/or-scratch24/scratch/braghiere              # NEW scratch (writable, ~900 TB)
export CCSM_INPUT=/home/braghiere/BNF_tom/inputdata                # rebuilt local inputdata (11 GB)
export PARAMDIR=/home/braghiere/BNF_tom                            # clm_params + CNP files
export REPO=/home/braghiere/ELM-FUN-BNFMIP                         # this repo

# Fix #3 — real filesystem for compiler temporaries (NOT container /tmp)
export TMPDIR=$RUNROOT/tmp_build && mkdir -p "$TMPDIR"
export GMAKE_J=2
```

> **Note on the old paths.** `REPRODUCE.md`, `scripts/README.md`, `docs/site_info.md`, the
> `per_site/*.sh` scripts, and the packaging scripts still hard-code the **dead**
> `/lustre/or-scratch/cades-ccsi/...` for `RUNROOT`, `CCSM_INPUT`/`DIN_LOC_ROOT`, and the
> packager `S1`. Every one of those must be repointed to `or-scratch24` / the local
> `inputdata` tree above. This is called out again in Phase 4 and Phase 5.

### 0.2 Compute-node rule

Never build/run on a login node. Grab an interactive compute node (fast-iteration path,
avoids the ~4 h batch backlog):

```bash
srun -A ccsi -p burst -N 1 -n 1 -t 4:00:00 --mem 32G \
     --exclude=or-condo-c105,or-condo-c67,or-condo-c04 --pty bash
```

For a case, prefer `./case.submit --no-batch` (runs on the current compute node) over batch
submission during iteration.

### 0.3 Input inventory checklist (verify BEFORE any case creation)

```bash
# --- Source, driver, SourceMods (all in $HOME, survived) ---
test -d $MODEL_ROOT/cime                          && echo OK MODEL_ROOT
test -f $OLMT/site_fullrun.py                      && echo OK OLMT/site_fullrun.py
test -f $OLMT/runcase.py                           && echo OK OLMT/runcase.py
test -f $OLMT/makepointdata.py                     && echo OK OLMT/makepointdata.py
for m in control_fixed_funp_nfix fun_fpg1_nfix \
         noACC_fixed_funp_nfix ACC_fixed_funp_nfix \
         noACC_temperate_funp_nfix ACC_temperate_funp_nfix \
         _shared_elm_fun_col_es; do
  test -d $SRCMODS/$m && echo "OK srcmods $m" || echo "MISSING srcmods $m"
done

# --- Fix #1: PTCLM site metadata staged in $CCSM_INPUT ---
for f in BNF_sitedata.txt BNF_soildata.txt BNF_pftdata.txt; do
  test -f $CCSM_INPUT/lnd/clm2/PTCLM/$f && echo "OK PTCLM $f" || echo "MISSING PTCLM $f  (copy from $OLMT/PTCLM/)"
done

# --- Per-site point surfdata (correct single PFT) + 252-yr CLM1PT met ---
for s in BNF_Man BNF_Har BNF_Bon; do
  ls $CCSM_INPUT/BNFMIP_forcing_from_OCN/$s/surfdata_*.nc 2>/dev/null && echo "OK surfdata $s"
  test -d $CCSM_INPUT/BNFMIP_forcing_from_OCN/$s/CLM1PT_data && echo "OK CLM1PT $s"
done

# --- Global domain (source for the 1x1 helper) + CO2/Ndep ---
test -f $CCSM_INPUT/domain.nc && echo OK global domain
ls $CCSM_INPUT/fco2_datm_ssp585_1765-2100_c260519.nc 2>/dev/null && echo OK ssp585 CO2
ls $CCSM_INPUT/lnd/clm2/ndepdata/fndep_clm_rcp4.5_simyr1849-2106_1.9x2.5_c100428.nc 2>/dev/null && echo OK ndep

# --- Fix #4: aerosol dep symlink ---
ls -l $CCSM_INPUT/atm/cam/chem/trop_mozart_aero/aero/aerosoldep_monthly_1849-2006_1.9x2.5_c090803.nc \
  && echo "OK aerosol link" \
  || echo "MISSING aerosol: ln -s $RUNROOT/e3sm_inputdata_ha1/aerosoldep_monthly_1849-2006_1.9x2.5_c090803.nc  $CCSM_INPUT/atm/cam/chem/trop_mozart_aero/aero/"

# --- Parameter files ---
for p in clm_params_fun3_sfix01.nc clm_params_fun3_sfix01_manaus_tuned.nc \
         clm_params_fun3_sfix01_bon_tuned.nc CNP_parameters.nc \
         CNP_parameters_manaus_oxisol_v2.nc; do
  ls $PARAMDIR/$p $CCSM_INPUT/$p 2>/dev/null | head -1 && echo "OK param $p" || echo "CHECK param $p"
done
```

**Gate 0:** every line prints `OK`. Any `MISSING` → run the remediation shown inline
(the aerosol symlink and PTCLM copy are the two most likely to be missing on a fresh clone).

### 0.4 Known-present staged point data (saves re-generation)

| Location | Contents | Coverage |
|----------|----------|----------|
| `$RUNROOT/manaus_ssp585_staged2/{nofun_baseline,fun_transient_only,noacc_transient,acc_transient}/` | `surfdata.nc`, `surfdata.pftdyn.nc`, `finidat.nc` | Manaus — **complete** (4 exps) |
| `$RUNROOT/ha1_ssp585_staged/` | `{exp}_surfdata.nc`, `{exp}_surfdata.pftdyn.nc`, `{exp}_finidat.nc` | Harvard — **partial** (surf+pftdyn+finidat, no spun-up chain) |
| `$RUNROOT/manaus_ssp585_staged/` | older Manaus stage (superseded by `_staged2`) | Manaus |
| — | **no Bonanza staged point data exists** | Bonanza — must be generated from `BNF_Bon` surfdata |

---

## Phase 1 — Build a 1×1 point domain per site (Fixes #5 + #6)

**Only `domain_BNF-Man_1x1.nc` exists today** (`$CCSM_INPUT/domain_BNF-Man_1x1.nc`,
`xc=299.9783`, `yc=-3.119`, `ni=nj=1`). Harvard and Bonanza domains do **not** exist yet.

The domain's `xc`/`yc` must **exactly equal** the point surfdata `LONGXY`/`LATIXY`
(confirmed: Manaus surfdata `LONGXY=299.9783`, `LATIXY=-3.119` — byte-match to the domain).
Building by "nearest global cell" reintroduces Fix #6.

### 1.1 Reusable helper — `scripts/utils/make_1x1_domain.py`

```python
#!/usr/bin/env python3
"""Build a 1x1 point domain whose xc/yc EXACTLY equal a surfdata LONGXY/LATIXY.
Usage: make_1x1_domain.py <surfdata.nc> <out_domain.nc>
Mirrors the layout of the working domain_BNF-Man_1x1.nc (dims ni=nj=1, nv=4)."""
import sys, numpy as np, netCDF4 as nc

surf, out = sys.argv[1], sys.argv[2]
with nc.Dataset(surf) as s:
    lon = float(np.ravel(s.variables['LONGXY'][:])[0])   # degrees_east (0..360)
    lat = float(np.ravel(s.variables['LATIXY'][:])[0])   # degrees_north
    # cell area/edges: reuse surfdata AREA if present, else a nominal small box
    area = float(np.ravel(s.variables['AREA'][:])[0]) if 'AREA' in s.variables else 1.0

d = nc.Dataset(out, 'w', format='NETCDF3_CLASSIC')
d.createDimension('ni', 1); d.createDimension('nj', 1); d.createDimension('nv', 4)
def v(name, val, units=None, dims=('nj','ni')):
    x = d.createVariable(name, 'f8', dims)
    if units: x.units = units
    x[:] = val
v('xc', lon, 'degrees_east'); v('yc', lat, 'degrees_north')
v('area', area, 'radians^2'); v('mask', 1.0); v('frac', 1.0)
# half-degree corners (order matches CIME expectation: SW,SE,NE,NW)
dx = dy = 0.25
xv = d.createVariable('xv','f8',('nj','ni','nv')); yv = d.createVariable('yv','f8',('nj','ni','nv'))
xv[:] = np.array([lon-dx, lon+dx, lon+dx, lon-dx]).reshape(1,1,4)
yv[:] = np.array([lat-dy, lat-dy, lat+dy, lat+dy]).reshape(1,1,4)
d.close()
print(f'wrote {out}: xc={lon} yc={lat}')
```

### 1.2 Generate the three domains

```bash
cd $REPO/scripts/utils
# Manaus already exists; regenerate only if you want a clean rebuild.
python3 make_1x1_domain.py \
  $CCSM_INPUT/BNFMIP_forcing_from_OCN/BNF_Har/surfdata_0.9x1.25_hist_16pfts_Irrig_CMIP6_simyr2000_BNF_Har_c221109.nc \
  $CCSM_INPUT/domain_BNF-Ha1_1x1.nc
python3 make_1x1_domain.py \
  $CCSM_INPUT/BNFMIP_forcing_from_OCN/BNF_Bon/surfdata_0.9x1.25_hist_16pfts_Irrig_CMIP6_simyr2000_BNF_Bon_c221108.nc \
  $CCSM_INPUT/domain_BNF-Bon_1x1.nc
```

> **Harvard PFT-7 caveat fix.** The Harvard domain is independent of PFT. What clears
> caveat (a) is that the **surfdata used must be single-PFT PFT 7** (temperate
> broadleaf-deciduous). Confirm before use (Gate 1b). If the surviving `BNF_Har` surfdata
> is still PFT 6 (tropical), a PFT-7 surfdata must be produced (edit `PCT_NAT_PFT` so index 7
> = 100 %, all others 0) — this is the one input that has to be *corrected*, not just reused.

### 1.3 Gates

**Gate 1a (coords match).** For each site:
```bash
source ~/elm_env_cades_gcc12.sh
ncdump -v xc,yc      $CCSM_INPUT/domain_BNF-${S}_1x1.nc | sed -n '/data:/,$p'
ncdump -v LONGXY,LATIXY <point surfdata>                | sed -n '/data:/,$p'
```
Expected: `xc == LONGXY` and `yc == LATIXY` to full printed precision. If not → rebuild the
domain from that exact surfdata (do not hand-edit).

**Gate 1b (Harvard PFT).**
```bash
ncdump -v PCT_NAT_PFT <BNF_Har surfdata> | sed -n '/PCT_NAT_PFT =/,$p' | head -12
```
Expected: 100 at the **PFT-7** slot (index 7, i.e. the 8th value; 0=bare ground).
For reference Manaus shows `0,0,0,0,100,...` = PFT 4 (BET tropical) — correct for Manaus.

---

## Phase 2 — Per (site × experiment) case: create → build → run

This is the reusable template for all **12** combinations. It encodes Fixes #1–#8 as ordered
steps, each with a **GATE** and the fix to apply if the gate fails. It reproduces exactly the
sequence recorded in the live Manaus `nofun_baseline` `CaseStatus`.

### 2.0 Per-combo variables (set these, then run 2.1–2.9 unchanged)

| Var | Manaus | Harvard (Ha1) | Bonanza (Bon) |
|-----|--------|---------------|---------------|
| `SITE` | `BNF-Man` | `BNF-Ha1` | `BNF-Bon` |
| `TAG` | `manaus` | `ha1` | `bon` |
| `DOMAIN` | `domain_BNF-Man_1x1.nc` | `domain_BNF-Ha1_1x1.nc` | `domain_BNF-Bon_1x1.nc` |
| `CLM1PT` | `.../BNF_Man/CLM1PT_data` | `.../BNF_Har/CLM1PT_data` | `.../BNF_Bon/CLM1PT_data` |
| paramfile (Exp1/3) | `clm_params_fun3_sfix01_manaus_tuned.nc` | `clm_params_fun3_sfix01.nc` | `clm_params_fun3_sfix01.nc` |
| paramfile (Exp4/5) | `clm_params_fun3_sfix01_manaus_tuned.nc` | `clm_params_fun3_sfix01.nc` | `clm_params_fun3_sfix01_bon_tuned.nc` |
| CNP file | `CNP_parameters_manaus_oxisol_v2.nc` | `CNP_parameters.nc` | `CNP_parameters.nc` |

Experiment → SourceMods (Fix: pick the right set; this is what differentiates the 4 experiments):

| Experiment | Manaus SourceMods | Ha1 / Bon SourceMods | `use_fun` / `use_funp` |
|-----------|-------------------|----------------------|------------------------|
| `nofun_baseline` | `control_fixed_funp_nfix` | `control_fixed_funp_nfix` | `.false.` / `.false.` |
| `fun_transient_only` (Houlton) | `fun_fpg1_nfix` | `fun_fpg1_nfix` | `.true.` / `.true.` |
| `noacc_transient` | `noACC_fixed_funp_nfix` | `noACC_temperate_funp_nfix` | `.true.` / `.true.` |
| `acc_transient` | `ACC_fixed_funp_nfix` | `ACC_temperate_funp_nfix` | `.true.` / `.true.` |

Always also copy `_shared_elm_fun_col_es/*.F90` (shared `clm_driver`/`clm_initializeMod`) on
top of the chosen set.

```bash
export SITE=BNF-Man TAG=manaus EXP=nofun_baseline
export DOMAIN=domain_BNF-Man_1x1.nc
export CLM1PT=$CCSM_INPUT/BNFMIP_forcing_from_OCN/BNF_Man/CLM1PT_data
export PARAMFILE=$PARAMDIR/clm_params_fun3_sfix01_manaus_tuned.nc
export CNPFILE=$PARAMDIR/CNP_parameters_manaus_oxisol_v2.nc
export SRCSET=$SRCMODS/control_fixed_funp_nfix
export CASEID=${EXP}_${TAG}_repro$(date +%Y%m%d)
export SURF=$RUNROOT/manaus_ssp585_staged2/${EXP}/surfdata.nc   # point surfdata (single PFT)
```

### 2.1 Create the case — bypass `makepointdata` (Fixes #1, #2)

`site_fullrun.py`'s first (AD) case would call `makepointdata.py`, which needs the dead
global surfdata_map/share/domain tree. Pass `--nopointdata --surffile --domainfile` so it is
skipped for **all** cases (verified: `site_fullrun.py` has these options at lines 99/132/134;
downstream fn/transient cases already append `--nopointdata` internally).

```bash
cd $OLMT
python3 site_fullrun.py \
    --site $SITE --sitegroup BNF --machine cades \
    --caseidprefix $CASEID \
    --model_root $MODEL_ROOT --ccsm_input $CCSM_INPUT \
    --runroot $RUNROOT --caseroot $CASEROOT \
    --mpilib openmpi --np 1 --walltime 24 --nofire \
    --clm_paramfile $PARAMFILE --clm1pt_dir $CLM1PT \
    --nyears_ad_spinup 200 --nyears_final_spinup 600 \
    --nopointdata --surffile $SURF --domainfile $CCSM_INPUT/$DOMAIN \
    --no_submit --no_build
```

> If `site_fullrun.py` still errors on point data, fall back to driving `runcase.py`
> directly per case (the repro log's working invocation, cleaned):
> ```bash
> python3 runcase.py --site $SITE --sitegroup BNF --machine cades \
>   --ccsm_input $CCSM_INPUT --model_root $MODEL_ROOT \
>   --caseroot $CASEROOT --runroot $RUNROOT \
>   --caseidprefix $CASEID --nofire --clm_paramfile $PARAMFILE \
>   --clm1pt_dir $CLM1PT --mpilib openmpi --pio_version 2 \
>   --np 1 --ng 256 --tstep 0.5 --walltime 24 --project e3sm \
>   --nopointdata --surffile $SURF --domainfile $CCSM_INPUT/$DOMAIN \
>   --ad_spinup --nyears_ad_spinup 200 --align_year 2 \
>   --hist_mfilt 1 --hist_nhtfrq -2190000 --rmold --no_submit --no_build \
>   --compset I1850CNRDCTCBC
> ```

**Gate 2.1:** the AD case dir exists under `$CASEROOT/${CASEID}_${SITE}_I1850CNRDCTCBC_ad_spinup`
and `create_newcase.log` shows no `makepointdata`/`Site data file not found`/`Error creating
point data` error. If it fails with `BNF_sitedata.txt` not found → **Fix #1** (copy PTCLM
metadata, §0.3). If `PointCLM: Error creating point data` → you omitted `--nopointdata` (**Fix #2**).

### 2.2 Install SourceMods (experiment differentiator)

```bash
AD=$CASEROOT/${CASEID}_${SITE}_I1850CNRDCTCBC_ad_spinup
mkdir -p $AD/SourceMods/src.clm
cp $SRCSET/*.F90                         $AD/SourceMods/src.clm/
cp $SRCMODS/_shared_elm_fun_col_es/*.F90 $AD/SourceMods/src.clm/
ls $AD/SourceMods/src.clm/*.F90 | wc -l   # expect > 0
```

**Gate 2.2:** file count > 0 and includes the shared driver files. For FUN experiments,
confirm the fix-bearing files are present (`AllocationMod.F90` with the `fpg_p` guard,
`NitrogenDynamicsMod.F90` with `freelivfix_slope=0.5e-4`) — see `docs/corrections.md` #1/#2.

### 2.3 Point-domain xmlchange block (Fixes #5, #7) + local inputdata roots

Applied in the live case via these exact `xmlchange` calls (from `CaseStatus`):

```bash
cd $AD
./xmlchange DIN_LOC_ROOT=$CCSM_INPUT
./xmlchange DIN_LOC_ROOT_CLMFORC=$CLM1PT
./xmlchange ATM_DOMAIN_PATH=$CCSM_INPUT,LND_DOMAIN_PATH=$CCSM_INPUT
./xmlchange ATM_DOMAIN_FILE=$DOMAIN,LND_DOMAIN_FILE=$DOMAIN
# Fix #7: force single-point grid sizes on every component that carries a gsmap
./xmlchange ATM_NX=1,ATM_NY=1,LND_NX=1,LND_NY=1,ROF_NX=1,ROF_NY=1
./xmlchange EXEROOT=$RUNROOT/${CASEID}_${SITE}_I1850CNRDCTCBC_ad_spinup/bld
./xmlchange RUNDIR=$RUNROOT/${CASEID}_${SITE}_I1850CNRDCTCBC_ad_spinup/run
./xmlchange PIO_VERSION=2 --id PIO_TYPENAME --val netcdf
./xmlchange STOP_OPTION=nyears,STOP_N=200
./xmlchange DOUT_S=FALSE
./xmlchange -id BATCH_SYSTEM --val none      # enables --no-batch iteration
./case.setup
```

### 2.4 `user_nl_datm` + DATM stream domain (Fix #8)

The single most-missed fix: OLMT writes a hard-coded **global** `domainfile` into
`user_nl_datm` and the CLM1PT stream. Both must point at the 1×1 domain.

```bash
# user_nl_datm: ensure exactly one domainfile line, pointing at the 1x1 domain
sed -i '/^domainfile/d' $AD/user_nl_datm
echo "domainfile = \"$CCSM_INPUT/$DOMAIN\"" >> $AD/user_nl_datm

# CLM1PT stream <domainInfo><fileNames>: replace global domain.nc with the 1x1 domain
sed -i "s#domain\.nc#$DOMAIN#g" $AD/user_datm.streams.txt.CLM1PT.CLM_USRDAT
```

**Gate 2.4:**
```bash
grep domainfile $AD/user_nl_datm                              # -> the 1x1 domain, once
grep -A2 '<fileNames>' $AD/user_datm.streams.txt.CLM1PT.CLM_USRDAT | grep domain   # -> 1x1 domain
```
(The live Manaus case's `user_nl_datm` line 28 reads
`domainfile = "/home/braghiere/BNF_tom/inputdata/domain_BNF-Man_1x1.nc"` — this is the target state.)

### 2.5 Build (Fix #3)

```bash
export TMPDIR=$RUNROOT/tmp_build && mkdir -p "$TMPDIR"   # Fix #3
export GMAKE_J=2
cd $AD
./xmlchange BUILD_COMPLETE=FALSE
./case.build 2>&1 | tee build_${EXP}.log
```

**Gate 2.5:** `MODEL BUILD HAS FINISHED SUCCESSFULLY` and
`test -f $RUNROOT/${CASEID}_${SITE}_I1850CNRDCTCBC_ad_spinup/bld/e3sm.exe`.
- If `can't open /tmp/*.s` → `TMPDIR` not set to a real FS (**Fix #3**), re-export and rebuild.
- If `env_build HAS CHANGED ... A manual clean of your obj directories is required` (this
  appears whenever you changed `ATM_NX/NY` etc. after a prior build, Fix #7) → **`./case.build --clean-all`** then rebuild. In the live case the clean rebuild took ~210 s and then succeeded.

### 2.6 Namelist / finidat / CNP (site-specific)

```bash
# Manaus only: inject oxisol P rates into FN + transient (AD is CN-only, not needed there)
#   fsoilordercon = '$CNPFILE'    (append or replace in user_nl_clm of FN & TR cases)
# AD spinup namelist (already written by OLMT): confirm the science switches
grep -E 'use_fun|use_funp|use_nitrif_denitrif|use_nofire|spinup_mortality_factor|nyears_ad_carbon_only' $AD/user_nl_clm
```
Expected for `nofun_baseline` AD: `use_fun=.false.`, `use_funp=.false.`,
`nyears_ad_carbon_only=25`, `spinup_mortality_factor=10`. For FUN experiments the FN and
transient stages set `use_fun=.true.`/`use_funp=.true.` (AD stays CN-only regardless).

### 2.7 First smoke run (short) on a compute node

Iterate cheaply: run 2 years with `--no-batch` and watch the coupler come up single-point.

```bash
cd $AD
./xmlchange STOP_OPTION=nyears,STOP_N=2,REST_N=2
./case.submit --no-batch 2>&1 | tee run_smoke.log
```

**Gate 2.7 (the coupler-init gate — the make-or-break one).** Tail the logs in
`$RUNROOT/${CASEID}_${SITE}_I1850CNRDCTCBC_ad_spinup/run/`:
- **`e3sm.log.*`** must reach `model execution` without an `MPI_ABORT ... errorcode 1001`.
- **PASS looks like:** DATM initializes, `(component_init_cc:mct) : Initialize component lnd`
  passes, and the run advances past day 1.
- **FAIL signatures → fix:**
  | log line | fix |
  |----------|-----|
  | DATM `data sizes 1 1 17520 55296` | domain still global → **Fix #5** (2.3) |
  | CLM `surfdata/fatmgrid lon/lat mismatch` | domain coords ≠ surfdata → **Fix #6** (Phase 1, rebuild domain) |
  | `(seq_map_gsmapcheck) different gsmap size` | either `ATM_NX/NY` not 1 (**Fix #7**, needs `--clean-all` rebuild) **or** `user_nl_datm` still global (**Fix #8**, 2.4) |
  | missing `aerosoldep_*.nc` | **Fix #4** (symlink, §0.3) |
  | `srun: ... Requested nodes are busy` | **not a model error** — node/queue contention; resubmit or grab a fresh interactive node (this is exactly what blocked jobs 5452444/5452476) |

Once Gate 2.7 passes on the 2-yr smoke test, reset to the full spin-up length (2.3:
`STOP_N=200` AD) and proceed to Phase 3.

### 2.8 Loop template

Wrap 2.0–2.7 in a bash function `build_case SITE EXP` and call it for the 12 combos.
Because the **executable only depends on the SourceMods + machine**, you can build **once per
(experiment × site-mods-flavor)** and reuse `EXEROOT` across the AD/FN/TR/§5.4 cases of that
experiment (the `per_site` scripts already do this via
`./xmlchange BUILD_COMPLETE=TRUE; ./xmlchange EXEROOT=<shared bld>`). That reduces 12+ builds
to ~6 distinct executables:

| Executable | Experiments/sites sharing it |
|-----------|------------------------------|
| `control_fixed_funp_nfix` | nofun_baseline — all 3 sites |
| `fun_fpg1_nfix` | fun_transient_only — all 3 sites |
| `noACC_fixed_funp_nfix` | noacc — Manaus |
| `noACC_temperate_funp_nfix` | noacc — Ha1, Bon |
| `ACC_fixed_funp_nfix` | acc — Manaus |
| `ACC_temperate_funp_nfix` | acc — Ha1, Bon |

(The point surfdata/domain/finidat differ per site and are set by xmlchange/namelist, not the exe.)

---

## Phase 3 — Full spin-up → transient → §5.4 → §5.5 sequence (per site × experiment)

Chain and restart hand-offs (per `scripts/per_site/*.sh` and `docs/corrections.md`):

```
AD spin-up (I1850CNRDCTCBC, 200 yr, CN-only, use_fun/funp=.false.)
   └─ restart yr 201  ── iniadjust (OLMT) ──▶ finidat for FN
FN spin-up (I1850CNPRDCTCBC, 600 yr)
   ├─ nofun: use_fun/funp=.false.
   └─ FUN exps: use_fun/funp=.true.  (FUN spin-up; needs the fixed exe, corrections #1/#2)
   └─ restart yr 601  ──▶ finidat for transient
§5.3 transient (I20TRCNPRDCTCBC, 1850–2014, transient CO2/Ndep)
   └─ restart 2015-01-01  ──▶ BOTH §5.4 and §5.5 branch from here
§5.4 (2015–2100): clone §5.3 case, RUN_STARTDATE=2015, fixed CO2 + Ndep locked @2014
§5.5 (2015–2100): repurpose the §5.4 case, switch CO2/Ndep to transient SSP5-8.5
```

### 3.1 Spin-up convergence criterion (protocol §5.2)

Constant 1850 CO₂/Ndep to equilibrium: drift over 50 yr **< 1 gC/m²/yr TOTECOC** and
**< 0.5 gN/m²/yr TOTECON**. Use 50-yr history output during spin-up to cut I/O
(`hist_nhtfrq = -438000, -438000`, as the `per_site` scripts do). Check FUN sanity after
spin-up with `scripts/utils/check_bnf_sanity.py <h0>` — expected Manaus `COST_NFIX≈7.2 gC/gN`,
`FFIX_TO_SMINN≈72 mgN/m²/yr` (`docs/corrections.md` sanity table).

### 3.2 §5.4 (fixed CO₂ + Ndep) — clone from §5.3

```bash
# From the §5.3 transient case, create a clone starting at 2015 from the 2015-01-01 restart:
$MODEL_ROOT/cime/scripts/create_clone --case <5.4_case> --clone <5.3_case> --keepexe
cd <5.4_case>
./xmlchange RUN_STARTDATE=2015-01-01,STOP_OPTION=nyears,STOP_N=86
./xmlchange CLM_CO2_TYPE=constant        # or DATM_CO2_TSERIES=none, per compset
./xmlchange CCSM_CO2_PPMV=397.7641       # 2014 value from fco2_datm_rcp4.5_1765-2500_c130312.nc
# Correction #4: lock Ndep in user_nl_clm
printf 'stream_year_first_ndep = 2014\nstream_year_last_ndep = 2014\n' >> user_nl_clm
```
> **CO₂ value note.** `scripts/README.md`/`resubmit_BNFMIP_v2.sh` use **397.7641 ppmv**
> (2014) with Ndep locked at 2014; `docs/corrections.md` #4 quotes 398.87 (2015). Use the
> value already baked into `resubmit_BNFMIP_v2.sh` for byte-consistency with the delivered
> data, and record whichever you use in the run notes.

### 3.3 §5.5 (SSP5-8.5 transient) — repurpose §5.4 (the discontinuity fix)

Do **not** use the dead dedicated `*_ssp585_*_20260523_*` builds (defective vegetation load,
`docs/corrections.md` #5). Instead take the sound §5.4 case and switch only the forcing:

```bash
cd <5.4_case>            # same case, now becomes §5.5
./xmlchange CLM_CO2_TYPE=diagnostic       # transient CO2 from the DATM stream
# CO2 stream -> SSP585
sed -i 's#fco2_datm[^<]*#fco2_datm_ssp585_1765-2100_c260519.nc#' \
    user_datm.streams.txt.co2tseries.20tr
# transient Ndep
sed -i 's/stream_year_first_ndep = .*/stream_year_first_ndep = 2015/' user_nl_clm
sed -i 's/stream_year_last_ndep  = .*/stream_year_last_ndep = 2100/'  user_nl_clm
./xmlchange RUN_STARTDATE=2015-01-01,STOP_N=86
```
Because it branches from the same §5.3 2015 restart with continuous state, the 2015 join is
smooth by construction — this is exactly what cleared the Manaus §5.5 caveat and must now be
applied uniformly to all 3 sites (Manaus was already done this way for the delivery; Ha1/Bon
were run from the now-superseded `submit_ssp585_cases.py`).

**Gate 3 (per stage):** each stage writes its expected restart
(`*.clm2.r.<date>-00000.nc`) and `check_bnf_sanity.py`/GPP>0 pass. The §5.3→§5.4/§5.5 branch
must read the **2015-01-01** restart of the *same experiment/site*.

---

## Phase 4 — Packaging + verification + Tom bundle

### 4.1 Repoint the packagers to `or-scratch24` (REQUIRED — current gap)

Both packagers hard-code the **dead** run root:
- `scripts/package_table2.py`: `S1='/lustre/or-scratch/cades-ccsi/scratch/braghiere'` (used
  by `resolve()` for all sections) and `S24=` is defined but unused.
- `scripts/package_manaus_sec55.py`: `RUN_BASE='/lustre/or-scratch/cades-ccsi/scratch/braghiere'`.

Update both to the regenerated run dirs under `/lustre/or-scratch24/scratch/braghiere` (and
update the `_20260521_`/`_20260529_fixed_` case stems to the new repro CASEIDs). Also update
`OUTDIR`/`OUTBASE` if you want a fresh delivery dir.

### 4.2 Run the packagers

```bash
cd $REPO/scripts
python3 package_bnfmip_outputs.py --section all   # quick annual-mean set
python3 package_table2.py all                      # full 54-var Table-2 (monthly)
python3 package_manaus_sec55.py                    # §5.5 annual (all sites; continuation)
```

Output layout (target — matches the current delivery, 36 files each):
`{OUTDIR}/{BNF-Man,BNF-Ha1,BNF-Bon}/{exp}_{site}_sec{53,54,55}_{years}[_table2].nc`
(3 sites × 4 experiments × 3 sections = 36).

### 4.3 Verification gates

```bash
# GPP > 0 and forest ALIVE (package_manaus_sec55.py prints this):
#   "... end GPP=#### VegC=#### ALIVE"   (DEAD if end-decade GPP <= 30)
# Smooth 2015 join: last §5.3 year (2014) vs first §5.5 year (2015) within a few %:
python3 - <<'PY'
import xarray as xr
for site in ['BNF-Man','BNF-Ha1','BNF-Bon']:
  for exp in ['nofun_baseline','fun_transient_only','noacc_transient','acc_transient']:
    a=xr.open_dataset(f'.../{site}/{exp}_{site}_sec53_1850-2014.nc')
    b=xr.open_dataset(f'.../{site}/{exp}_{site}_sec55_2015-2100.nc')
    g14=float(a['GPP'].isel(year=-1)); g15=float(b['GPP'].isel(year=0))
    print(site,exp,f'GPP 2014={g14:.0f} 2015={g15:.0f} jump={100*(g15-g14)/g14:+.1f}%')
PY
# Table-2 completeness: expect ~54 variables per file
python3 -c "import xarray as xr,glob; [print(f.split('/')[-1], len(xr.open_dataset(f).data_vars)) for f in glob.glob('.../*/*_table2.nc')]"
```

**Gate 4:** every file has GPP>0 through 2100 (all sites, incl. Harvard PFT-7 rebuild), the
2015 jump is small (no discontinuity), and each Table-2 file carries the full variable set.
Harvard absolute GPP/NPP should now be **higher** than the caveated PFT-6 delivery (PFT 7 has
~41 % higher `flnr`).

### 4.4 Rebuild the Tom bundle

```bash
cd /home/braghiere/BNF_tom
tar czf delivery/BNFMIP_ELM-FUN_delivery_$(date +%Y-%m-%d).tar.gz -C delivery BNF-Man BNF-Ha1 BNF-Bon README_for_Tom.md
tar czf delivery/BNFMIP_ELM-FUN_Table2_$(date +%Y%m%d).tar.gz     -C delivery_table2 BNF-Man BNF-Ha1 BNF-Bon README_for_Tom.md
```
Update `delivery/README_for_Tom.md` and `delivery_table2/README_for_Tom.md` to drop the two
now-fixed caveats (Harvard PFT-6, §5.5 discontinuity) and keep the remaining notes
(H2OSOI units, SMINP magnitude).

---

## Phase 5 — Document & archive (so this never happens again)

1. **Update `REPRODUCE.md`:** set `RUNROOT=/lustre/or-scratch24/scratch/$USER`,
   `INPUTDATA=/home/<user>/BNF_tom/inputdata` (or a durable copy), add the 8-fix section
   (point domain, `TMPDIR`, `--nopointdata`, aerosol symlink, `ATM_NX/NY=1`, `user_nl_datm`
   domain), and remove the Harvard PFT-6 + §5.5 caveats from "Known caveats".
2. **Update `scripts/README.md`, `docs/site_info.md`, `per_site/*.sh`, packagers:** replace
   every `/lustre/or-scratch/cades-ccsi/...` with the `or-scratch24` / local `inputdata` paths.
3. **Archive the regenerated artifacts to durable storage** (home or HPSS), so a future
   scratch loss is recoverable without a full rebuild:
   - the ~6 executables (`bld/e3sm.exe` per experiment flavor),
   - the point surfdata/pftdyn/finidat per site×experiment (`manaus_ssp585_staged2/`,
     `ha1_ssp585_staged/`, and the new Bonanza stage),
   - the 1×1 domains (`domain_BNF-{Man,Ha1,Bon}_1x1.nc`),
   - the 2015-01-01 restarts and final restarts of each chain,
   - the delivery + delivery_table2 trees and their tarballs.
4. **Commit** the new `make_1x1_domain.py`, this plan, and the path edits to the repo.

---

## Effort / time estimates

| Phase | Wall-clock | Notes |
|-------|-----------|-------|
| 0 — prereqs/inventory | 15–30 min | mostly `test`/`ncdump`; symlink + PTCLM copy if missing |
| 1 — 1×1 domains (Ha1, Bon) + Harvard PFT-7 surfdata | 30–60 min | domain gen is seconds; PFT-7 surfdata edit + gate is the work |
| 2 — build (~6 exes) | ~4 min each clean; ~3.5 min if only SourceMods change; **+3.5 min for the `--clean-all` after `ATM_NX/NY`** | build log shows 21 s incremental / 210 s clean-all; smoke run 2 yr ≈ 30–60 s |
| 2 — get first clean AD init (Gate 2.7) | minutes once a node is free | **the current blocker is node availability, not the model** |
| 3 — spin-up chain (**the long pole**) | AD 200 yr + FN 600 yr + FUN 200 yr per case | at single-point ELM speeds this is the dominant cost — plan for **many hours to a few days per experiment** end-to-end; run the 6 exe-flavors in parallel across nodes |
| 3 — §5.3 (165 yr) + §5.4/§5.5 (86 yr ea.) | hours per case | branch from 2015 restart; §5.4 and §5.5 are cheap relative to spin-up |
| 4 — packaging + verify | 30–60 min | I/O-bound; `package_table2 all` iterates all cases |
| 5 — docs + archive | 1–2 hr | tar + HPSS/home copy of exes+restarts is the bulk |

**Batch vs `--no-batch`.** Batch queue backlog was ~4 h during this work; interactive
`--no-batch` on a `burst` compute node is the fast-iteration path (used for all the 2026-07-08
repro attempts). Use batch only for the long unattended spin-ups, with dependency chains
(`sbatch --dependency=afterok:JID`, or `./case.submit --prereq JID` — the `--batch-args`
dependency form hangs for Ha1/Bon per `scripts/README.md`).

---

## Iteration loop (detect → diagnose → fix → cheap re-run)

1. **Detect.** A stage fails a gate: `CaseStatus` shows `case.run error` /
   `RUN FAIL: ... e3sm.exe ... failed`, or `case.build error`.
2. **Diagnose — go to the right log** in the run dir
   `$RUNROOT/<case>/run/`:
   - **`e3sm.log.<jid>.*`** — the master stdout; `MPI_ABORT ... errorcode 1001` + the last
     component line tells you which component aborted.
   - **`cpl.log.*`** — coupler; `(seq_map_gsmapcheck) different gsmap size` = grid-size
     mismatch (Fix #7 or #8).
   - **`lnd.log.*`** — CLM; `surfdata/fatmgrid lon/lat mismatch` = Fix #6; also shows the
     `SUPL NITROGEN and PHOSPHORUS` init line just before a domain abort.
   - **`atm.log.*`** / **`datm_in`** / **`datm.streams.txt.CLM1PT.CLM_USRDAT`** — DATM;
     `data sizes 1 1 17520 55296` = global domain (Fix #5); check the `<domainInfo>` filename
     (Fix #8).
   - build fail → `bld/e3sm.bldlog.*` (`can't open /tmp/*.s` = Fix #3).
3. **Fix.** Apply the mapped fix from the Fix Legend / Gate 2.7 table.
4. **Re-run cheaply.** On a compute node: `./case.submit --no-batch` for a 2-yr smoke test
   (`STOP_N=2`) before committing to the full length. If you changed `ATM_NX/NY` (Fix #7) you
   **must** `./case.build --clean-all` first (else `case.submit` errors
   `Build complete is not True` / `env_build HAS CHANGED`). If the only failure is
   `Requested nodes are busy`, just resubmit / get a fresh node — no code change needed.

---

## Risk register (remaining unknowns)

| Risk | Likelihood | Impact | Mitigation / watch |
|------|-----------|--------|--------------------|
| **Node availability** blocks even correct runs (`Requested nodes are busy` — hit on 2026-07-08) | High | Slows everything | Hold an interactive `burst` node; submit long spin-ups to batch with dependencies; exclude flaky nodes (`--exclude=or-condo-c105,or-condo-c67,or-condo-c04`) |
| **FUN-experiment builds need different SourceMods** than the validated `control_fixed_funp_nfix` (only nofun is proven end-to-end so far) | Medium | Per-exe rework | Rebuild per flavor with the §2.8 table; re-verify Gate 2.7 for each; confirm `fpg_p` guard + `freelivfix_slope` fixes are compiled in (corrections #1/#2) |
| **Bonanza point data missing** — no `bon_ssp585_staged`; only `BNF_Bon` source surfdata exists | High | Blocks Bon transient/§5.5 | Generate Bon surfdata/pftdyn/finidat from `BNF_Bon` surfdata + a fresh Bon spin-up; note Bon is boreal PFT 2 (single-PFT) |
| **Harvard PFT-7 surfdata may not exist** — surviving `BNF_Har` surfdata could still be PFT 6 | Medium | Caveat (a) not actually cleared | Gate 1b; if PFT 6, build a PFT-7 surfdata (edit `PCT_NAT_PFT`) and do a fresh Harvard spin-up (multi-day) |
| **Spin-up may not converge** to the §5.2 drift criterion in 200/600/200 yr | Medium | Extra spin-up cycles | Check drift every 50 yr; extend `nyears_final_spinup` if TOTECOC/TOTECON still drifting |
| **First clean AD run not yet demonstrated** (frontier) — a non-obvious runtime bug could still surface past coupler init | Low–Medium | Recipe gap | Get one full AD to completion before fanning out to 12 combos; keep the 2-yr smoke test as the gate |
| **Packager path drift** — both packagers still point at dead `/lustre/or-scratch` | High (certain) | Empty deliveries | Phase 4.1 repoint is mandatory; verify `NO FILES` messages are gone |
| **CO₂ value ambiguity** (397.7641 vs 398.87) for §5.4 | Low | Minor bias / non-repro | Use the `resubmit_BNFMIP_v2.sh` value (397.7641) for consistency; record it |
| **Queue dependency form** `--batch-args=--dependency` hangs for Ha1/Bon | Medium | Stuck submissions | Use `./case.submit --prereq JID` (per `scripts/README.md` known issue) |
| **Durability** — `or-scratch24` is scratch, not backed up | Medium | Repeat of the disaster | Phase 5.3 archive of exes/restarts/point-data to home or HPSS |

---

## Appendix — quick reference (real paths & values)

```
Source ELM/E3SM : /home/braghiere/BNF_tom/E3SM_global_silent
OLMT            : /home/braghiere/BNF_tom/OLMT_BNF   (site_fullrun.py, runcase.py, makepointdata.py)
Case dirs       : /home/braghiere/BNF_tom/OLMT_BNF/cime_case_dirs
SourceMods sets : .../cime_case_dirs/source_codes/{control_fixed_funp_nfix, fun_fpg1_nfix,
                    noACC_fixed_funp_nfix, ACC_fixed_funp_nfix, noACC_temperate_funp_nfix,
                    ACC_temperate_funp_nfix, _shared_elm_fun_col_es}
Local inputdata : /home/braghiere/BNF_tom/inputdata   (DIN_LOC_ROOT)
  point surfdata: inputdata/BNFMIP_forcing_from_OCN/BNF_{Man,Har,Bon}/surfdata_*.nc
  CLM1PT met    : inputdata/BNFMIP_forcing_from_OCN/BNF_{Man,Har,Bon}/CLM1PT_data
  global domain : inputdata/domain.nc  (288x192 — source for the 1x1 helper only)
  1x1 domains   : inputdata/domain_BNF-Man_1x1.nc (exists); Ha1/Bon TO BUILD (Phase 1)
  aerosol (link): inputdata/atm/cam/chem/trop_mozart_aero/aero/aerosoldep_monthly_1849-2006_1.9x2.5_c090803.nc
                  -> /lustre/or-scratch24/scratch/braghiere/e3sm_inputdata_ha1/...
  CO2 ssp585    : inputdata/fco2_datm_ssp585_1765-2100_c260519.nc
  Ndep          : inputdata/lnd/clm2/ndepdata/fndep_clm_rcp4.5_simyr1849-2106_1.9x2.5_c100428.nc
  PTCLM meta    : inputdata/lnd/clm2/PTCLM/BNF_{site,soil,pft}data.txt   (Fix #1)
Scratch (NEW)   : /lustre/or-scratch24/scratch/braghiere   (RUNROOT; TMPDIR=$RUNROOT/tmp_build)
  staged Manaus : $RUNROOT/manaus_ssp585_staged2/{exp}/{surfdata,surfdata.pftdyn,finidat}.nc
  staged Ha1    : $RUNROOT/ha1_ssp585_staged/{exp}_{surfdata,surfdata.pftdyn,finidat}.nc (partial)
  aerosol src   : $RUNROOT/e3sm_inputdata_ha1/
Params          : /home/braghiere/BNF_tom/clm_params_fun3_sfix01{,_manaus_tuned,_bon_tuned}.nc
                  /home/braghiere/BNF_tom/CNP_parameters_manaus_oxisol_v2.nc ; inputdata/CNP_parameters.nc
Env             : ~/elm_env_cades_gcc12.sh   (module: gcc/12.2.0 openmpi/4.1.6 python/3.10.14
                    hdf5/1.14.3-mpi netcdf-c/4.9.2 netcdf-fortran/4.6.1 parallel-netcdf/1.12.3)
Delivery        : /home/braghiere/BNF_tom/delivery (annual) ; delivery_table2 (54-var Table-2)
Compsets        : AD I1850CNRDCTCBC · FN I1850CNPRDCTCBC · transient/5.4/5.5 I20TRCNPRDCTCBC
Contact attr    : as set in the packaging scripts (PI email) — do not hard-code elsewhere
```
