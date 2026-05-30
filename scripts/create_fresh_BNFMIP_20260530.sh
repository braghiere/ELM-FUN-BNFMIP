#!/bin/bash
# =============================================================================
# create_fresh_BNFMIP_20260530.sh
#
# Creates ALL BNFMIP protocol experiment cases from scratch with corrected
# parameters:
#   - freelivfix_slope = 6.0e-4_r8   (original value; repo source_mods confirmed)
#   - fpg_p(c) = 1.0                  (FUN-P handles P limitation; all FUN mods)
#   - s_fix = -0.1 (Man, Ha1)        (param files: sfix01, manaus_tuned)
#   - s_fix = -1.0 (Bon FUN exps)    (param file: bon_tuned, updated 2026-05-30)
#
# Experiments × sites (12 total):
#   nofun_baseline       × Man, Ha1, Bon
#   fun_transient_only   × Man, Ha1, Bon
#   noacc_transient      × Man, Ha1, Bon
#   acc_transient        × Man, Ha1, Bon
#
# Executables built (6 unique, shared where source mods are identical):
#   nofun_manaus    → shared with nofun_ha1, nofun_bon
#   fun_manaus      → shared with fun_ha1, fun_bon
#   noacc_manaus    → NOT shared (tropical-fixed vs temperate source mods differ)
#   noacc_ha1       → shared with noacc_bon
#   acc_manaus      → NOT shared
#   acc_ha1         → shared with acc_bon
#
# Submission logic:
#   Man/Bon FUN exps: funsp (immediate, external finidat) → TR
#   Ha1  FUN exps:    AD → ini → FN → funsp → TR
#   nofun_baseline:   AD → ini → FN → TR
#
# Usage (burst compute node, ~4-6h total):
#   srun -A ccsi -p burst -N 1 -n 1 -t 6:00:00 --mem 32G \
#        --exclude=or-condo-c105,or-condo-c67,or-condo-c04 --pty bash
#   mkdir -p /home/braghiere/ELM-FUN-BNFMIP/logs
#   bash /home/braghiere/ELM-FUN-BNFMIP/scripts/create_fresh_BNFMIP_20260530.sh \
#        2>&1 | tee /home/braghiere/ELM-FUN-BNFMIP/logs/create_20260530.log
# =============================================================================
set -euo pipefail

# ─── Safety: must run on compute node ────────────────────────────────────────
if [[ "$(hostname)" == *login* ]]; then
    echo "ERROR: This script must run on a compute node, not $(hostname)"
    echo "  Use: srun -A ccsi -p burst -N 1 -n 1 -t 6:00:00 --mem 32G --pty bash"
    exit 1
fi

source ~/elm_env_cades_gcc12.sh

# =============================================================================
# Configuration
# =============================================================================
DATE=20260530
OLMT=/home/braghiere/BNF_tom/OLMT_BNF
REPO=/home/braghiere/ELM-FUN-BNFMIP
MODEL_ROOT=/home/braghiere/BNF_tom/E3SM_global_silent
CCSM_INPUT="${CCSM_INPUT:-/lustre/or-scratch/cades-ccsi/proj-shared/project_acme/e3sm_inputdata}"
RUNROOT=/lustre/or-scratch/cades-ccsi/scratch/braghiere
CASEROOT=/home/braghiere/BNF_tom/OLMT_BNF/cime_case_dirs
PARAMDIR=/home/braghiere/BNF_tom
RESTART_OPT=/home/braghiere/BNF_tom/restart_opt

# Source mod directories (from git repo — all confirmed correct 2026-05-30)
# freelivfix_slope = 6.0e-4_r8 and fpg_p(c) = 1.0 in all FUN mods
SMODS=${REPO}/source_mods
SHARED_MODS=${SMODS}/_shared_elm_fun_col_es   # clm_driver.F90, clm_initializeMod.F90

# Param files
# NOTE: clm_params_fun3_sfix01_bon_tuned.nc updated 2026-05-30: s_fix = -1.0 for all PFTs
PARAM_MAN=${PARAMDIR}/clm_params_fun3_sfix01_manaus_tuned.nc   # Man all exps: s_fix=-0.1
PARAM_HA1=${PARAMDIR}/clm_params_fun3_sfix01.nc                # Ha1 + Bon nofun: s_fix=-0.1
PARAM_BON=${PARAMDIR}/clm_params_fun3_sfix01_bon_tuned.nc      # Bon FUN exps: s_fix=-1.0

# CLM1PT atmospheric forcing directories
CLM1PT_MAN=/home/braghiere/BNF_tom/inputdata/BNFMIP_forcing_from_OCN/BNF_Man/CLM1PT_data
CLM1PT_HA1=/home/braghiere/BNF_tom/inputdata/BNFMIP_forcing_from_OCN/BNF_Ha1/CLM1PT_data
CLM1PT_BON=/home/braghiere/BNF_tom/inputdata/BNFMIP_forcing_from_OCN/BNF_Bon/CLM1PT_data

# Bon special surface data (gelisol/organic soil for boreal)
GELISOL=${PARAMDIR}/surfdata_bon_gelisol.nc

# =============================================================================
# Prerequisite checks
# =============================================================================
echo ""
echo "=== Checking prerequisites ==="

for f in "${PARAM_MAN}" "${PARAM_HA1}" "${PARAM_BON}" "${GELISOL}" \
          "${SHARED_MODS}/clm_driver.F90" "${SHARED_MODS}/clm_initializeMod.F90"; do
    [[ -f "$f" ]] || { echo "ERROR - MISSING FILE: $f"; exit 1; }
    echo "  OK: $f"
done

for d in "${CLM1PT_MAN}" "${CLM1PT_HA1}" "${CLM1PT_BON}" "${RESTART_OPT}"; do
    [[ -d "$d" ]] || { echo "ERROR - MISSING DIR: $d"; exit 1; }
    echo "  OK: $d"
done

for exp in fun noacc acc; do
    man_rst="${RESTART_OPT}/man_optimized_restart_${exp}_0751-01-01-00000.nc"
    bon_rst="${RESTART_OPT}/bon_optimized_restart_${exp}_0751-01-01-00000.nc"
    [[ -f "${man_rst}" ]] || { echo "ERROR - MISSING: ${man_rst}"; exit 1; }
    [[ -f "${bon_rst}" ]] || { echo "ERROR - MISSING: ${bon_rst}"; exit 1; }
    echo "  OK: Man restart ${exp}"
    echo "  OK: Bon restart ${exp}"
done

# Guard against overwriting in-progress runs with the same DATE
if ls "${CASEROOT}"/*_${DATE}_* 2>/dev/null | head -1 >/dev/null 2>&1; then
    echo ""
    echo "ERROR: Cases with DATE=${DATE} already exist in ${CASEROOT}."
    echo "       Remove them or change DATE before running this script."
    exit 1
fi

echo ""
echo "=== All prerequisites OK ==="

# =============================================================================
# Helper functions
# =============================================================================

# Run OLMT to create cases (no build, no submit).
# Usage: run_olmt CASEIDPREFIX SITE CLM1PT_DIR PARAMFILE [FUN_FLAGS...]
run_olmt() {
    local caseid=$1 site=$2 clm1pt=$3 paramfile=$4
    shift 4
    local fun_flags="$*"
    echo ""
    echo "── OLMT: ${caseid} (${site}) ──"
    cd "${OLMT}"
    # shellcheck disable=SC2086
    python3 site_fullrun.py \
        --site "${site}" --sitegroup BNF --machine cades \
        --caseidprefix "${caseid}" \
        --model_root "${MODEL_ROOT}" --ccsm_input "${CCSM_INPUT}" \
        --runroot "${RUNROOT}" --caseroot "${CASEROOT}" \
        --mpilib openmpi --np 1 --walltime 24 --nofire \
        --clm_paramfile "${paramfile}" \
        --clm1pt_dir "${clm1pt}" \
        --nyears_ad_spinup 200 --nyears_final_spinup 600 \
        --batch_build \
        --no_submit \
        ${fun_flags}
}

# Inject source mods into an AD case SourceMods directory.
# Usage: inject_sourcemods AD_CASE_DIR SMOD_DIR
inject_sourcemods() {
    local ad_case=$1 smod_dir=$2
    mkdir -p "${ad_case}/SourceMods/src.clm"
    cp "${smod_dir}"/*.F90 "${ad_case}/SourceMods/src.clm/"
    cp "${SHARED_MODS}"/*.F90 "${ad_case}/SourceMods/src.clm/"
    echo "  Injected $(ls "${ad_case}/SourceMods/src.clm/"*.F90 | wc -l) F90 files into $(basename "${ad_case}")"
}

# Build the AD case exe; prints EXEROOT on stdout.
# Usage: exeroot=$(build_ad_case AD_CASE_DIR)
build_ad_case() {
    local ad_case=$1
    echo "" >&2
    echo "══ Building: $(basename "${ad_case}") ══" >&2
    cd "${ad_case}"
    ./case.build 2>&1 | tee "${ad_case}/case.build.log" >&2
    local exeroot
    exeroot=$(./xmlquery EXEROOT --value)
    if [[ ! -f "${exeroot}/e3sm.exe" ]]; then
        echo "ERROR: Build FAILED for $(basename "${ad_case}")" >&2
        echo "  Check: ${ad_case}/case.build.log" >&2
        exit 1
    fi
    echo "  Build OK: ${exeroot}/e3sm.exe" >&2
    echo "${exeroot}"
}

# Point a set of cases to a shared EXEROOT (skip their own build).
# First arg: EXEROOT path; remaining args: case dirs to update.
# The first case dir is the AD case and gets BUILD_COMPLETE=TRUE.
set_shared_exe() {
    local primary_exeroot=$1
    shift
    local ad_case=$1   # first dir is always the AD case
    echo "  Sharing exe: ${primary_exeroot}"
    for case_dir in "$@"; do
        if [[ -d "${case_dir}" ]]; then
            cd "${case_dir}"
            ./xmlchange EXEROOT="${primary_exeroot}"
            echo "    Updated EXEROOT: $(basename "${case_dir}")"
        else
            echo "    WARNING: Case dir not found (skipping): ${case_dir}"
        fi
    done
    cd "${ad_case}"
    ./xmlchange BUILD_COMPLETE=TRUE
    echo "    BUILD_COMPLETE=TRUE: $(basename "${ad_case}")"
}

# Append or replace a variable in user_nl_clm.
# Usage: set_nl_var USER_NL_FILE VARNAME VALUE
set_nl_var() {
    local nlfile=$1 varname=$2 value=$3
    if grep -q "^[[:space:]]*${varname}[[:space:]]*=" "${nlfile}"; then
        sed -i "s|^[[:space:]]*${varname}[[:space:]]*=.*|${varname} = ${value}|" "${nlfile}"
    else
        printf "%s = %s\n" "${varname}" "${value}" >> "${nlfile}"
    fi
}

# Submit a PBS/SLURM script; returns the job ID on stdout.
# Usage: jid=$(submit_one LABEL PBS_SCRIPT [SBATCH_DEP_ARG])
submit_one() {
    local label=$1 script=$2 dep=${3:-""}
    local out jid
    out=$(sbatch ${dep} "${script}" 2>&1)
    if ! echo "$out" | grep -q 'Submitted batch job'; then
        echo "ERROR submitting ${label}: ${out}" >&2
        exit 1
    fi
    jid=$(echo "$out" | awk '{print $4}')
    echo "  ${label}: job ${jid}  ${dep:+(${dep})}" >&2
    echo "${jid}"
}

# =============================================================================
# SECTION 1: OLMT case creation (12 experiment groups)
# =============================================================================
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  SECTION 1: OLMT case creation (12 groups)                  ║"
echo "╚══════════════════════════════════════════════════════════════╝"

# nofun_baseline — no FUN/FUNP, standard CNRDCTCBC compset
run_olmt "nofun_baseline_manaus_${DATE}" BNF-Man "${CLM1PT_MAN}" "${PARAM_MAN}"
run_olmt "nofun_baseline_ha1_${DATE}"   BNF-Ha1 "${CLM1PT_HA1}" "${PARAM_HA1}"
run_olmt "nofun_baseline_bon_${DATE}"   BNF-Bon "${CLM1PT_BON}" "${PARAM_HA1}"

# fun_transient_only — FUN+FUNP on, Houlton N-fixation scheme
run_olmt "fun_transient_only_manaus_${DATE}" BNF-Man "${CLM1PT_MAN}" "${PARAM_MAN}" --use_fun --use_funp
run_olmt "fun_transient_only_ha1_${DATE}"   BNF-Ha1 "${CLM1PT_HA1}" "${PARAM_HA1}" --use_fun --use_funp
run_olmt "fun_transient_only_bon_${DATE}"   BNF-Bon "${CLM1PT_BON}" "${PARAM_BON}" --use_fun --use_funp

# noacc_transient — FUN+FUNP on, Bytnerowicz noACC N-fixation scheme
run_olmt "noacc_transient_manaus_${DATE}" BNF-Man "${CLM1PT_MAN}" "${PARAM_MAN}" --use_fun --use_funp
run_olmt "noacc_transient_ha1_${DATE}"   BNF-Ha1 "${CLM1PT_HA1}" "${PARAM_HA1}" --use_fun --use_funp
run_olmt "noacc_transient_bon_${DATE}"   BNF-Bon "${CLM1PT_BON}" "${PARAM_BON}" --use_fun --use_funp

# acc_transient — FUN+FUNP on, Bytnerowicz ACC N-fixation scheme
run_olmt "acc_transient_manaus_${DATE}" BNF-Man "${CLM1PT_MAN}" "${PARAM_MAN}" --use_fun --use_funp
run_olmt "acc_transient_ha1_${DATE}"   BNF-Ha1 "${CLM1PT_HA1}" "${PARAM_HA1}" --use_fun --use_funp
run_olmt "acc_transient_bon_${DATE}"   BNF-Bon "${CLM1PT_BON}" "${PARAM_BON}" --use_fun --use_funp

echo ""
echo "=== SECTION 1 complete: 12 case groups created ==="

# =============================================================================
# SECTION 2: Source mod injection + Build (6 primary executables)
#            + Shared-exe configuration for 6 non-building cases
# =============================================================================
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  SECTION 2: Source mods + Build (6 executables)             ║"
echo "╚══════════════════════════════════════════════════════════════╝"

# --- Case directory variables (all 12 groups × all phases) ---

# nofun_baseline
NF_MAN_AD=${CASEROOT}/nofun_baseline_manaus_${DATE}_BNF-Man_I1850CNRDCTCBC_ad_spinup
NF_MAN_FN=${CASEROOT}/nofun_baseline_manaus_${DATE}_BNF-Man_I1850CNPRDCTCBC
NF_MAN_TR=${CASEROOT}/nofun_baseline_manaus_${DATE}_BNF-Man_I20TRCNPRDCTCBC
NF_HA1_AD=${CASEROOT}/nofun_baseline_ha1_${DATE}_BNF-Ha1_I1850CNRDCTCBC_ad_spinup
NF_HA1_FN=${CASEROOT}/nofun_baseline_ha1_${DATE}_BNF-Ha1_I1850CNPRDCTCBC
NF_HA1_TR=${CASEROOT}/nofun_baseline_ha1_${DATE}_BNF-Ha1_I20TRCNPRDCTCBC
NF_BON_AD=${CASEROOT}/nofun_baseline_bon_${DATE}_BNF-Bon_I1850CNRDCTCBC_ad_spinup
NF_BON_FN=${CASEROOT}/nofun_baseline_bon_${DATE}_BNF-Bon_I1850CNPRDCTCBC
NF_BON_TR=${CASEROOT}/nofun_baseline_bon_${DATE}_BNF-Bon_I20TRCNPRDCTCBC

# fun_transient_only
FUN_MAN_AD=${CASEROOT}/fun_transient_only_manaus_${DATE}_BNF-Man_I1850CNRDCTCBC_ad_spinup
FUN_MAN_FN=${CASEROOT}/fun_transient_only_manaus_${DATE}_BNF-Man_I1850CNPRDCTCBC
FUN_MAN_FUNSP=${CASEROOT}/fun_transient_only_manaus_${DATE}_funsp_BNF-Man_I1850CNPRDCTCBC
FUN_MAN_TR=${CASEROOT}/fun_transient_only_manaus_${DATE}_BNF-Man_I20TRCNPRDCTCBC
FUN_HA1_AD=${CASEROOT}/fun_transient_only_ha1_${DATE}_BNF-Ha1_I1850CNRDCTCBC_ad_spinup
FUN_HA1_FN=${CASEROOT}/fun_transient_only_ha1_${DATE}_BNF-Ha1_I1850CNPRDCTCBC
FUN_HA1_FUNSP=${CASEROOT}/fun_transient_only_ha1_${DATE}_funsp_BNF-Ha1_I1850CNPRDCTCBC
FUN_HA1_TR=${CASEROOT}/fun_transient_only_ha1_${DATE}_BNF-Ha1_I20TRCNPRDCTCBC
FUN_BON_AD=${CASEROOT}/fun_transient_only_bon_${DATE}_BNF-Bon_I1850CNRDCTCBC_ad_spinup
FUN_BON_FN=${CASEROOT}/fun_transient_only_bon_${DATE}_BNF-Bon_I1850CNPRDCTCBC
FUN_BON_FUNSP=${CASEROOT}/fun_transient_only_bon_${DATE}_funsp_BNF-Bon_I1850CNPRDCTCBC
FUN_BON_TR=${CASEROOT}/fun_transient_only_bon_${DATE}_BNF-Bon_I20TRCNPRDCTCBC

# noacc_transient
NOACC_MAN_AD=${CASEROOT}/noacc_transient_manaus_${DATE}_BNF-Man_I1850CNRDCTCBC_ad_spinup
NOACC_MAN_FN=${CASEROOT}/noacc_transient_manaus_${DATE}_BNF-Man_I1850CNPRDCTCBC
NOACC_MAN_FUNSP=${CASEROOT}/noacc_transient_manaus_${DATE}_funsp_BNF-Man_I1850CNPRDCTCBC
NOACC_MAN_TR=${CASEROOT}/noacc_transient_manaus_${DATE}_BNF-Man_I20TRCNPRDCTCBC
NOACC_HA1_AD=${CASEROOT}/noacc_transient_ha1_${DATE}_BNF-Ha1_I1850CNRDCTCBC_ad_spinup
NOACC_HA1_FN=${CASEROOT}/noacc_transient_ha1_${DATE}_BNF-Ha1_I1850CNPRDCTCBC
NOACC_HA1_FUNSP=${CASEROOT}/noacc_transient_ha1_${DATE}_funsp_BNF-Ha1_I1850CNPRDCTCBC
NOACC_HA1_TR=${CASEROOT}/noacc_transient_ha1_${DATE}_BNF-Ha1_I20TRCNPRDCTCBC
NOACC_BON_AD=${CASEROOT}/noacc_transient_bon_${DATE}_BNF-Bon_I1850CNRDCTCBC_ad_spinup
NOACC_BON_FN=${CASEROOT}/noacc_transient_bon_${DATE}_BNF-Bon_I1850CNPRDCTCBC
NOACC_BON_FUNSP=${CASEROOT}/noacc_transient_bon_${DATE}_funsp_BNF-Bon_I1850CNPRDCTCBC
NOACC_BON_TR=${CASEROOT}/noacc_transient_bon_${DATE}_BNF-Bon_I20TRCNPRDCTCBC

# acc_transient
ACC_MAN_AD=${CASEROOT}/acc_transient_manaus_${DATE}_BNF-Man_I1850CNRDCTCBC_ad_spinup
ACC_MAN_FN=${CASEROOT}/acc_transient_manaus_${DATE}_BNF-Man_I1850CNPRDCTCBC
ACC_MAN_FUNSP=${CASEROOT}/acc_transient_manaus_${DATE}_funsp_BNF-Man_I1850CNPRDCTCBC
ACC_MAN_TR=${CASEROOT}/acc_transient_manaus_${DATE}_BNF-Man_I20TRCNPRDCTCBC
ACC_HA1_AD=${CASEROOT}/acc_transient_ha1_${DATE}_BNF-Ha1_I1850CNRDCTCBC_ad_spinup
ACC_HA1_FN=${CASEROOT}/acc_transient_ha1_${DATE}_BNF-Ha1_I1850CNPRDCTCBC
ACC_HA1_FUNSP=${CASEROOT}/acc_transient_ha1_${DATE}_funsp_BNF-Ha1_I1850CNPRDCTCBC
ACC_HA1_TR=${CASEROOT}/acc_transient_ha1_${DATE}_BNF-Ha1_I20TRCNPRDCTCBC
ACC_BON_AD=${CASEROOT}/acc_transient_bon_${DATE}_BNF-Bon_I1850CNRDCTCBC_ad_spinup
ACC_BON_FN=${CASEROOT}/acc_transient_bon_${DATE}_BNF-Bon_I1850CNPRDCTCBC
ACC_BON_FUNSP=${CASEROOT}/acc_transient_bon_${DATE}_funsp_BNF-Bon_I1850CNPRDCTCBC
ACC_BON_TR=${CASEROOT}/acc_transient_bon_${DATE}_BNF-Bon_I20TRCNPRDCTCBC

# --- Build 1: nofun_baseline_manaus (shared with ha1 and bon) ----------------
echo ""
echo "── Build 1/6: nofun_baseline_manaus (control_fixed_funp_nfix) ──"
inject_sourcemods "${NF_MAN_AD}" "${SMODS}/control_fixed_funp_nfix"
NF_MAN_EXE=$(build_ad_case "${NF_MAN_AD}")

# Shared exe: nofun_ha1 and nofun_bon get nofun_man's exe
echo "── Shared-exe setup: nofun_ha1 and nofun_bon ──"
set_shared_exe "${NF_MAN_EXE}" \
    "${NF_HA1_AD}" "${NF_HA1_FN}" "${NF_HA1_TR}"
set_shared_exe "${NF_MAN_EXE}" \
    "${NF_BON_AD}" "${NF_BON_FN}" "${NF_BON_TR}"

# --- Build 2: fun_transient_only_manaus (shared with ha1 and bon) ------------
echo ""
echo "── Build 2/6: fun_transient_only_manaus (fun_fpg1_nfix) ──"
inject_sourcemods "${FUN_MAN_AD}" "${SMODS}/fun_fpg1_nfix"
FUN_MAN_EXE=$(build_ad_case "${FUN_MAN_AD}")

# Shared exe: fun_ha1 and fun_bon
echo "── Shared-exe setup: fun_ha1 and fun_bon ──"
set_shared_exe "${FUN_MAN_EXE}" \
    "${FUN_HA1_AD}" "${FUN_HA1_FN}" "${FUN_HA1_FUNSP}" "${FUN_HA1_TR}"
set_shared_exe "${FUN_MAN_EXE}" \
    "${FUN_BON_AD}" "${FUN_BON_FN}" "${FUN_BON_FUNSP}" "${FUN_BON_TR}"

# Update EXEROOT in Man funsp and TR (they were set to AD bld, same location — confirming)
for d in "${FUN_MAN_FUNSP}" "${FUN_MAN_TR}"; do
    cd "${d}" && ./xmlchange EXEROOT="${FUN_MAN_EXE}"
done

# --- Build 3: noacc_transient_manaus (NOT shared — tropical fixed mods) ------
echo ""
echo "── Build 3/6: noacc_transient_manaus (noACC_fixed_funp_nfix) ──"
inject_sourcemods "${NOACC_MAN_AD}" "${SMODS}/noACC_fixed_funp_nfix"
NOACC_MAN_EXE=$(build_ad_case "${NOACC_MAN_AD}")

# Update EXEROOT in Man funsp and TR (they are already pointing to noacc_man bld)
for d in "${NOACC_MAN_FUNSP}" "${NOACC_MAN_TR}" "${NOACC_MAN_FN}"; do
    cd "${d}" && ./xmlchange EXEROOT="${NOACC_MAN_EXE}"
done

# --- Build 4: noacc_transient_ha1 (shared with bon) -------------------------
echo ""
echo "── Build 4/6: noacc_transient_ha1 (noACC_temperate_funp_nfix) ──"
inject_sourcemods "${NOACC_HA1_AD}" "${SMODS}/noACC_temperate_funp_nfix"
NOACC_HA1_EXE=$(build_ad_case "${NOACC_HA1_AD}")

# Shared exe: noacc_bon
echo "── Shared-exe setup: noacc_bon ──"
set_shared_exe "${NOACC_HA1_EXE}" \
    "${NOACC_BON_AD}" "${NOACC_BON_FN}" "${NOACC_BON_FUNSP}" "${NOACC_BON_TR}"

# Update EXEROOT in Ha1 funsp and TR
for d in "${NOACC_HA1_FUNSP}" "${NOACC_HA1_TR}" "${NOACC_HA1_FN}"; do
    cd "${d}" && ./xmlchange EXEROOT="${NOACC_HA1_EXE}"
done

# --- Build 5: acc_transient_manaus (NOT shared — tropical fixed mods) --------
echo ""
echo "── Build 5/6: acc_transient_manaus (ACC_fixed_funp_nfix) ──"
inject_sourcemods "${ACC_MAN_AD}" "${SMODS}/ACC_fixed_funp_nfix"
ACC_MAN_EXE=$(build_ad_case "${ACC_MAN_AD}")

# Update EXEROOT in Man funsp and TR
for d in "${ACC_MAN_FUNSP}" "${ACC_MAN_TR}" "${ACC_MAN_FN}"; do
    cd "${d}" && ./xmlchange EXEROOT="${ACC_MAN_EXE}"
done

# --- Build 6: acc_transient_ha1 (shared with bon) ----------------------------
echo ""
echo "── Build 6/6: acc_transient_ha1 (ACC_temperate_funp_nfix) ──"
inject_sourcemods "${ACC_HA1_AD}" "${SMODS}/ACC_temperate_funp_nfix"
ACC_HA1_EXE=$(build_ad_case "${ACC_HA1_AD}")

# Shared exe: acc_bon
echo "── Shared-exe setup: acc_bon ──"
set_shared_exe "${ACC_HA1_EXE}" \
    "${ACC_BON_AD}" "${ACC_BON_FN}" "${ACC_BON_FUNSP}" "${ACC_BON_TR}"

# Update EXEROOT in Ha1 funsp and TR
for d in "${ACC_HA1_FUNSP}" "${ACC_HA1_TR}" "${ACC_HA1_FN}"; do
    cd "${d}" && ./xmlchange EXEROOT="${ACC_HA1_EXE}"
done

echo ""
echo "=== SECTION 2 complete: 6 executables built, 6 shared-exe cases configured ==="

# =============================================================================
# SECTION 3: Per-site user_nl_clm customizations
# =============================================================================
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  SECTION 3: Per-site user_nl_clm customizations             ║"
echo "╚══════════════════════════════════════════════════════════════╝"

# --- Manaus FUN experiments: override funsp finidat with optimized restarts --
# (Man funsp starts from pre-existing optimized spinup restarts, not FN yr 751)
echo "── Man FUN funsp: override finidat with optimized restarts ──"
set_nl_var "${FUN_MAN_FUNSP}/user_nl_clm"   "finidat" "'${RESTART_OPT}/man_optimized_restart_fun_0751-01-01-00000.nc'"
set_nl_var "${NOACC_MAN_FUNSP}/user_nl_clm" "finidat" "'${RESTART_OPT}/man_optimized_restart_noacc_0751-01-01-00000.nc'"
set_nl_var "${ACC_MAN_FUNSP}/user_nl_clm"   "finidat" "'${RESTART_OPT}/man_optimized_restart_acc_0751-01-01-00000.nc'"
echo "  Done: Man funsp finidat → restart_opt"

# --- Bonanza Creek FUN experiments: funsp customizations ---------------------
# (Bon funsp: external optimized restart + gelisol surfdata + spinup_mort=1)
echo "── Bon FUN funsp: finidat + gelisol + spinup_mortality_factor=1 ──"
for nl_file in \
    "${FUN_BON_FUNSP}/user_nl_clm" \
    "${NOACC_BON_FUNSP}/user_nl_clm" \
    "${ACC_BON_FUNSP}/user_nl_clm"; do
    set_nl_var "${nl_file}" "fsurdat"                "'${GELISOL}'"
    set_nl_var "${nl_file}" "spinup_mortality_factor" "1"
done
set_nl_var "${FUN_BON_FUNSP}/user_nl_clm"   "finidat" "'${RESTART_OPT}/bon_optimized_restart_fun_0751-01-01-00000.nc'"
set_nl_var "${NOACC_BON_FUNSP}/user_nl_clm" "finidat" "'${RESTART_OPT}/bon_optimized_restart_noacc_0751-01-01-00000.nc'"
set_nl_var "${ACC_BON_FUNSP}/user_nl_clm"   "finidat" "'${RESTART_OPT}/bon_optimized_restart_acc_0751-01-01-00000.nc'"
echo "  Done: Bon funsp finidat + gelisol + spinup_mortality=1"

# --- Bonanza Creek FUN experiments: TR customizations -----------------------
# (Bon TR: gelisol surfdata + disable finidat-surfdata consistency check)
echo "── Bon FUN TR: gelisol surfdata ──"
for nl_file in \
    "${FUN_BON_TR}/user_nl_clm" \
    "${NOACC_BON_TR}/user_nl_clm" \
    "${ACC_BON_TR}/user_nl_clm"; do
    set_nl_var "${nl_file}" "fsurdat"                          "'${GELISOL}'"
    set_nl_var "${nl_file}" "check_finidat_fsurdat_consistency" ".false."
done
echo "  Done: Bon TR gelisol + consistency check disabled"

echo ""
echo "=== SECTION 3 complete: per-site customizations applied ==="

# =============================================================================
# SECTION 4: Submit all experiment chains
# =============================================================================
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  SECTION 4: Submit all chains                               ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  Submission legend:"
echo "  nofun (all sites):        AD → ini → FN → TR"
echo "  FUN exps (Ha1 only):      AD → ini → FN → funsp → TR"
echo "  FUN exps (Man, Bon):      funsp (immediate) → TR"
echo ""

# PBS script directories
PBS_NF_MAN=${OLMT}/scripts/nofun_baseline_manaus_${DATE}
PBS_NF_HA1=${OLMT}/scripts/nofun_baseline_ha1_${DATE}
PBS_NF_BON=${OLMT}/scripts/nofun_baseline_bon_${DATE}
PBS_FUN_MAN=${OLMT}/scripts/fun_transient_only_manaus_${DATE}
PBS_FUN_HA1=${OLMT}/scripts/fun_transient_only_ha1_${DATE}
PBS_FUN_BON=${OLMT}/scripts/fun_transient_only_bon_${DATE}
PBS_NOACC_MAN=${OLMT}/scripts/noacc_transient_manaus_${DATE}
PBS_NOACC_HA1=${OLMT}/scripts/noacc_transient_ha1_${DATE}
PBS_NOACC_BON=${OLMT}/scripts/noacc_transient_bon_${DATE}
PBS_ACC_MAN=${OLMT}/scripts/acc_transient_manaus_${DATE}
PBS_ACC_HA1=${OLMT}/scripts/acc_transient_ha1_${DATE}
PBS_ACC_BON=${OLMT}/scripts/acc_transient_bon_${DATE}

# ── nofun_baseline_manaus: AD → ini → FN → TR ──────────────────────────────
echo "Submitting nofun_baseline_manaus chain..."
J=$(submit_one "nofun_man_AD"  "${PBS_NF_MAN}/ad_spinup_group0.pbs")
J=$(submit_one "nofun_man_ini" "${PBS_NF_MAN}/iniadjust_group0.pbs" "--dependency=afterok:${J}")
J=$(submit_one "nofun_man_FN"  "${PBS_NF_MAN}/fn_spinup_group0.pbs" "--dependency=afterok:${J}")
J=$(submit_one "nofun_man_TR"  "${PBS_NF_MAN}/transient_group0.pbs" "--dependency=afterok:${J}")
NF_MAN_TR_JID="${J}"

# ── nofun_baseline_ha1: AD → ini → FN → TR ─────────────────────────────────
echo "Submitting nofun_baseline_ha1 chain..."
J=$(submit_one "nofun_ha1_AD"  "${PBS_NF_HA1}/ad_spinup_group0.pbs")
J=$(submit_one "nofun_ha1_ini" "${PBS_NF_HA1}/iniadjust_group0.pbs" "--dependency=afterok:${J}")
J=$(submit_one "nofun_ha1_FN"  "${PBS_NF_HA1}/fn_spinup_group0.pbs" "--dependency=afterok:${J}")
J=$(submit_one "nofun_ha1_TR"  "${PBS_NF_HA1}/transient_group0.pbs" "--dependency=afterok:${J}")
NF_HA1_TR_JID="${J}"

# ── nofun_baseline_bon: AD → ini → FN → TR ─────────────────────────────────
echo "Submitting nofun_baseline_bon chain..."
J=$(submit_one "nofun_bon_AD"  "${PBS_NF_BON}/ad_spinup_group0.pbs")
J=$(submit_one "nofun_bon_ini" "${PBS_NF_BON}/iniadjust_group0.pbs" "--dependency=afterok:${J}")
J=$(submit_one "nofun_bon_FN"  "${PBS_NF_BON}/fn_spinup_group0.pbs" "--dependency=afterok:${J}")
J=$(submit_one "nofun_bon_TR"  "${PBS_NF_BON}/transient_group0.pbs" "--dependency=afterok:${J}")
NF_BON_TR_JID="${J}"

# ── fun_transient_only_manaus: funsp (now) → TR ────────────────────────────
# (finidat = restart_opt/man_optimized_restart_fun_0751-01-01-00000.nc)
echo "Submitting fun_transient_only_manaus chain..."
J=$(submit_one "fun_man_funsp" "${PBS_FUN_MAN}/fun_spinup_group0.pbs")
J=$(submit_one "fun_man_TR"    "${PBS_FUN_MAN}/transient_group0.pbs" "--dependency=afterok:${J}")

# ── fun_transient_only_ha1: AD → ini → FN → funsp → TR ────────────────────
echo "Submitting fun_transient_only_ha1 chain..."
J=$(submit_one "fun_ha1_AD"    "${PBS_FUN_HA1}/ad_spinup_group0.pbs")
J=$(submit_one "fun_ha1_ini"   "${PBS_FUN_HA1}/iniadjust_group0.pbs" "--dependency=afterok:${J}")
J=$(submit_one "fun_ha1_FN"    "${PBS_FUN_HA1}/fn_spinup_group0.pbs" "--dependency=afterok:${J}")
J=$(submit_one "fun_ha1_funsp" "${PBS_FUN_HA1}/fun_spinup_group0.pbs" "--dependency=afterok:${J}")
J=$(submit_one "fun_ha1_TR"    "${PBS_FUN_HA1}/transient_group0.pbs" "--dependency=afterok:${J}")

# ── fun_transient_only_bon: funsp (now) → TR ──────────────────────────────
# (finidat = restart_opt/bon_optimized_restart_fun_0751-01-01-00000.nc)
echo "Submitting fun_transient_only_bon chain..."
J=$(submit_one "fun_bon_funsp" "${PBS_FUN_BON}/fun_spinup_group0.pbs")
J=$(submit_one "fun_bon_TR"    "${PBS_FUN_BON}/transient_group0.pbs" "--dependency=afterok:${J}")

# ── noacc_transient_manaus: funsp (now) → TR ──────────────────────────────
echo "Submitting noacc_transient_manaus chain..."
J=$(submit_one "noacc_man_funsp" "${PBS_NOACC_MAN}/fun_spinup_group0.pbs")
J=$(submit_one "noacc_man_TR"    "${PBS_NOACC_MAN}/transient_group0.pbs" "--dependency=afterok:${J}")

# ── noacc_transient_ha1: AD → ini → FN → funsp → TR ──────────────────────
echo "Submitting noacc_transient_ha1 chain..."
J=$(submit_one "noacc_ha1_AD"    "${PBS_NOACC_HA1}/ad_spinup_group0.pbs")
J=$(submit_one "noacc_ha1_ini"   "${PBS_NOACC_HA1}/iniadjust_group0.pbs" "--dependency=afterok:${J}")
J=$(submit_one "noacc_ha1_FN"    "${PBS_NOACC_HA1}/fn_spinup_group0.pbs" "--dependency=afterok:${J}")
J=$(submit_one "noacc_ha1_funsp" "${PBS_NOACC_HA1}/fun_spinup_group0.pbs" "--dependency=afterok:${J}")
J=$(submit_one "noacc_ha1_TR"    "${PBS_NOACC_HA1}/transient_group0.pbs" "--dependency=afterok:${J}")

# ── noacc_transient_bon: funsp (now) → TR ────────────────────────────────
echo "Submitting noacc_transient_bon chain..."
J=$(submit_one "noacc_bon_funsp" "${PBS_NOACC_BON}/fun_spinup_group0.pbs")
J=$(submit_one "noacc_bon_TR"    "${PBS_NOACC_BON}/transient_group0.pbs" "--dependency=afterok:${J}")

# ── acc_transient_manaus: funsp (now) → TR ────────────────────────────────
echo "Submitting acc_transient_manaus chain..."
J=$(submit_one "acc_man_funsp" "${PBS_ACC_MAN}/fun_spinup_group0.pbs")
J=$(submit_one "acc_man_TR"    "${PBS_ACC_MAN}/transient_group0.pbs" "--dependency=afterok:${J}")

# ── acc_transient_ha1: AD → ini → FN → funsp → TR ────────────────────────
echo "Submitting acc_transient_ha1 chain..."
J=$(submit_one "acc_ha1_AD"    "${PBS_ACC_HA1}/ad_spinup_group0.pbs")
J=$(submit_one "acc_ha1_ini"   "${PBS_ACC_HA1}/iniadjust_group0.pbs" "--dependency=afterok:${J}")
J=$(submit_one "acc_ha1_FN"    "${PBS_ACC_HA1}/fn_spinup_group0.pbs" "--dependency=afterok:${J}")
J=$(submit_one "acc_ha1_funsp" "${PBS_ACC_HA1}/fun_spinup_group0.pbs" "--dependency=afterok:${J}")
J=$(submit_one "acc_ha1_TR"    "${PBS_ACC_HA1}/transient_group0.pbs" "--dependency=afterok:${J}")

# ── acc_transient_bon: funsp (now) → TR ──────────────────────────────────
echo "Submitting acc_transient_bon chain..."
J=$(submit_one "acc_bon_funsp" "${PBS_ACC_BON}/fun_spinup_group0.pbs")
J=$(submit_one "acc_bon_TR"    "${PBS_ACC_BON}/transient_group0.pbs" "--dependency=afterok:${J}")

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  ALL CHAINS SUBMITTED                                        ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  Monitor with: squeue -u braghiere --format='%.10i %.8P %.45j %.2t %.10M %R'"
echo ""
echo "  Expected timelines:"
echo "    funsp (200 yr):  ~3-5h  → transients start automatically"
echo "    FN spinup (750yr): ~12-18h → Ha1 FUN transients start after funsp"
echo "    Transient (250yr): ~4-6h"
echo ""
echo "  SANITY CHECK after funsp completes (~5h from now):"
echo "    CASE=fun_transient_only_manaus_${DATE}_funsp_BNF-Man_I1850CNPRDCTCBC"
echo "    F=\$(ls ${RUNROOT}/\${CASE}/run/*.clm2.h0.*.nc | sort | tail -1)"
echo "    python3 -c \""
echo "    import netCDF4 as nc, numpy as np"
echo "    d = nc.Dataset('\$F')"
echo "    for v in ['COST_NFIX','FFIX_TO_SMINN']:"
echo "        x = np.ma.compressed(d[v][:])"
echo "        if len(x): print(f'{v}: {x[0]:.4e} {d[v].units}')"
echo "    \""
echo "  Expected: COST_NFIX ~7.2 gC/gN, FFIX_TO_SMINN ~2.3e-9 gN/m2/s"
echo ""
echo "=== create_fresh_BNFMIP_${DATE}.sh COMPLETE ==="
