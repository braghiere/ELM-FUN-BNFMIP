# Reproducing the ELM-FUN BNFMIP runs

End-to-end, clone → simulations → Table-2 deliverables, on CADES (ORNL).
Anyone with a CADES allocation and an ELM/E3SM build can follow this.

> **Paths.** The scripts were written for one user's tree. Set the variables in
> [Step 0](#step-0-configure-paths) and search-replace them, or run as-is and adjust
> the hard-coded `/home/<user>/...` and scratch paths. All such paths are collected
> below so there are no surprises.

---

## Prerequisites

| Need | Detail |
|------|--------|
| CADES access | `batch` partition; a compute allocation (this work used account `ccsi`) |
| ELM / E3SM | An E3SM checkout with ELM. The FUN scheme lives in [`source_mods/`](source_mods) and is applied on top (Step 1). |
| OLMT | [github.com/dmricciuto/OLMT](https://github.com/dmricciuto/OLMT) — drives case creation (`site_fullrun.py`) |
| Input data | The CADES `e3sm_inputdata` tree (surfdata, DATM forcing, CO₂/Ndep streams) |
| Python | ≥ 3.9 with `xarray numpy netCDF4 matplotlib` (+ `jupyter nbformat` for the notebook) |

## Step 0 — configure paths

```bash
export SRCROOT=/path/to/E3SM            # your ELM/E3SM checkout
export OLMT=/path/to/OLMT               # OLMT clone
export CASEROOT=$HOME/BNFMIP/cases      # where case dirs are created
export RUNROOT=/lustre/or-scratch24/scratch/$USER   # scratch for run dirs (or-scratch24 recommended)
export PARAMDIR=$HOME/BNFMIP/params     # clm_params + CNP parameter files
export INPUTDATA=/lustre/or-scratch/cades-ccsi/proj-shared/project_acme/e3sm_inputdata
export REPO=$HOME/ELM-FUN-BNFMIP        # this repository
```

> **Filesystem note.** `/lustre/or-scratch` was intermittently unstable during this
> work; `/lustre/or-scratch24` is the more reliable scratch. Stage forcing/restarts
> there and set `RUNROOT` accordingly.

## Step 1 — apply the FUN source modifications

The four experiments differ only by which `source_mods/` subdirectory is compiled in:

| Experiment | SourceMods |
|------------|-----------|
| `nofun_baseline` | `control_fixed_funp_nfix/` |
| `fun_transient_only` (Houlton) | `fun_fpg1_nfix/` |
| `noacc_transient` | `noACC_fixed_funp_nfix/` (Manaus) · `noACC_temperate_funp_nfix/` (Harvard, Bonanza) |
| `acc_transient` | `ACC_fixed_funp_nfix/` (Manaus) · `ACC_temperate_funp_nfix/` (Harvard, Bonanza) |

Each set already contains the **scientific corrections** (see [`docs/corrections.md`](docs/corrections.md)):
`fpg_p` P double-limitation, `freelivfix_slope`, and the shared `clm_driver`/`clm_initializeMod`
in `_shared_elm_fun_col_es/`. The `s_fix` cost and per-site tuning live in the parameter
files in `$PARAMDIR` (see [Parameter files](#parameter-files)).

Point each case's `SourceMods/src.clm/` at the appropriate directory (the `per_site`
scripts do this automatically).

## Step 2 — create and spin up the cases

```bash
# One script per site × experiment; creates the OLMT case + AD/FN/FUN spin-up chain.
for s in scripts/per_site/run_manaus_*.sh scripts/per_site/run_ha1_*.sh scripts/per_site/run_bon_*.sh; do
    bash "$s"          # edit SRCROOT/OLMT/CASEROOT/RUNROOT at the top of each first
done
```

Spin-up follows protocol §5.2 (constant 1850 CO₂/Ndep to equilibrium: <1 gC/m²/yr
TOTECOC and <0.5 gN/m²/yr TOTECON drift over 50 yr). Chain: **AD spin-up → FN spin-up
→ (FUN spin-up for the 3 FUN experiments)**. See [`scripts/README.md`](scripts/README.md)
for case naming and the spin-up diagram.

**Pre-flight check** before submitting:
```bash
bash scripts/utils/verify_BNFMIP_submit_env.sh    # paramfiles, surfdata, create_clone present
```

## Step 3 — §5.3 historical + §5.4 fixed-CO₂ (the canonical submission)

```bash
bash scripts/resubmit_BNFMIP_v2.sh --dry-run      # preview
bash scripts/resubmit_BNFMIP_v2.sh                # submit all phases
```

This runs, for all 4 experiments × 3 sites:
- **§5.3** transient 1850–2014 (`I20TRCNPRDCTCBC`, transient CO₂/Ndep)
- **§5.4** 2015–2100 cloned from the 2015-01-01 restart, **CO₂ fixed at 397.7641 ppmv**
  (`CLM_CO2_TYPE=constant`) and **Ndep locked at 2014** (`stream_year_first/last_ndep=2014`).

## Step 4 — §5.5 SSP5-8.5 transient (2015–2100)

Start from each site's 2015-01-01 restart and run 2015–2100 with **transient** SSP5-8.5
CO₂ and Ndep:

```bash
python3 scripts/submit_ssp585_cases.py            # creates/submits the §5.5 cases
```

Key settings (vs §5.4): `CLM_CO2_TYPE=diagnostic`, CO₂ DATM stream field =
`fco2_datm_ssp585_1765-2100_c260519.nc`, transient Ndep.

> **Manaus §5.5 caveat (important).** The dedicated Manaus `ssp585` case builds were
> defective (vegetation failed to initialize). The working recipe is to start from the
> validated §5.4 Manaus case and switch CO₂/Ndep to transient — i.e. §5.4 + transient
> forcing = §5.5. See [`docs/corrections.md`](docs/corrections.md) §5. Harvard/Bonanza
> §5.5 run directly from `submit_ssp585_cases.py`.

## Step 5 — package outputs into deliverables

```bash
# Simple annual-mean set (quick look):
python3 scripts/package_bnfmip_outputs.py --section all

# Full Table-2 set (54 variables, monthly fluxes + pools, C/N/P):
python3 scripts/package_table2.py all
# Manaus §5.5 (packaged from the repurposed §5.4 run dirs):
python3 scripts/package_manaus_sec55.py
```

Output: one NetCDF per site × experiment × section under the delivery directory,
named `{experiment}_{site}_sec{53,54,55}_{years}.nc`.

## Step 6 — verify and visualize

```bash
# sanity-check a raw run (expected Manaus COST_NFIX ~7.2 gC/gN, FFIX ~72 mgN/m²/yr):
python3 scripts/utils/check_bnf_sanity.py <path-to-h0-file>

# figures:
python3 notebooks/bnfmip_figs.py          # writes notebooks/figs/*.png
# or open notebooks/BNFMIP_results.ipynb
```

---

## Parameter files

Stored in `$PARAMDIR` (not in this repo — they are large NetCDF and site-specific):

| Site / experiment | `clm_params` file | CNP file |
|-------------------|-------------------|----------|
| Manaus, all | `clm_params_fun3_sfix01_manaus_tuned.nc` | `CNP_parameters_manaus_oxisol_v2.nc` |
| Harvard, all | `clm_params_fun3_sfix01.nc` | `CNP_parameters.nc` |
| Bonanza, nofun | `clm_params_fun3_sfix01.nc` | `CNP_parameters.nc` |
| Bonanza, FUN exps | `clm_params_fun3_sfix01_bon_tuned.nc` | `CNP_parameters.nc` |

`s_fix` (BNF temperature-cost slope) is set per PFT in these files: warm PFTs `-6.0`,
cold PFTs (1,2,3,8,11,12) `-1.0` (correction #3).

## Key inputdata

```
NDEP     : $INPUTDATA/lnd/clm2/ndepdata/fndep_clm_rcp8.5_simyr1849-2106_1.9x2.5_c100428.nc
CO2 §5.4 : fco2_datm_rcp4.5_1765-2500_c130312.nc   (value at 2014 = 397.7641 ppmv)
CO2 §5.5 : fco2_datm_ssp585_1765-2100_c260519.nc   (transient SSP5-8.5)
```

## Known caveats (carried in the delivered data)

- **Harvard PFT** — run on PFT 6 (broadleaf-deciduous *tropical*) rather than protocol
  PFT 7 (temperate). BNF temperature-response parameters are identical, so the
  intercomparison signal is intact; Harvard absolute C is ~10–25 % low.
- **H2OSOI** delivered as ELM volumetric soil moisture (mm³/mm³), not kgH2O/m².
- **SMINP** magnitude should be sanity-checked against the ELM P-pool definition.

Full details and the reasoning for every fix: [`docs/corrections.md`](docs/corrections.md).
