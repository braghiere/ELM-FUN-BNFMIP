# Namelist Templates README

These are reference templates for ELM-FUN `user_nl_clm` and `user_nl_datm`
namelist fragments. They are **not** used directly by OLMT — OLMT generates
its own namelists. Use these as reference when manually creating or patching
cases.

Placeholders in `<angle brackets>` must be substituted before use.

---

## Templates

| File | Used for |
|------|---------|
| `user_nl_clm.spinup_nofun.template` | FN spinup, Exp 1 (FUN OFF) |
| `user_nl_clm.spinup_fun.template` | FUN spinup, Exps 3–5 (FUN ON) |
| `user_nl_clm.transient_nofun.template` | I20TR/IRCP85 transient, Exp 1 |
| `user_nl_clm.transient_fun.template` | I20TR transient, Exps 3–5 (phases 5.3 + 5.5) |
| `user_nl_clm.section54_fixed.template` | IRCP85 fixed CO₂+Ndep, Exps 1–5 (phase 5.4) |
| `user_nl_datm.clm1pt.template` | DATM CLM1PT forcing with CO₂ stream |
