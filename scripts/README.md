# Scripts

All scripts here are the actual files used to create and submit the canonical **0521/0529** BNFMIP cases.  
Old test/development scripts (`run_manaus_acc.sh`, `run_houlton_*.sh`, etc.) are **not** included here.

---

## Canonical case naming

| Phase | Date stamp | Example case |
|-------|-----------|--------------|
| AD + FN spinup | `20260521` | `nofun_baseline_manaus_20260521_BNF-Man_I1850CNRDCTCBC_ad_spinup` |
| FUN spinup | `20260521_funsp` | `acc_transient_manaus_20260521_funsp_BNF-Man_I1850CNPRDCTCBC` |
| Section 5.3/5.5 historical+transient | `20260521` | `fun_transient_only_bon_20260521_BNF-Bon_I20TRCNPRDCTCBC` |
| **Section 5.4 fixed CO2+Ndep** | `20260529_fixed` | `noacc_transient_ha1_20260529_fixed_BNF-Ha1_I20TRCNPRDCTCBC` |

---

## Top-level orchestration scripts

### `resubmit_BNFMIP_v2.sh` — **THE canonical submission script**
Phases 1–4 in one file.  Run once with `--dry-run` first.

```
Phase 1 — FUN funsp   (9 cases, Batch A, independent)
Phase 2 — FUN 5.3/5.5 transient (9 cases, Batch B, dep on Batch A)
Phase 3 — nofun transient (3 cases, Batch C, independent)
Phase 4 — Fixed 5.4 runs (12 new clones, dep on Batch B/C)
```

Key values:
- `DATE=20260521`, `FIXDATE=20260529`
- `CO2_2014=397.7641` ppmv (from `fco2_datm_rcp4.5_1765-2500_c130312.nc` year 2014)
- Ndep locked: `stream_year_first_ndep=2014`, `stream_year_last_ndep=2014`
- Paramfiles: `clm_params_fun3_sfix01.nc` (ha1/bon nofun), `clm_params_fun3_sfix01_manaus_tuned.nc` (manaus), `clm_params_fun3_sfix01_bon_tuned.nc` (bon FUN exps)

### `resubmit_phase4_fixed.sh` — Phase 4 only (standalone)
Use when transients have already run and you need to launch only the fixed 0529 cases.
Hardcodes the transient SLURM job IDs from the May 2026 run.

### `resubmit_missing6.sh` — Emergency re-queue
Fixes 6 failed transient runs that crashed due to stale `rpointers` + `CONTINUE_RUN=FALSE`.
Includes dependent `resubmit_phase4_fixed` wrappers.

---

## `per_site/` — Initial case creation scripts

Used to set up the 0521 case directories from scratch (run before `resubmit_BNFMIP_v2.sh`).

| Script | Experiment | Sites |
|--------|-----------|-------|
| `run_manaus_nofun_baseline.sh` | Exp 1 (FUN OFF) | Manaus |
| `run_manaus_fun_transient_only.sh` | Exp 3 (Houlton) | Manaus |
| `run_manaus_noacc_transient.sh` | Exp 4 (NoACC) | Manaus |
| `run_manaus_acc_transient.sh` | Exp 5 (ACC) | Manaus |
| `run_ha1_fun_transient_only.sh` | Exp 3 | Ha1 |
| `run_ha1_noacc_transient.sh` | Exp 4 | Ha1 |
| `run_ha1_acc_transient.sh` | Exp 5 | Ha1 |
| `run_bon_fun_transient_only.sh` | Exp 3 | Bon |
| `run_bon_noacc_transient.sh` | Exp 4 | Bon |
| `run_bon_acc_transient.sh` | Exp 5 | Bon |

> Note: `nofun_baseline` at Ha1 and Bon is created by the ha1/bon FUN scripts (shares spinup).

---

## `utils/`

| File | Purpose |
|------|---------|
| `verify_BNFMIP_submit_env.sh` | Pre-flight check: paramfiles, surfdata, create_clone |
| `check_bnf_sanity.py` | Sanity-check key NFIX/FFIX values in h0 output |
| `adjust_restart.py` | Fix restart file date mismatches |
| `compare_cases.py` | Compare namelist/env settings between two case dirs |
| `SESSION_NOTES_20260527.md` | Engineering log: bugs fixed + job IDs from May 27 run |

---

## Known issue (documented in SESSION_NOTES_20260527.md)

`./case.submit --batch-args="--dependency=afterok:JID"` hangs for Ha1 and Bon.
**Workaround**: use `./case.submit --prereq JID` instead.  
`resubmit_BNFMIP_v2.sh` Phase 2 still uses `--batch-args` — update to `--prereq` before next full resubmit.
