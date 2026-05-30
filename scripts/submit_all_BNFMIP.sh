#!/bin/bash
# submit_all_BNFMIP_experiments.sh
#
# Single launcher for ALL BNFMIP temperature-response experiments:
#   3 sites × 4 experiments (Exps 1, 3, 4, 5) per Bytnerowicz et al.
#
# EXPERIMENTS (Exp 2 excluded — fun_fpg1_baseline full pipeline not run):
#   Exp 1: nofun_baseline       — control_fixed_funp_nfix (FUN/FUNP OFF)
#                                 Full pipeline: AD(200yr)→iniadjust→FN(600yr)→TR
#   Exp 3: fun_transient_only   — fun_fpg1_nfix (FUN+FUNP ON, TR only from Exp 1 yr-751)
#   Exp 4: noacc_transient      — Bytnerowicz noACC Nfix (biome-specific T params, TR only)
#   Exp 5: acc_transient        — Bytnerowicz ACC  Nfix (biome-specific T params, TR only)
#
# SITES & BIOME-SPECIFIC SOURCEMODS:
#   Manaus (BNF-Man):           tropical  → noACC_fixed_funp_nfix, ACC_fixed_funp_nfix
#                                 Tmin=7.04°C, Topt=33.22°C, Tmax=45.35°C
#   Harvard Forest (BNF-Ha1):   temperate → noACC_temperate_funp_nfix, ACC_temperate_funp_nfix
#                                 Tmin=-2.04°C, Topt=32.10°C, Tmax=43.98°C
#   Bonanza Creek (BNF-Bon):    boreal    → noACC_temperate_funp_nfix, ACC_temperate_funp_nfix
#                                 Tmin=-2.04°C, Topt=32.10°C, Tmax=43.98°C
#
# SOIL ORDERS (P-cycle parameterisation):
#   Manaus:   Oxisols  → SOIL_ORDER=4; custom CNP_parameters_manaus_oxisol_v2.nc injected
#   Ha1:      Inceptisols → SOIL_ORDER=5 (corrected from global Alfisol mask, Typic Dystrudepts)
#   Bon:      Inceptisols → SOIL_ORDER=5 (appropriate for boreal mineral soil, Typic Cryepts)
#
# TIMELINE:
#   NOW (~2.5hr on this compute node):
#     Exp 1 nofun_baseline built & submitted for each site (Manaus → Ha1 → Bon)
#     One builder job per site queued (waits for that site's FN spinup to finish)
#
#   AFTER each site's Exp 1 FN spinup completes (~2-3 days, running in PARALLEL):
#     Each site's builder job wakes up and runs:
#       Exp 3 (fun_transient_only), Exp 4 (noacc), Exp 5 (acc)  [~3 x 45min builds]
#
# USAGE:
#   srun -A ccsi -p burst -N 1 -n 1 -t 4:00:00 --mem 32G \
#        --exclude=or-condo-c105,or-condo-c67,or-condo-c04 --pty bash
#   cd /home/braghiere/BNF_tom/OLMT_BNF
#   bash submit_all_BNFMIP_experiments.sh
#
# To resubmit ONLY Exps 3–5 (after nofun yr-751 exists), using the same run_* scripts:
#   bash resubmit_BNFMIP_exps345.sh
# (optional: export NOFUN_MANAUS / NOFUN_HA1 / NOFUN_BON to pin caseids)

set -e

# ── Safety: abort if on a login node ──
if [[ "$(hostname)" == *login* ]]; then
    echo "ERROR: This script must run on a compute node, not $(hostname)!"
    exit 1
fi

source ~/elm_env_cades_gcc12.sh

# Local PTCLM CSVs (BNF_sitedata.txt, etc.) when /nfs/.../PTCLM is unavailable or stale.
export PTCLM_DIR=/home/braghiere/BNF_tom/OLMT_BNF/PTCLM

# ══════════════════════════════════════════════════════════════════════
# Shared paths
# ══════════════════════════════════════════════════════════════════════
OLMT=/home/braghiere/BNF_tom/OLMT_BNF
MODEL_ROOT=/home/braghiere/BNF_tom/E3SM_global_silent
# E3SM DIN_LOC_ROOT — must exist (runcase checks). On CADES burst/condo nodes, /nfs/data/ccsi/...
# is often missing; default is the lustre project_acme mirror (same tree as DIN_LOC_ROOT on many CADES docs).
# Override if you use NFS from a host where it is mounted:
#   export CCSM_INPUT=/nfs/data/ccsi/proj-shared/E3SM/inputdata
CCSM_INPUT="${CCSM_INPUT:-/lustre/or-scratch/cades-ccsi/proj-shared/project_acme/e3sm_inputdata}"
if ! timeout 25 bash -c "[[ -d \"\$1\" ]]" _ "${CCSM_INPUT}"; then
    echo "ERROR: Input data root not found or unreachable within 25s: ${CCSM_INPUT}" >&2
    echo "  Run on a host where project NFS is mounted, or: export CCSM_INPUT=/path/to/E3SM/inputdata" >&2
    exit 1
fi
RUNROOT=/lustre/or-scratch/cades-ccsi/scratch/braghiere
CASEROOT=/home/braghiere/BNF_tom/OLMT_BNF/cime_case_dirs
TODAY=$(date +%Y%m%d)

mkdir -p ${OLMT}/logs

# ══════════════════════════════════════════════════════════════════════
# Helpers
# ══════════════════════════════════════════════════════════════════════

submit_one() {
    local label=$1 script=$2 dep=$3
    local out rc jid
    out=$(sbatch ${dep} "$script" 2>&1)
    rc=$?
    if [ $rc -ne 0 ] || ! echo "$out" | grep -q 'Submitted batch job'; then
        echo "ERROR: Failed to submit ${label}: $out" >&2
        exit 1
    fi
    jid=$(echo "$out" | awk '{print $4}')
    echo "  ${label}: job ${jid}  ${dep:-"(no dependency)"}" >&2
    echo $jid
}

# Inject fsoilordercon into FN and TR user_nl_clm (Manaus oxisol override)
inject_fsoilordercon() {
    local nl="${1}/user_nl_clm"
    local soilfile="${2}"
    if grep -q 'fsoilordercon' "${nl}"; then
        sed -i "s|fsoilordercon.*|fsoilordercon = '${soilfile}'|" "${nl}"
        echo "  $(basename $1): fsoilordercon replaced"
    else
        echo " fsoilordercon = '${soilfile}'" >> "${nl}"
        echo "  $(basename $1): fsoilordercon appended"
    fi
}

# ══════════════════════════════════════════════════════════════════════
# setup_full_experiment
#
# Args:
#   1  CASEID            — e.g. nofun_baseline_manaus_20260324
#   2  SOURCEMODS        — full path to SourceMods dir
#   3  FUN_ON            — "yes" or "no" (FUN/FUNP switch for FN+TR)
#   4  LOGNAME           — label for build log
#   5  SITE              — OLMT site code (BNF-Man, BNF-Ha1, BNF-Bon)
#   6  CLM_PARAMFILE     — full path to CLM parameter netCDF
#   7  CLM1PT_DIR        — full path to CLM1PT forcing data
#   8  MOD_PARM_P_ARG    — "--mod_parm_file_P /path/to/CNP.nc" or "" (Manaus)
#   9  SOILORDER_FILE    — path to fsoilordercon override nc (Manaus), or "" (others)
#
# Sets global RESULT_FN_JID to the FN spinup Slurm job ID.
# ══════════════════════════════════════════════════════════════════════
RESULT_FN_JID=""

setup_full_experiment() {
    local CASEID=$1
    local SOURCEMODS=$2
    local FUN_ON=$3
    local LOGNAME=$4
    local SITE=$5
    local CLM_PARAMFILE=$6
    local CLM1PT_DIR=$7
    local MOD_PARM_P_ARG=$8   # "--mod_parm_file_P /path" or ""
    local SOILORDER_FILE=$9   # path for Manaus fsoilordercon injection, or ""

    local AD_CASE=${CASEROOT}/${CASEID}_${SITE}_I1850CNRDCTCBC_ad_spinup
    local FN_CASE=${CASEROOT}/${CASEID}_${SITE}_I1850CNPRDCTCBC
    local TR_CASE=${CASEROOT}/${CASEID}_${SITE}_I20TRCNPRDCTCBC
    local FN_RUNDIR=${RUNROOT}/${CASEID}_${SITE}_I1850CNPRDCTCBC
    local PBSDIR=${OLMT}/scripts/${CASEID}
    local EXEROOT=${RUNROOT}/${CASEID}_${SITE}_I1850CNRDCTCBC_ad_spinup/bld

    echo ""
    echo "══════════════════════════════════════════════════════════════════"
    echo "=== Setting up: ${CASEID} (${SITE}) ==="
    echo "    SourceMods: $(basename ${SOURCEMODS})"
    echo "    FUN/FUNP:   ${FUN_ON}"
    echo "══════════════════════════════════════════════════════════════════"

    # ── Cleanup ──
    echo "--- Cleanup ---"
    local sfx d r
    for sfx in _I1850CNRDCTCBC_ad_spinup _I1850CNRDCTCBC _I1850CNPRDCTCBC _I20TRCNPRDCTCBC; do
        d=${CASEROOT}/${CASEID}_${SITE}${sfx}
        [ -d "$d" ] && rm -rf "$d" && echo "  Removed $d"
        r=${RUNROOT}/${CASEID}_${SITE}${sfx}
        [ -d "$r" ] && rm -rf "$r" && echo "  Removed $r"
    done

    # ── Step 1: OLMT creates cases ──
    echo ""
    echo "--- Step 1: OLMT creates cases ---"
    cd ${OLMT}
    python3 site_fullrun.py \
        --site ${SITE} --sitegroup BNF --machine cades \
        --caseidprefix ${CASEID} \
        --model_root ${MODEL_ROOT} --ccsm_input ${CCSM_INPUT} \
        --runroot ${RUNROOT} --caseroot ${CASEROOT} \
        --mpilib openmpi --np 1 --walltime 24 --nofire \
        --clm_paramfile ${CLM_PARAMFILE} \
        ${MOD_PARM_P_ARG} \
        --clm1pt_dir ${CLM1PT_DIR} \
        --nyears_ad_spinup 200 --nyears_final_spinup 600 \
        --batch_build \
        --no_submit

    # ── Step 2: SourceMods + build exe ──
    echo ""
    echo "--- Step 2: Build exe (${LOGNAME}) ---"
    sed -i 's/hist_nhtfrq = .*/hist_nhtfrq = -438000, -438000/' ${AD_CASE}/user_nl_clm
    mkdir -p ${AD_CASE}/SourceMods/src.clm
    cp ${SOURCEMODS}/*.F90 ${AD_CASE}/SourceMods/src.clm/
    # col_es SOIL10 wiring (must NOT live in E3SM_global_silent; overlays base checkout)
    if [[ -d ${CASEROOT}/source_codes/_shared_elm_fun_col_es ]]; then
      cp ${CASEROOT}/source_codes/_shared_elm_fun_col_es/*.F90 ${AD_CASE}/SourceMods/src.clm/
    fi
    echo "  Copied $(ls ${AD_CASE}/SourceMods/src.clm/*.F90 | wc -l) SourceMod files"
    ( cd ${AD_CASE} && ./case.build 2>&1 | tee build_${LOGNAME}.log )
    if [ ! -f "${EXEROOT}/e3sm.exe" ]; then
        echo "ERROR: Build FAILED. Check ${AD_CASE}/build_${LOGNAME}.log" >&2
        exit 1
    fi
    echo "  exe: ${EXEROOT}/e3sm.exe"

    # ── Step 3: Propagate BUILD_COMPLETE to FN + TR ──
    echo ""
    echo "--- Step 3: Propagate BUILD_COMPLETE to FN + TR ---"
    local casedir
    for casedir in ${FN_CASE} ${TR_CASE}; do
        ( cd "$casedir" && ./xmlchange BUILD_COMPLETE=TRUE && ./xmlchange EXEROOT=${EXEROOT} )
        echo "  $(basename $casedir): BUILD_COMPLETE=TRUE, EXEROOT set"
    done

    # ── Step 3b: Inject fsoilordercon (Manaus oxisol only) ──
    if [[ -n "${SOILORDER_FILE}" ]]; then
        echo ""
        echo "--- Step 3b: Inject fsoilordercon (${SITE}) ---"
        inject_fsoilordercon ${FN_CASE} "${SOILORDER_FILE}"
        inject_fsoilordercon ${TR_CASE} "${SOILORDER_FILE}"
    fi

    # ── Step 4: Configure FN spinup ──
    echo ""
    echo "--- Step 4: Configure FN spinup (FUN_ON=${FUN_ON}) ---"
    sed -i 's/hist_nhtfrq = .*/hist_nhtfrq = -438000, -438000/' ${FN_CASE}/user_nl_clm
    if [[ "${FUN_ON}" == "yes" ]]; then
        sed -i 's/use_fun = .false./use_fun = .true./'   ${FN_CASE}/user_nl_clm
        sed -i 's/use_funp = .false./use_funp = .true./' ${FN_CASE}/user_nl_clm
        grep -q 'use_fun'  ${FN_CASE}/user_nl_clm || echo 'use_fun  = .true.' >> ${FN_CASE}/user_nl_clm
        grep -q 'use_funp' ${FN_CASE}/user_nl_clm || echo 'use_funp = .true.' >> ${FN_CASE}/user_nl_clm
        echo "  fn_spinup: FUN+FUNP ON"
    else
        grep -q 'use_fun = .true.' ${FN_CASE}/user_nl_clm && {
            echo "ERROR: FUN was unexpectedly enabled in no-FUN fn_spinup" >&2; exit 1
        }
        echo "  fn_spinup: FUN/FUNP OFF (default)"
    fi
    ( cd ${FN_CASE} && ./preview_namelists 2>&1 | tail -3 )

    # ── Step 5: Configure transient ──
    echo ""
    echo "--- Step 5: Configure transient (FUN_ON=${FUN_ON}) ---"
    local FN_RESTART=${FN_RUNDIR}/run/${CASEID}_${SITE}_I1850CNPRDCTCBC.clm2.r.0751-01-01-00000.nc
    sed -i "s|finidat = .*|finidat = '${FN_RESTART}'|" ${TR_CASE}/user_nl_clm
    ( cd ${TR_CASE} && ./xmlchange RUN_REFDATE=0751-01-01 )
    if [[ "${FUN_ON}" == "yes" ]]; then
        sed -i 's/use_fun = .false./use_fun = .true./'   ${TR_CASE}/user_nl_clm
        sed -i 's/use_funp = .false./use_funp = .true./' ${TR_CASE}/user_nl_clm
        grep -q 'use_fun'  ${TR_CASE}/user_nl_clm || echo 'use_fun  = .true.' >> ${TR_CASE}/user_nl_clm
        grep -q 'use_funp' ${TR_CASE}/user_nl_clm || echo 'use_funp = .true.' >> ${TR_CASE}/user_nl_clm
        echo "  transient: FUN+FUNP ON"
    else
        echo "  transient: FUN/FUNP OFF"
    fi
    ( cd ${TR_CASE} && ./preview_namelists 2>&1 | tail -3 )

    # ── Step 6: Patch PBS scripts (exclude broken nodes) ──
    echo ""
    echo "--- Step 6: Patch PBS scripts ---"
    if [ -d "${PBSDIR}" ]; then
        local f
        for f in ${PBSDIR}/*.pbs; do
            grep -q "exclude" "$f" || \
                sed -i '/#SBATCH  --nodes=1/a #SBATCH  --exclude=or-condo-c105,or-condo-c67,or-condo-c04' "$f"
        done
        echo "  Patched $(ls ${PBSDIR}/*.pbs | wc -l) PBS scripts"
    else
        echo "  WARNING: PBS dir not found: ${PBSDIR}"
    fi

    # ── Step 7: Submit pipeline ──
    echo ""
    echo "--- Step 7: Submit pipeline ---"
    cd ${OLMT}
    local JID_AD JID_IA JID_FN JID_TR
    JID_AD=$(submit_one "ad_spinup" ${PBSDIR}/ad_spinup_group0.pbs  "")
    JID_IA=$(submit_one "iniadjust" ${PBSDIR}/iniadjust_group0.pbs  "--dependency=afterok:${JID_AD}")
    JID_FN=$(submit_one "fn_spinup" ${PBSDIR}/fn_spinup_group0.pbs  "--dependency=afterok:${JID_IA}")
    JID_TR=$(submit_one "transient" ${PBSDIR}/transient_group0.pbs  "--dependency=afterok:${JID_FN}")

    RESULT_FN_JID=${JID_FN}
    echo "  ${CASEID}: AD=${JID_AD} IA=${JID_IA} FN=${JID_FN} TR=${JID_TR}"
}

# ══════════════════════════════════════════════════════════════════════
# write_and_submit_builder
#
# Writes and submits the Exps 3/4/5 builder job for one site.
#
# Args:
#   1  SITE_TAG        — short label for filenames (manaus, ha1, bon)
#   2  SITE            — OLMT site code (BNF-Man, BNF-Ha1, BNF-Bon)
#   3  NOFUN_CASEID    — Exp 1 CASEID (to locate yr-751 restart)
#   4  EXP1_FN_JID     — Slurm job ID of Exp 1 FN spinup
#   5  EXP3_SCRIPT     — path to run_*_fun_transient_only.sh
#   6  EXP4_SCRIPT     — path to run_*_noacc_transient.sh
#   7  EXP5_SCRIPT     — path to run_*_acc_transient.sh
#
# Sets global BUILDER_JID.
# ══════════════════════════════════════════════════════════════════════
BUILDER_JID=""

write_and_submit_builder() {
    local SITE_TAG=$1
    local SITE=$2
    local NOFUN_CASEID=$3
    local EXP1_FN_JID=$4
    local EXP3_SCRIPT=$5
    local EXP4_SCRIPT=$6
    local EXP5_SCRIPT=$7

    local BSCRIPT=${OLMT}/logs/${SITE_TAG}_exps345_builder_${TODAY}.sh

    cat > "${BSCRIPT}" << BUILDEREOF
#!/bin/bash
#SBATCH --job-name=${SITE_TAG}_exps345
#SBATCH --account=ccsi
#SBATCH --partition=burst
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=04:00:00
#SBATCH --mem=32G
#SBATCH --exclude=or-condo-c105,or-condo-c67,or-condo-c04
#SBATCH --output=${OLMT}/logs/${SITE_TAG}_exps345_builder_%j.out
#SBATCH --error=${OLMT}/logs/${SITE_TAG}_exps345_builder_%j.err
#
# Builder: builds and submits Exps 3, 4, 5 for ${SITE}.
# Activated when Exp 1 (${NOFUN_CASEID}) FN spinup writes yr-751 restart.
set -e

source ~/elm_env_cades_gcc12.sh

OLMT=${OLMT}
NOFUN_CASEID=${NOFUN_CASEID}
SITE=${SITE}

echo "════════════════════════════════════════════════════════"
echo "=== ${SITE_TAG} Exps 3/4/5 builder started: \$(date) ==="
echo "    CASEID: \${NOFUN_CASEID}"
echo "════════════════════════════════════════════════════════"

RESTART=\${RUNROOT:-${RUNROOT}}/\${NOFUN_CASEID}_\${SITE}_I1850CNPRDCTCBC/run/\${NOFUN_CASEID}_\${SITE}_I1850CNPRDCTCBC.clm2.r.0751-01-01-00000.nc
if [ ! -f "\${RESTART}" ]; then
    echo "ERROR: yr-751 restart not found: \${RESTART}"
    exit 1
fi
echo "Found yr-751 restart: \$(basename \${RESTART})"

cd \${OLMT}

echo ""; echo "=== Exp 3: fun_transient_only (${SITE_TAG}) ==="
bash ${EXP3_SCRIPT} "\${NOFUN_CASEID}"

echo ""; echo "=== Exp 4: noacc_transient (${SITE_TAG}) ==="
bash ${EXP4_SCRIPT} "\${NOFUN_CASEID}"

echo ""; echo "=== Exp 5: acc_transient (${SITE_TAG}) ==="
bash ${EXP5_SCRIPT} "\${NOFUN_CASEID}"

echo ""
echo "════════════════════════════════════════════════════════"
echo "=== ${SITE_TAG} Exps 3/4/5 builder finished: \$(date) ==="
echo "════════════════════════════════════════════════════════"
BUILDEREOF

    chmod +x "${BSCRIPT}"
    echo "  Builder script: ${BSCRIPT}"

    local BOUT
    BOUT=$(sbatch --dependency=afterok:${EXP1_FN_JID} "${BSCRIPT}" 2>&1)
    if ! echo "${BOUT}" | grep -q 'Submitted batch job'; then
        echo "ERROR: Failed to submit ${SITE_TAG} builder: ${BOUT}" >&2
        exit 1
    fi
    BUILDER_JID=$(echo "${BOUT}" | awk '{print $4}')
    echo "  Builder job: ${BUILDER_JID}  (depends on Exp 1 FN ${EXP1_FN_JID})"
}

# ══════════════════════════════════════════════════════════════════════
# ███  MANAUS  (BNF-Man)  — tropical
# ══════════════════════════════════════════════════════════════════════
echo ""
echo "████████████████████████████████████████████████████████████████████"
echo "███  SITE 1/3: MANAUS (BNF-Man) — tropical                       ███"
echo "████████████████████████████████████████████████████████████████████"

MANAUS_CASEID=nofun_baseline_manaus_${TODAY}

setup_full_experiment \
    "${MANAUS_CASEID}" \
    "${CASEROOT}/source_codes/control_fixed_funp_nfix" \
    "no" \
    "nofun_manaus" \
    "BNF-Man" \
    "/home/braghiere/BNF_tom/clm_params_fun3_sfix01_manaus_tuned.nc" \
    "/home/braghiere/BNF_tom/inputdata/BNFMIP_forcing_from_OCN/BNF_Man/CLM1PT_data" \
    "" \
    "/home/braghiere/BNF_tom/CNP_parameters_manaus_oxisol_v2.nc"

MANAUS_FN_JID=${RESULT_FN_JID}
echo ">>> Manaus Exp 1 FN job: ${MANAUS_FN_JID}"

write_and_submit_builder \
    "manaus" "BNF-Man" "${MANAUS_CASEID}" "${MANAUS_FN_JID}" \
    "${OLMT}/run_manaus_fun_transient_only.sh" \
    "${OLMT}/run_manaus_noacc_transient.sh" \
    "${OLMT}/run_manaus_acc_transient.sh"

MANAUS_BUILDER_JID=${BUILDER_JID}

# ══════════════════════════════════════════════════════════════════════
# ███  HARVARD FOREST  (BNF-Ha1)  — temperate
# ══════════════════════════════════════════════════════════════════════
echo ""
echo "████████████████████████████████████████████████████████████████████"
echo "███  SITE 2/3: HARVARD FOREST (BNF-Ha1) — temperate              ███"
echo "█   Soil: Inceptisols (Typic Dystrudepts, SOIL_ORDER=5, corrected) █"
echo "████████████████████████████████████████████████████████████████████"

HA1_CASEID=nofun_baseline_ha1_${TODAY}

setup_full_experiment \
    "${HA1_CASEID}" \
    "${CASEROOT}/source_codes/control_fixed_funp_nfix" \
    "no" \
    "nofun_ha1" \
    "BNF-Ha1" \
    "/home/braghiere/BNF_tom/clm_params_fun3_sfix01.nc" \
    "/home/braghiere/BNF_tom/inputdata/BNFMIP_forcing_from_OCN/BNF_Har/CLM1PT_data" \
    "--mod_parm_file_P /home/braghiere/BNF_tom/OLMT_BNF/define_site_files/US-Ha1/CNP_parameters.nc" \
    ""

HA1_FN_JID=${RESULT_FN_JID}
echo ">>> Ha1 Exp 1 FN job: ${HA1_FN_JID}"

write_and_submit_builder \
    "ha1" "BNF-Ha1" "${HA1_CASEID}" "${HA1_FN_JID}" \
    "${OLMT}/run_ha1_fun_transient_only.sh" \
    "${OLMT}/run_ha1_noacc_transient.sh" \
    "${OLMT}/run_ha1_acc_transient.sh"

HA1_BUILDER_JID=${BUILDER_JID}

# ══════════════════════════════════════════════════════════════════════
# ███  BONANZA CREEK  (BNF-Bon)  — boreal
# ══════════════════════════════════════════════════════════════════════
echo ""
echo "████████████████████████████████████████████████████████████████████"
echo "███  SITE 3/3: BONANZA CREEK (BNF-Bon) — boreal                  ███"
echo "█   Soil: Inceptisols (Typic Cryepts, SOIL_ORDER=5, appropriate)   █"
echo "████████████████████████████████████████████████████████████████████"

BON_CASEID=nofun_baseline_bon_${TODAY}

setup_full_experiment \
    "${BON_CASEID}" \
    "${CASEROOT}/source_codes/control_fixed_funp_nfix" \
    "no" \
    "nofun_bon" \
    "BNF-Bon" \
    "/home/braghiere/BNF_tom/clm_params_fun3_sfix01.nc" \
    "/home/braghiere/BNF_tom/inputdata/BNFMIP_forcing_from_OCN/BNF_Bon/CLM1PT_data" \
    "--mod_parm_file_P /home/braghiere/BNF_tom/OLMT_BNF/define_site_files/US-Bon/CNP_parameters.nc" \
    ""

BON_FN_JID=${RESULT_FN_JID}
echo ">>> Bon Exp 1 FN job: ${BON_FN_JID}"

write_and_submit_builder \
    "bon" "BNF-Bon" "${BON_CASEID}" "${BON_FN_JID}" \
    "${OLMT}/run_bon_fun_transient_only.sh" \
    "${OLMT}/run_bon_noacc_transient.sh" \
    "${OLMT}/run_bon_acc_transient.sh"

BON_BUILDER_JID=${BUILDER_JID}

# ══════════════════════════════════════════════════════════════════════
# Final summary
# ══════════════════════════════════════════════════════════════════════
echo ""
echo "████████████████████████████████████████████████████████████████████"
echo "████████████████████████████████████████████████████████████████████"
echo "███  ALL BNFMIP EXPERIMENTS LAUNCHED                             ███"
echo "████████████████████████████████████████████████████████████████████"
echo ""
echo "━━━ MANAUS (BNF-Man) ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Exp 1  ${MANAUS_CASEID}"
echo "         SourceMods: control_fixed_funp_nfix  (FUN/FUNP OFF)"
echo "         Pipeline:   AD(200yr) → iniadjust → FN(600yr) → TR(1850-2101)"
echo "  Builder job: ${MANAUS_BUILDER_JID}  [depends on FN: ${MANAUS_FN_JID}]"
echo "    → Exp 3  fun_transient_only_manaus  (fun_fpg1_nfix)"
echo "    → Exp 4  noacc_transient_manaus     (noACC_fixed: Tmin=7.04 tropical)"
echo "    → Exp 5  acc_transient_manaus       (ACC_fixed:   Tmin=7.04→ACC tropical)"
echo "  Soil:  Oxisols  (SOIL_ORDER=4, CNP_parameters_manaus_oxisol_v2.nc)"
echo ""
echo "━━━ HARVARD FOREST (BNF-Ha1) ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Exp 1  ${HA1_CASEID}"
echo "         SourceMods: control_fixed_funp_nfix  (FUN/FUNP OFF)"
echo "         Pipeline:   AD(200yr) → iniadjust → FN(600yr) → TR(1850-2101)"
echo "  Builder job: ${HA1_BUILDER_JID}  [depends on FN: ${HA1_FN_JID}]"
echo "    → Exp 3  fun_transient_only_ha1     (fun_fpg1_nfix)"
echo "    → Exp 4  noacc_transient_ha1        (noACC_temperate: Tmin=-2.04 temperate)"
echo "    → Exp 5  acc_transient_ha1          (ACC_temperate:   Tmin=-2.04→ACC temperate)"
echo "  Soil:  Inceptisols (SOIL_ORDER=5, Typic Dystrudepts — corrected from global Alfisol mask)"
echo ""
echo "━━━ BONANZA CREEK (BNF-Bon) ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Exp 1  ${BON_CASEID}"
echo "         SourceMods: control_fixed_funp_nfix  (FUN/FUNP OFF)"
echo "         Pipeline:   AD(200yr) → iniadjust → FN(600yr) → TR(1850-2101)"
echo "  Builder job: ${BON_BUILDER_JID}  [depends on FN: ${BON_FN_JID}]"
echo "    → Exp 3  fun_transient_only_bon      (fun_fpg1_nfix)"
echo "    → Exp 4  noacc_transient_bon         (noACC_temperate: Tmin=-2.04 boreal)"
echo "    → Exp 5  acc_transient_bon           (ACC_temperate:   Tmin=-2.04→ACC boreal)"
echo "  Soil:  Inceptisols (SOIL_ORDER=5, Typic Cryepts — appropriate for boreal mineral soil)"
echo ""
echo "Monitor:   squeue -u \$USER"
echo "Logs dir:  ${OLMT}/logs/"
echo "████████████████████████████████████████████████████████████████████"
