#!/bin/bash
# submit_section54_fixed.sh
#
# Submit Section 5.4 (fixed CO2 + fixed Ndep) runs for ALL 3 sites × 4 experiments.
#
# Protocol: BNFMIP Section 5.4 — "CO2 and N deposition will remain as they were
# at the end of 2014" (i.e., held at 2015-01-01 values):
#   - CO2 fixed via DATM_CO2_TSERIES=none + CCSM_CO2_PPMV=398.87
#   - Ndep fixed via stream_year_first_ndep=2015 + stream_year_last_ndep=2015
#   - Climate follows SSP5-8.5 (transient — only CO2 and Ndep are fixed)
#
# PREREQUISITES:
#   - I20TR (Section 5.3+5.5) runs must have produced 2015-01-01 restart files
#   - Pass the CASEID of the nofun_baseline for each site as positional arguments
#
# USAGE:
#   srun -A ccsi -p burst -N 1 -n 1 -t 4:00:00 --mem 32G \
#        --exclude=or-condo-c105,or-condo-c67,or-condo-c04 --pty bash
#   bash submit_section54_fixed.sh \
#        nofun_baseline_manaus_20260529 \
#        nofun_baseline_ha1_20260529 \
#        nofun_baseline_bon_20260529
#
# EXPERIMENTS (4 per site = 12 total IRCP85 runs):
#   Exp 1: nofun_baseline       (IRCP85, FUN/FUNP OFF)
#   Exp 3: fun_transient_only   (IRCP85, FUN/FUNP ON, Houlton)
#   Exp 4: noacc_transient      (IRCP85, FUN/FUNP ON, Bytnerowicz noACC)
#   Exp 5: acc_transient        (IRCP85, FUN/FUNP ON, Bytnerowicz ACC)

set -e

# ── Safety: must run on a compute node ──
if [[ "$(hostname)" == *login* ]]; then
    echo "ERROR: Must run on a compute node, not $(hostname)!" >&2
    exit 1
fi

if [[ $# -lt 3 ]]; then
    echo "USAGE: $0 <NOFUN_MAN_CASEID> <NOFUN_HA1_CASEID> <NOFUN_BON_CASEID>" >&2
    echo "  e.g.: $0 nofun_baseline_manaus_20260529 nofun_baseline_ha1_20260529 nofun_baseline_bon_20260529" >&2
    exit 1
fi

NOFUN_MAN="$1"
NOFUN_HA1="$2"
NOFUN_BON="$3"

source ~/elm_env_cades_gcc12.sh

OLMT=/home/braghiere/BNF_tom/OLMT_BNF
MODEL_ROOT=/home/braghiere/BNF_tom/E3SM_global_silent
CCSM_INPUT="${CCSM_INPUT:-/lustre/or-scratch/cades-ccsi/proj-shared/project_acme/e3sm_inputdata}"
RUNROOT=/lustre/or-scratch/cades-ccsi/scratch/braghiere
CASEROOT=/home/braghiere/BNF_tom/OLMT_BNF/cime_case_dirs
TODAY=$(date +%Y%m%d)

# Fixed 2015 CO2 concentration (global mean, NOAA/ESRL)
CO2_2015=398.87

mkdir -p ${OLMT}/logs

# ══════════════════════════════════════════════════════════════════════
# Helper: submit one IRCP85 case for one experiment × one site
#
# Args:
#   1  EXP_LABEL      — e.g., acc_transient
#   2  SITE           — BNF-Man, BNF-Ha1, BNF-Bon
#   3  SITE_TAG       — manaus, ha1, bon
#   4  NOFUN_CASEID   — nofun_baseline CASEID for this site
#   5  FUN_ON         — "yes" or "no"
#   6  SOURCEMODS     — full path to SourceMods dir
#   7  CLM_PARAMFILE  — full path to CLM parameter file
#   8  SOILORDER_FILE — fsoilordercon path (Manaus only) or ""
#   9  MOD_PARM_P_ARG — "--mod_parm_file_P /path" or ""
#
# Returns Slurm job ID via RESULT_JID
# ══════════════════════════════════════════════════════════════════════
RESULT_JID=""

submit_section54() {
    local EXP_LABEL=$1
    local SITE=$2
    local SITE_TAG=$3
    local NOFUN_CASEID=$4
    local FUN_ON=$5
    local SOURCEMODS=$6
    local CLM_PARAMFILE=$7
    local SOILORDER_FILE=$8
    local MOD_PARM_P_ARG=$9

    local CASEID=${EXP_LABEL}_${SITE_TAG}_${TODAY}
    local I20TR_RUNDIR=${RUNROOT}/${CASEID}_${SITE}_I20TRCNPRDCTCBC
    local IRCP85_CASE=${CASEROOT}/${CASEID}_${SITE}_IRCP85CNPRDCTCBC
    local AD_CASE=${CASEROOT}/${CASEID}_${SITE}_I1850CNRDCTCBC_ad_spinup
    local EXEROOT=${RUNROOT}/${CASEID}_${SITE}_I1850CNRDCTCBC_ad_spinup/bld

    echo ""
    echo "──────────────────────────────────────────────────────────────────"
    echo "=== Section 5.4: ${EXP_LABEL} / ${SITE} ==="
    echo "    FUN_ON: ${FUN_ON} | SourceMods: $(basename ${SOURCEMODS})"

    # Verify 2015-01-01 restart from I20TR run exists
    local FINIDAT
    FINIDAT=$(ls ${I20TR_RUNDIR}/run/${CASEID}_${SITE}_I20TRCNPRDCTCBC.clm2.r.2015-01-01-*.nc 2>/dev/null | head -1)
    if [[ -z "${FINIDAT}" ]]; then
        echo "ERROR: 2015-01-01 restart not found in ${I20TR_RUNDIR}/run/" >&2
        echo "  The I20TR (Section 5.3/5.5) run must complete past 2015 first." >&2
        exit 1
    fi
    echo "    finidat: $(basename ${FINIDAT})"

    # Cleanup
    [ -d "${IRCP85_CASE}" ] && rm -rf "${IRCP85_CASE}" && echo "  Removed existing ${IRCP85_CASE}"
    [ -d "${RUNROOT}/${CASEID}_${SITE}_IRCP85CNPRDCTCBC" ] && \
        rm -rf "${RUNROOT}/${CASEID}_${SITE}_IRCP85CNPRDCTCBC"

    # Create IRCP85 case via OLMT
    cd ${OLMT}
    python3 site_fullrun.py \
        --site ${SITE} --sitegroup BNF --machine cades \
        --caseidprefix ${CASEID} \
        --model_root ${MODEL_ROOT} --ccsm_input ${CCSM_INPUT} \
        --runroot ${RUNROOT} --caseroot ${CASEROOT} \
        --mpilib openmpi --np 1 --walltime 24 --nofire \
        --clm_paramfile ${CLM_PARAMFILE} \
        ${MOD_PARM_P_ARG} \
        --nyears_ad_spinup 200 --nyears_final_spinup 600 \
        --batch_build --no_submit

    # Reuse exe from the I20TR build (same SourceMods)
    if [ ! -f "${EXEROOT}/e3sm.exe" ]; then
        echo "  No exe at ${EXEROOT} — building from AD case SourceMods..."
        mkdir -p ${AD_CASE}/SourceMods/src.clm
        cp ${SOURCEMODS}/*.F90 ${AD_CASE}/SourceMods/src.clm/
        if [[ -d ${CASEROOT}/source_codes/_shared_elm_fun_col_es ]]; then
            cp ${CASEROOT}/source_codes/_shared_elm_fun_col_es/*.F90 \
               ${AD_CASE}/SourceMods/src.clm/
        fi
        ( cd ${AD_CASE} && ./case.build 2>&1 | tee build_sec54_${EXP_LABEL}.log )
        if [ ! -f "${EXEROOT}/e3sm.exe" ]; then
            echo "ERROR: Build FAILED." >&2; exit 1
        fi
        echo "  exe built: ${EXEROOT}/e3sm.exe"
    else
        echo "  Reusing exe: ${EXEROOT}/e3sm.exe"
    fi

    # Set BUILD_COMPLETE + EXEROOT on IRCP85 case
    ( cd ${IRCP85_CASE} && \
      ./xmlchange BUILD_COMPLETE=TRUE && \
      ./xmlchange EXEROOT=${EXEROOT} && \
      echo "  BUILD_COMPLETE=TRUE, EXEROOT set" )

    # Fix CO2: use fixed 2015 level
    ( cd ${IRCP85_CASE} && \
      ./xmlchange DATM_CO2_TSERIES=none && \
      ./xmlchange CCSM_CO2_PPMV=${CO2_2015} && \
      echo "  CO2 fixed: DATM_CO2_TSERIES=none, CCSM_CO2_PPMV=${CO2_2015}" )

    # Configure user_nl_clm
    local NL="${IRCP85_CASE}/user_nl_clm"

    # finidat
    sed -i "s|finidat = .*|finidat = '${FINIDAT}'|" ${NL}

    # ── FIX NDEP AT 2015 (Section 5.4 requirement) ──────────────────
    if grep -q 'stream_year_first_ndep' ${NL}; then
        sed -i "s|stream_year_first_ndep.*|stream_year_first_ndep = 2015|" ${NL}
        sed -i "s|stream_year_last_ndep.*|stream_year_last_ndep  = 2015|" ${NL}
    else
        printf "\n! Section 5.4: fix Ndep at 2015\nstream_year_first_ndep = 2015\nstream_year_last_ndep  = 2015\n" >> ${NL}
    fi
    echo "  Ndep fixed: stream_year_first/last_ndep = 2015"

    # FUN/FUNP flags
    if [[ "${FUN_ON}" == "yes" ]]; then
        sed -i 's/use_fun = .false./use_fun = .true./'   ${NL}
        sed -i 's/use_funp = .false./use_funp = .true./' ${NL}
        grep -q 'use_fun'  ${NL} || echo 'use_fun  = .true.' >> ${NL}
        grep -q 'use_funp' ${NL} || echo 'use_funp = .true.' >> ${NL}
        echo "  FUN/FUNP: ON"
    else
        echo "  FUN/FUNP: OFF"
    fi

    # Inject fsoilordercon (Manaus only)
    if [[ -n "${SOILORDER_FILE}" ]]; then
        if grep -q 'fsoilordercon' ${NL}; then
            sed -i "s|fsoilordercon.*|fsoilordercon = '${SOILORDER_FILE}'|" ${NL}
        else
            echo " fsoilordercon = '${SOILORDER_FILE}'" >> ${NL}
        fi
        echo "  fsoilordercon: $(basename ${SOILORDER_FILE})"
    fi

    ( cd ${IRCP85_CASE} && ./preview_namelists 2>&1 | tail -3 )

    # Patch PBS script
    local PBSDIR=${OLMT}/scripts/${CASEID}
    if [ -d "${PBSDIR}" ]; then
        for f in ${PBSDIR}/*.pbs; do
            grep -q "exclude" "$f" || \
                sed -i '/#SBATCH  --nodes=1/a #SBATCH  --exclude=or-condo-c105,or-condo-c67,or-condo-c04' "$f"
        done
    fi

    # Submit IRCP85 transient
    local IRCP85_PBS="${PBSDIR}/transient_group0.pbs"
    if [ ! -f "${IRCP85_PBS}" ]; then
        # Fall back: submit via case.submit
        local out
        out=$( cd ${IRCP85_CASE} && ./case.submit 2>&1 )
        RESULT_JID=$(echo "$out" | grep -oP '(?:Submitted batch job|Submitted job case\.run with id) \K[0-9]+' | head -1)
    else
        local out
        out=$(sbatch "${IRCP85_PBS}" 2>&1)
        RESULT_JID=$(echo "$out" | awk '{print $4}')
    fi
    echo "  Submitted: job ${RESULT_JID}"
}

# ══════════════════════════════════════════════════════════════════════
# MANAUS (BNF-Man)
# ══════════════════════════════════════════════════════════════════════
echo ""; echo "████  MANAUS (BNF-Man) — Section 5.4  ████"

MAN_CLM1=/home/braghiere/BNF_tom/clm_params_fun3_sfix01_manaus_tuned.nc
MAN_CLM4=/home/braghiere/BNF_tom/clm_params_fun3_sfix6_manaus_tuned.nc
MAN_CNP=/home/braghiere/BNF_tom/CNP_parameters_manaus_oxisol_v2.nc

submit_section54 "nofun_baseline"     "BNF-Man" "manaus" "${NOFUN_MAN}" "no"  \
    "${CASEROOT}/source_codes/control_fixed_funp_nfix"  "${MAN_CLM1}" "${MAN_CNP}" ""
MAN_NOFUN_JID=${RESULT_JID}

submit_section54 "fun_transient_only" "BNF-Man" "manaus" "${NOFUN_MAN}" "yes" \
    "${CASEROOT}/source_codes/fun_fpg1_nfix"            "${MAN_CLM4}" "${MAN_CNP}" ""
MAN_FUN_JID=${RESULT_JID}

submit_section54 "noacc_transient"    "BNF-Man" "manaus" "${NOFUN_MAN}" "yes" \
    "${CASEROOT}/source_codes/noACC_fixed_funp_nfix"    "${MAN_CLM4}" "${MAN_CNP}" ""
MAN_NOACC_JID=${RESULT_JID}

submit_section54 "acc_transient"      "BNF-Man" "manaus" "${NOFUN_MAN}" "yes" \
    "${CASEROOT}/source_codes/ACC_fixed_funp_nfix"      "${MAN_CLM4}" "${MAN_CNP}" ""
MAN_ACC_JID=${RESULT_JID}

# ══════════════════════════════════════════════════════════════════════
# HARVARD FOREST (BNF-Ha1)
# ══════════════════════════════════════════════════════════════════════
echo ""; echo "████  HARVARD FOREST (BNF-Ha1) — Section 5.4  ████"

HA1_CLM1=/home/braghiere/BNF_tom/clm_params_fun3_sfix01.nc
HA1_CLM4=/home/braghiere/BNF_tom/clm_params_fun3_sfix6.nc
HA1_P="--mod_parm_file_P /home/braghiere/BNF_tom/OLMT_BNF/define_site_files/US-Ha1/CNP_parameters.nc"

submit_section54 "nofun_baseline"     "BNF-Ha1" "ha1" "${NOFUN_HA1}" "no"  \
    "${CASEROOT}/source_codes/control_fixed_funp_nfix"  "${HA1_CLM1}" "" "${HA1_P}"
HA1_NOFUN_JID=${RESULT_JID}

submit_section54 "fun_transient_only" "BNF-Ha1" "ha1" "${NOFUN_HA1}" "yes" \
    "${CASEROOT}/source_codes/fun_fpg1_nfix"            "${HA1_CLM4}" "" "${HA1_P}"
HA1_FUN_JID=${RESULT_JID}

submit_section54 "noacc_transient"    "BNF-Ha1" "ha1" "${NOFUN_HA1}" "yes" \
    "${CASEROOT}/source_codes/noACC_temperate_funp_nfix" "${HA1_CLM4}" "" "${HA1_P}"
HA1_NOACC_JID=${RESULT_JID}

submit_section54 "acc_transient"      "BNF-Ha1" "ha1" "${NOFUN_HA1}" "yes" \
    "${CASEROOT}/source_codes/ACC_temperate_funp_nfix"  "${HA1_CLM4}" "" "${HA1_P}"
HA1_ACC_JID=${RESULT_JID}

# ══════════════════════════════════════════════════════════════════════
# BONANZA CREEK (BNF-Bon)
# ══════════════════════════════════════════════════════════════════════
echo ""; echo "████  BONANZA CREEK (BNF-Bon) — Section 5.4  ████"

BON_CLM1=/home/braghiere/BNF_tom/clm_params_fun3_sfix01.nc
BON_CLM4=/home/braghiere/BNF_tom/clm_params_fun3_sfix6.nc
BON_P="--mod_parm_file_P /home/braghiere/BNF_tom/OLMT_BNF/define_site_files/US-Bon/CNP_parameters.nc"

submit_section54 "nofun_baseline"     "BNF-Bon" "bon" "${NOFUN_BON}" "no"  \
    "${CASEROOT}/source_codes/control_fixed_funp_nfix"  "${BON_CLM1}" "" "${BON_P}"
BON_NOFUN_JID=${RESULT_JID}

submit_section54 "fun_transient_only" "BNF-Bon" "bon" "${NOFUN_BON}" "yes" \
    "${CASEROOT}/source_codes/fun_fpg1_nfix"            "${BON_CLM4}" "" "${BON_P}"
BON_FUN_JID=${RESULT_JID}

submit_section54 "noacc_transient"    "BNF-Bon" "bon" "${NOFUN_BON}" "yes" \
    "${CASEROOT}/source_codes/noACC_temperate_funp_nfix" "${BON_CLM4}" "" "${BON_P}"
BON_NOACC_JID=${RESULT_JID}

submit_section54 "acc_transient"      "BNF-Bon" "bon" "${NOFUN_BON}" "yes" \
    "${CASEROOT}/source_codes/ACC_temperate_funp_nfix"  "${BON_CLM4}" "" "${BON_P}"
BON_ACC_JID=${RESULT_JID}

# ══════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════
echo ""
echo "████████████████████████████████████████████████████████████████████"
echo "███  SECTION 5.4 SUBMITTED — 12 IRCP85 runs                      ███"
echo "████████████████████████████████████████████████████████████████████"
echo ""
printf "%-10s %-25s %-25s %-25s\n" "Site" "nofun" "fun_only" "noacc" "acc"
printf "%-10s %-25s %-25s %-25s %-25s\n" "Manaus" "${MAN_NOFUN_JID}" "${MAN_FUN_JID}" "${MAN_NOACC_JID}" "${MAN_ACC_JID}"
printf "%-10s %-25s %-25s %-25s %-25s\n" "Ha1"    "${HA1_NOFUN_JID}" "${HA1_FUN_JID}" "${HA1_NOACC_JID}" "${HA1_ACC_JID}"
printf "%-10s %-25s %-25s %-25s %-25s\n" "Bon"    "${BON_NOFUN_JID}" "${BON_FUN_JID}" "${BON_NOACC_JID}" "${BON_ACC_JID}"
echo ""
echo "CO2 fixed at ${CO2_2015} ppm (2015 global mean)"
echo "Ndep fixed at 2015 via stream_year_first/last_ndep = 2015"
echo "Monitor: squeue -u \$USER"
