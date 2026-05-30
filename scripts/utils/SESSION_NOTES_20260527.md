# BNFMIP Resubmit Session — May 27, 2026

## What was done tonight

### Bugs fixed in `resubmit_all_bnfmip.sh`
1. **pipefail + ls crash** — `ls *.h0.*.nc | wc -l` exited with code 1 when no files found.
   Fixed to: `find "${RUN_DIR}" -maxdepth 1 -name "*.clm2.h0.*.nc" 2>/dev/null | wc -l`

2. **Missing `--mem` in chain scripts** — CADES cluster requires explicit `--mem` for all sbatch jobs.
   Fixed: added `#SBATCH --mem=32G` to all chain_*.sh headers.

3. **Wrong grep pattern for CIME job ID** — CIME prints `"Submitted job case.run with id XXXX"`,
   not `"Submitted batch job XXXX"`. Grep returned empty → transients never queued.
   Fixed to: `grep -oP '(?:Submitted batch job|Submitted job case\.run with id) \K[0-9]+'`

4. **`--batch-args` hang for Bon/Ha1** — `case.submit --batch-args="--dependency=afterok:JID"`
   hung for non-Manaus sites. All 9 transient dependencies were submitted manually using
   `./case.submit --prereq JID` (native CIME option).
   **TODO**: Update the master script's transient submission section to use `--prereq` instead.

### Code fixes (applied before build, verified in SourceMods)
- `NitrogenDynamicsMod.F90`: `freelivfix_slope = 0.5e-4_r8` (was `6.0e-4`)
  → Expected FFIX_TO_SMINN at Manaus: ~72 mgN/m²/yr (was ~718)
- Param files: `s_fix = -6.0` (was `-0.1`)
  → Expected COST_NFIX at Manaus ~31°C: ~7.2 gC/gN (was ~0.12)

### Builds
- 6 direct builds completed successfully
- 3 recovery builds (fun_ha1, noacc_ha1, noacc_manaus) ran without `--clean`
  due to concurrent build collision that corrupted Buildconf on first attempt
- All logs in: `/home/braghiere/BNF_tom/OLMT_BNF/build_jobs_20260527_2210/`

---

## Job queue status at submission (~22:14–22:28 EDT)

| Funsp JID | Experiment         | Site   | Transient JID |
|-----------|--------------------|--------|---------------|
| 5389270   | fun_transient_only | Manaus | 5389283       |
| 5389271   | acc_transient      | Manaus | 5389284       |
| 5389279   | noacc_transient    | Manaus | 5389282       |
| 5389273   | fun_transient_only | Bon    | 5389297       |
| 5389274   | acc_transient      | Bon    | 5389298       |
| 5389272   | noacc_transient    | Bon    | 5389296       |
| 5389280   | fun_transient_only | Ha1    | 5389301       |
| 5389275   | acc_transient      | Ha1    | 5389299       |
| 5389281   | noacc_transient    | Ha1    | 5389300       |

All transients have `afterok` dependency on their corresponding funsp job.

---

## What to check tomorrow morning

### 1. Job status
```bash
squeue -u braghiere --format="%.10i %.8P %.35j %.2t %.10M %R"
```
- All 9 funsp should be COMPLETE (or still running if slow)
- All 9 transients should be RUNNING (or queued `afterok` if funsp still going)
- If any job shows `(launch failed)` or is missing, check the chain log:
  `/home/braghiere/BNF_tom/OLMT_BNF/build_jobs_20260527_2210/chain_*.out`

### 2. NFIX sanity check — did the fixes take effect?
Expected timeline: funsp ~200yr × ~1-2 min/yr ≈ complete ~01:00–02:00 AM.
Check h0 files in a funsp run dir:
```bash
RUNROOT=/lustre/or-scratch/cades-ccsi/scratch/braghiere
CASE=fun_transient_only_manaus_20260521_funsp_BNF-Man_I1850CNPRDCTCBC
ls ${RUNROOT}/${CASE}/run/*.clm2.h0.*.nc | wc -l
```
Then check key variables (use any year after year 1):
```bash
F=$(ls ${RUNROOT}/${CASE}/run/*.clm2.h0.*.nc | sort | tail -1)
python3 -c "
import netCDF4 as nc, numpy as np
d = nc.Dataset('$F')
for v in ['COST_NFIX','FFIX_TO_SMINN','NFIX_TO_SMINN','SMINN','NPP_NFIX']:
    x = np.ma.compressed(d[v][:])
    if len(x): print(f'{v:20s}: {x[0]:.4f} {d[v].units}')
"
```

**Expected "working" values at Manaus (annual mean):**
| Variable | Expected | Bad (old params) |
|---|---|---|
| `COST_NFIX` | ~7.2 gC/gN | ~0.12 gC/gN |
| `FFIX_TO_SMINN` | ~2.3e-9 gN/m²/s (~72 mgN/m²/yr) | ~2.3e-8 (~718 mgN/m²/yr) |
| `NFIX_TO_SMINN` | growing over years as SMINN drains | near zero throughout |
| `SMINN` | declining from ~5.7 gN/m² toward ~0.5 | stuck at ~5.7 |

### 3. Check transient start
Once funsp completes, the transient should auto-start. Verify:
```bash
ls ${RUNROOT}/fun_transient_only_manaus_20260521_BNF-Man_I20TRCNPRDCTCBC/run/*.clm2.h0.*.nc 2>/dev/null | wc -l
```

### 4. If a funsp or transient FAILED
Check the SLURM stderr log in the run dir:
```bash
ls ${RUNROOT}/${CASE}/run/*.err 2>/dev/null | xargs tail -30
```
Or the chain log for the experiment:
```bash
cat /home/braghiere/BNF_tom/OLMT_BNF/build_jobs_20260527_2210/chain_fun_manaus_*.err
```

---

## Remaining TODO
- [ ] Fix `resubmit_all_bnfmip.sh` transient section: replace
  `./case.submit --batch-args="--dependency=afterok:\${FUNSP_JID}"`
  with `./case.submit --prereq \${FUNSP_JID}`
- [ ] Evaluate funsp output once runs complete (notebook: `BNFMIP_site_evaluation.ipynb`)
- [ ] Compare FFIX/NFIX time series across all 3 experiments × 3 sites
