# BNFMIP ELM-FUN — Rebuild & Spin-up-Fix Log (July 2026 session)

Working branch: `bnfmip-submission`. This documents the diagnosis, fixes, decisions, and
pipeline for regenerating the corrected BNFMIP site deliverable after the original scratch
was lost. Sites: Manaus (PFT4 tropical), Harvard (PFT7 temperate), Bonanza (PFT2 boreal).
Experiments: nofun / fun(Houlton) / noacc(Bytnerowicz) / acc(Bytnerowicz-acclim).
Sections: §5.3 historical 1850–2014, §5.4 fixed CO2/Ndep 2015–2100, §5.5 SSP5-8.5 2015–2100.

## Status at last update
- §5.3 + §5.5 continuous rebuild runs: complete for 10/12 combos (Man/Ha1 **nofun missing**).
- Gallery on corrected data: `notebooks/BNFMIP_table2_gallery_REBUILD.ipynb` (reads `delivery_rebuild/`).
- **Spin-up fix in progress** (see below) — supersedes the runs above once complete.

## 1. Root cause of the pre-industrial "U-shape" pool drift  ✅ confirmed
Carbon/veg pools dropped ~8–25% to a ~1960–1986 minimum then recovered — impossible as a real
forced response (historical CO2/Ndep/climate all rise). Cause, verified from namelists:
- **Every year-751 spin-up ran `use_funp = .false.`** (Bon/Man from CN `restart_opt`; Ha1/nofun
  from `fn_*` CNP-compset restarts — but all with FUNP off).
- **fun/noacc/acc transients run `use_funp = .true.`** → the P cycle starts unequilibrated at
  1850, the ecosystem relaxes downward, then CO2 fertilization recovers it = the U-shape.
- `nofun` transients run `use_funp=.false.` too → **nofun is exempt** (spin-up matches transient).

## 2. Fix: CNP+FUNP re-spin-up  (validated)
Re-spin-up each fun/noacc/acc × site at 1850 forcing with `I1850CNPRDCTCBC` + `use_fun`+`use_funp`,
300 yr from the existing restart, then re-branch the transient. Proof (Bon-fun) **converged**:
GPP/NPP/TOTECOSYSC/veg-N/veg-P flat, **BNF flat at 2.14 kgN/ha/yr**. Regular spin-up from the
751-yr restart is sufficient (C already equilibrated) — **no AD pass needed**.
- **Residual caveat (accepted by PI):** mineral soil `SMINN`/`SMINP` still fill slowly after 300 yr
  (SMINN → ~0.59 kgN/m², +0.36%/yr). C/BNF are equilibrated; mineral pools carry a small residual
  drift. Decision: accept C/BNF equilibrium, re-branch from yr 300, document this residual.

## 3. BNF vs literature  ✅ benchmarked → no tuning
Pre-industrial total BNF (kgN/ha/yr): **Manaus 23** (Cleveland 15–36; Sullivan 5.7 [1.2–14.4]),
**Harvard 12–15** (Cleveland 7–27), **Bonanza 2.17** (DeLuca **1.5–2.0** moss-cyanobacteria).
Bonanza NoFUN = 6.65 (too high). **FUN's Bonanza value is literature-correct**; its symbiotic≈0 +
associative≈2.11 partitioning matches boreal reality. **Decision: do NOT tune `s_fix`.**
The NoFUN↔FUN divergence at Bonanza is real physics (FUN down-regulates cold-limited fixation);
at warm sites FUN≈prescribed so divergence is small — visible once Man/Ha1 nofun are built.

## 4. `do_transient_pfts` — verified constant, switch off for §5.4
All rebuild runs inherited `do_transient_pfts=.true.` (I20TR default) but **every site is 100%
single-PFT, constant over all years** (Bon2/Man4/Ha7 — verified in flanduse input, restart
`pfts1d_itypveg`, and h0 PCT_NAT_PFT 1850 vs 2100). **No PFT ever changed**, so output is identical
to transient-off; §5.3/§5.5 need no re-run for this. §5.4 sets `do_transient_pfts=.false.`
(required to clear the 2015-start init crash; `flanduse_timeseries` kept only to satisfy
`20thC_transient` build-namelist — not read when the switch is off).

## 5. §5.4 config (fixed CO2/Ndep)
`I20TRCNPRDCTCBC` from the §5.3 `r.2015` restart: `DATM_CO2_TSERIES=none`, `CCSM_CO2_PPMV=401.5`
(2015), `stream_year_first/last_ndep=2015`, met transient SSP5-8.5, continuous DATM alignment,
`do_transient_pfts=.false.`. Bonanza §5.4 (current generation) reached 2100 cleanly.

## 6. Packaging fix
`scripts/package_table2.py` (authoritative 54-var VMAP) had `resolve()` pointing at dead run
names. `scripts/rebuild/package_table2_rebuild.py` reuses its `process()` verbatim, repointing to
the rebuild runs → `delivery_rebuild/`. Two bugs fixed vs a naive repackage: (a) time must be
decimal-year (not raw "days since"), (b) strip phantom 1-month zero-flux boundary records at the
section seams (they created spurious dips; present in the delivered set too).

## 7. Completeness gaps (to close)
- **Man-nofun, Ha1-nofun**: never completed (old `--nopointdata` pftdyn crash). Missing §5.3+§5.5.
- **§5.4 for all 8 Man/Ha1**: pending `r.2015` (the re-branched transients save it via `REST_N=5`).

## 8. Pipeline / scripts (in `scripts/rebuild/`)
- `spinup_fanout.sh` — 9 CNP+FUNP spin-ups (fun/noacc/acc × 3 sites) from existing restarts.
- `rebranch.sh` — re-branch 9 transients from spun-up `r.0301` (do_transient_pfts=.false., REST_N=5).
- `spin_then_rebranch.sh` — monitor: waits for all 9 `r.0301`, then auto-launches `rebranch.sh`.
- `package_table2_rebuild.py` — package rebuild runs → `delivery_rebuild/` (54-var VMAP).
- `plot_working_bon.py` — spin-up convergence plot.
- Site met note: **Harvard met dir is `BNFMIP_forcing_from_OCN/BNF_Har/`** (not `BNF_Ha1`);
  Harvard domain staged to `inputdata/domain_BNF-Ha1_1x1.nc` from the makepointdata `domain.nc`.
