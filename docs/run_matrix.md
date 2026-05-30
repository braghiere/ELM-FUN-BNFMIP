# Run Matrix — ELM-FUN BNFMIP

**3 sites × 4 experiments × (AD + FN + FUN_FN + 5.3 + 5.4 + 5.5)**

Legend:
- ✓ = this experiment runs this phase
- ✗ = reuses from nofun_baseline
- (shared) = AD/FN are physically the same as nofun_baseline's; only exe differs

---

## Phase Definitions

| Phase | Compset | Years | Notes |
|-------|---------|-------|-------|
| **AD** | `I1850CNRDCTCBC` | 200 yr spinup | Accelerated decomposition; builds experiment-specific exe |
| **FN** | `I1850CNPRDCTCBC` | 600 yr spinup | Regular spinup; FUN OFF for Exp 1, FUN OFF as precursor for Exps 3–5 |
| **FUN_FN** | `I1850CNPRDCTCBC` | ~200 yr | FUN ON spinup; branches from FN yr-751; only for Exps 3–5 |
| **5.3** | `I20TRCNPRDCTCBC` | 1850–2014 | Historical transient; CO₂ and Ndep transient |
| **5.5** | `I20TRCNPRDCTCBC` | 2015–2100 | Future varying; CO₂ and Ndep follow SSP5-8.5/RCP8.5 |
| **5.4** | `IRCP85CNPRDCTCBC` | 2015–2100 | Future fixed; CO₂ and Ndep locked at 2015 levels |

---

## Complete Run Matrix

### MANAUS (BNF-Man) — Tropical

| Exp | Label | AD | FN | FUN_FN | 5.3 | 5.5 | 5.4 | SourceMods |
|-----|-------|----|----|--------|-----|-----|-----|------------|
| 1 | `nofun_baseline_manaus` | ✓ | ✓ (FUN OFF) | ✗ | ✓ | ✓ | ✓ | `control_fixed_funp_nfix` |
| 3 | `fun_transient_only_manaus` | ✓ (exe only) | ✗ | ✓ | ✓ | ✓ | ✓ | `fun_fpg1_nfix` |
| 4 | `noacc_transient_manaus` | ✓ (exe only) | ✗ | ✓ | ✓ | ✓ | ✓ | `noACC_fixed_funp_nfix` |
| 5 | `acc_transient_manaus` | ✓ (exe only) | ✗ | ✓ | ✓ | ✓ | ✓ | `ACC_fixed_funp_nfix` |

**Manaus total SLURM jobs: 19**
- Exp 1: AD + iniadjust + FN + 5.3 + 5.4 + 5.5 = 6
- Exps 3/4/5: (FUN_FN + 5.3 + 5.4 + 5.5) × 3 = 12
- 1 shared exe build per FUN exp = exe builds only (no extra jobs)

### HARVARD FOREST (BNF-Ha1) — Temperate

| Exp | Label | AD | FN | FUN_FN | 5.3 | 5.5 | 5.4 | SourceMods |
|-----|-------|----|----|--------|-----|-----|-----|------------|
| 1 | `nofun_baseline_ha1` | ✓ | ✓ (FUN OFF) | ✗ | ✓ | ✓ | ✓ | `control_fixed_funp_nfix` |
| 3 | `fun_transient_only_ha1` | ✓ (exe only) | ✗ | ✓ | ✓ | ✓ | ✓ | `fun_fpg1_nfix` |
| 4 | `noacc_transient_ha1` | ✓ (exe only) | ✗ | ✓ | ✓ | ✓ | ✓ | `noACC_temperate_funp_nfix` |
| 5 | `acc_transient_ha1` | ✓ (exe only) | ✗ | ✓ | ✓ | ✓ | ✓ | `ACC_temperate_funp_nfix` |

**Ha1 total SLURM jobs: 19**

### BONANZA CREEK (BNF-Bon) — Boreal

| Exp | Label | AD | FN | FUN_FN | 5.3 | 5.5 | 5.4 | SourceMods |
|-----|-------|----|----|--------|-----|-----|-----|------------|
| 1 | `nofun_baseline_bon` | ✓ | ✓ (FUN OFF) | ✗ | ✓ | ✓ | ✓ | `control_fixed_funp_nfix` |
| 3 | `fun_transient_only_bon` | ✓ (exe only) | ✗ | ✓ | ✓ | ✓ | ✓ | `fun_fpg1_nfix` |
| 4 | `noacc_transient_bon` | ✓ (exe only) | ✗ | ✓ | ✓ | ✓ | ✓ | `noACC_temperate_funp_nfix` |
| 5 | `acc_transient_bon` | ✓ (exe only) | ✗ | ✓ | ✓ | ✓ | ✓ | `ACC_temperate_funp_nfix` |

**Bon total SLURM jobs: 19**

---

## Grand Total

| Category | Count |
|----------|-------|
| Sites | 3 |
| Experiments per site | 4 |
| Phases per experiment | 6 (AD, FN, FUN_FN, 5.3, 5.4, 5.5) |
| **Unique SLURM jobs** | **~57** (19 × 3 sites) |
| **Unique model integrations** | **45** (discounting shared exe-only AD builds) |

### Summary by phase
| Phase | Jobs | Notes |
|-------|------|-------|
| AD spinup | 12 | 4 exps × 3 sites; Exps 3/4/5 build exe only, don't run |
| iniadjust | 3 | Exp 1 only × 3 sites |
| FN spinup (FUN OFF) | 3 | Exp 1 only × 3 sites |
| FUN spinup (FUN ON) | 9 | Exps 3/4/5 × 3 sites |
| Historical 5.3 | 12 | 4 exps × 3 sites |
| Future 5.5 | 12 | 4 exps × 3 sites |
| Future 5.4 | 12 | 4 exps × 3 sites |

---

## Case Naming Convention

```
<experiment>_<site_tag>_<YYYYMMDD>_<SITE>_<COMPSET>
```

Examples:
- `nofun_baseline_manaus_20260529_BNF-Man_I1850CNRDCTCBC_ad_spinup`
- `acc_transient_manaus_20260529_BNF-Man_I20TRCNPRDCTCBC`
- `acc_transient_manaus_20260529_BNF-Man_IRCP85CNPRDCTCBC`

---

## Dependencies (Slurm DAG)

```
[nofun AD] → [iniadjust] → [nofun FN] ─────────────────────────┐
                                │                                │
                                ├─ [nofun 5.3] → [nofun 5.5]   │
                                │         └─────→ [nofun 5.4]  │
                                │                                │
                                └─────────── (yr-751 restart) ──┤
                                             ↓                  ↓
                              [FUN_FN (fun/noacc/acc)]         (after 2015 restart available)
                                             ↓
                              [5.3 (fun/noacc/acc)] → [5.5]
                                         └──────────→ [5.4]
```
