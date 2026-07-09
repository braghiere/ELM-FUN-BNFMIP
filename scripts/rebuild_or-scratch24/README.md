# or-scratch24 rebuild scripts (2026-07-08/09)

Exact scripts used to rebuild the site runs on `/lustre/or-scratch24` after `/lustre/or-scratch`
went permanently offline. See `../../docs/rebuild_or-scratch24.md` for the method.

- `rerun_ha1.sh` / `rerun_bon.sh` — re-run the 4 AD spin-ups per site with corrected surfdata
  (Harvard PFT7; Bonanza gelisol soil/P).
- `proof_bonfun_sec53.sh` — single-combo proof that a transient branches correctly from a year-751 restart.
- `shortcut_all.sh` — restart shortcut: 6 FUN combos, one continuous 1850–2100 SSP5-8.5 transient each
  (§5.3 + §5.5 sliced from it → continuous at 2015).
- `fn_autochain.sh` — idempotent AD→FN(750yr)→transient autochainer for the full from-scratch path.
- `finish_all.sh` — launches the remaining combos: transients where FN is done, FN→transient
  SLURM-dependency chains where it isn't.
- `monitor_finish.sh` — validates the CO2 fix, tracks transients to 2100, runs the 2015 continuity check.

Paths are absolute (CADES `/home/braghiere/BNF_tom`); adapt for another account.
