#!/bin/bash
# resubmit_BNFMIP_v2.sh
#
# Resubmits all BNFMIP experiments with corrected paramfiles (sfix01)
# and creates the new "fixed" experiment (2015-2100, CO2 + Ndep fixed at 2014).
#
# Changes from previous sfix1p5 runs:
#   FUN funsp:       paramfile sfix1p5* → sfix01 variant per site
#                    spinup_mortality_factor 10 → 1   (Bon only)
#                    fsurdat → surfdata_bon_gelisol.nc (Bon only)
#                    CONTINUE_RUN=FALSE
#   FUN transient:   paramfile sfix1p5* → sfix01 variant per site
#                    fsurdat → surfdata_bon_gelisol.nc (Bon only)
#                    REST_N=5, REST_OPTION=nyears, CONTINUE_RUN=FALSE
#                    (spinup_mortality_factor/nyears_ad_carbon_only left unchanged — inert in transient)
#   nofun transient: REST_N=5, REST_OPTION=nyears, CONTINUE_RUN=FALSE  (no other changes)
#   Fixed (NEW):     12 new cases cloned from each transient
#                    RUN_TYPE=startup, RUN_STARTDATE=2015-01-01, STOP_N=86 yr
#                    CLM_CO2_TYPE=constant, CCSM_CO2_PPMV=397.7641
#                    Ndep cycling at 2014 (ndep_taxmode=cycle, stream years=2014)
#                    finidat = transient 2015-01-01 restart
#
# Total jobs: 9 FUN funsp + 9 FUN transient + 3 nofun transient + 12 fixed = 33
#
# Usage:
#   bash resubmit_BNFMIP_v2.sh            # full run
#   bash resubmit_BNFMIP_v2.sh --dry-run  # preview only (no changes, no submissions)
#
# Run from login node. No rebuilds required (paramfile is a runtime namelist change).
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

# ── Configuration ────────────────────────────────────────────────────────────
DATE=20260521           # date stamp of existing cases
FIXDATE=20260529        # date stamp for new fixed cases

CASEROOT=/home/braghiere/BNF_tom/OLMT_BNF/cime_case_dirs
RUNROOT=/lustre/or-scratch/cades-ccsi/scratch/braghiere
PARAMDIR=/home/braghiere/BNF_tom
CREATE_CLONE=/home/braghiere/BNF_tom/E3SM_global_silent/cime/scripts/create_clone

CO2_2014=397.7641       # CO2 ppmv from stream file fco2_datm_rcp4.5_1765-2500_c130312.nc for year 2014

LOGDIR=/home/braghiere/BNF_tom/OLMT_BNF/bnfmip_v2_$(date +%Y%m%d_%H%M)
JOBLOG="${LOGDIR}/job_ids.log"

FUN_EXPS=(fun_transient_only noacc_transient acc_transient)
ALL_EXPS=(fun_transient_only noacc_transient acc_transient nofun_baseline)
ALL_SITES=(manaus ha1 bon)

if [[ $DRY_RUN -eq 0 ]]; then
    mkdir -p "${LOGDIR}"
    touch "${JOBLOG}"
fi

# ── Helper: site code ────────────────────────────────────────────────────────
site_code() {
    case "$1" in
        manaus) echo "Man" ;;
        ha1)    echo "Ha1" ;;
        bon)    echo "Bon" ;;
        *) echo "ERROR: unknown site $1" >&2; exit 1 ;;
    esac
}

# ── Helper: paramfile name for a given experiment + site ────────────────────
paramfile_for() {
    local exp=$1 site=$2
    case "${site}" in
        manaus) echo "clm_params_fun3_sfix01_manaus_tuned.nc" ;;
        ha1)    echo "clm_params_fun3_sfix01.nc" ;;
        bon)
            if [[ "${exp}" == "nofun_baseline" ]]; then
                echo "clm_params_fun3_sfix01.nc"
            else
                echo "clm_params_fun3_sfix01_bon_tuned.nc"
            fi ;;
    esac
}

# ── Pre-flight checks ────────────────────────────────────────────────────────
echo "══════════════════════════════════════════════════════════════════"
echo "  BNFMIP Resubmit v2  —  $(date)"
[[ $DRY_RUN -eq 1 ]] && echo "  *** DRY RUN — no changes will be made ***"
echo "══════════════════════════════════════════════════════════════════"
echo ""
echo "▶ Pre-flight checks..."

for PF in clm_params_fun3_sfix01.nc \
           clm_params_fun3_sfix01_manaus_tuned.nc \
           clm_params_fun3_sfix01_bon_tuned.nc \
           surfdata_bon_gelisol.nc; do
    [[ -f "${PARAMDIR}/${PF}" ]] \
        || { echo "  FAIL: missing ${PARAMDIR}/${PF}"; exit 1; }
done
echo "  Paramfiles and surfdata: OK"

[[ -x "${CREATE_CLONE}" ]] \
    || { echo "  FAIL: create_clone not found/not executable at ${CREATE_CLONE}"; exit 1; }
echo "  create_clone: OK"

for exp in "${FUN_EXPS[@]}"; do
    for site in "${ALL_SITES[@]}"; do
        code=$(site_code "${site}")
        for CDIR in \
            "${CASEROOT}/${exp}_${site}_${DATE}_funsp_BNF-${code}_I1850CNPRDCTCBC" \
            "${CASEROOT}/${exp}_${site}_${DATE}_BNF-${code}_I20TRCNPRDCTCBC"; do
            [[ -d "${CDIR}" ]] \
                || { echo "  FAIL: missing case dir: ${CDIR}"; exit 1; }
        done
    done
done
for site in "${ALL_SITES[@]}"; do
    code=$(site_code "${site}")
    NOFUN_TR="${CASEROOT}/nofun_baseline_${site}_${DATE}_BNF-${code}_I20TRCNPRDCTCBC"
    [[ -d "${NOFUN_TR}" ]] \
        || { echo "  FAIL: missing ${NOFUN_TR}"; exit 1; }
done
echo "  Case dirs (21): OK"
echo ""

# Associative arrays for job IDs (funsp and transient phases)
declare -A FUNSP_JIDS
declare -A TR_JIDS

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 1 — FUN funsp cases (Batch A, independent)
# ─────────────────────────────────────────────────────────────────────────────
echo "▶ PHASE 1 — FUN funsp (9 cases, Batch A)"
echo ""

for exp in "${FUN_EXPS[@]}"; do
    for site in "${ALL_SITES[@]}"; do
        code=$(site_code "${site}")
        pf=$(paramfile_for "${exp}" "${site}")

        FUNSP_CASE="${CASEROOT}/${exp}_${site}_${DATE}_funsp_BNF-${code}_I1850CNPRDCTCBC"
        FUNSP_RUN="${RUNROOT}/${exp}_${site}_${DATE}_funsp_BNF-${code}_I1850CNPRDCTCBC/run"

        echo "  ── ${exp} / ${site} ──"
        echo "     paramfile → ${pf}"

        if [[ $DRY_RUN -eq 0 ]]; then
            # Replace paramfile line
            sed -i "s| paramfile = .*| paramfile = '${PARAMDIR}/${pf}'|" \
                "${FUNSP_CASE}/user_nl_clm"
        fi

        # Bon only: spinup_mortality_factor=1 and gelisol surfdata
        if [[ "${site}" == "bon" ]]; then
            echo "     spinup_mortality_factor → 1  (Bon only)"
            echo "     fsurdat → surfdata_bon_gelisol.nc  (Bon only)"
            if [[ $DRY_RUN -eq 0 ]]; then
                sed -i "s/ spinup_mortality_factor = [0-9]*/ spinup_mortality_factor = 1/" \
                    "${FUNSP_CASE}/user_nl_clm"
                sed -i "s| fsurdat = .*| fsurdat = '${PARAMDIR}/surfdata_bon_gelisol.nc'|" \
                    "${FUNSP_CASE}/user_nl_clm"
            fi
        fi

        # Reset CONTINUE_RUN
        echo "     CONTINUE_RUN → FALSE"
        if [[ $DRY_RUN -eq 0 ]]; then
            (cd "${FUNSP_CASE}" && ./xmlchange CONTINUE_RUN=FALSE)
        fi

        # Remove old h0 files from run dir if they exist
        if [[ -d "${FUNSP_RUN}" ]]; then
            NH=$(find "${FUNSP_RUN}" -maxdepth 1 -name "*.clm2.h0.*.nc" 2>/dev/null | wc -l)
            if [[ "${NH}" -gt 0 ]]; then
                echo "     Removing ${NH} old h0 files"
                [[ $DRY_RUN -eq 0 ]] && rm -f "${FUNSP_RUN}"/*.clm2.h0.*.nc
            fi
        fi

        # Submit
        if [[ $DRY_RUN -eq 0 ]]; then
            echo "     Submitting funsp..."
            SUBMIT_OUT=$(cd "${FUNSP_CASE}" && ./case.submit 2>&1)
            echo "${SUBMIT_OUT}" | tail -4
            JID=$(echo "${SUBMIT_OUT}" | \
                grep -oP '(?:Submitted batch job|Submitted job case\.run with id) \K[0-9]+' | head -1)
            if [[ -z "${JID}" ]]; then
                echo "  ERROR: could not capture funsp job ID for ${exp}/${site}" >&2
                exit 1
            fi
            FUNSP_JIDS["${exp}_${site}"]="${JID}"
            echo "  funsp ${exp}/${site}  JOB=${JID}" | tee -a "${JOBLOG}"
        else
            echo "     [DRY] would submit funsp"
        fi
        echo ""
    done
done

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 2 — FUN transient cases (Batch B, depends on Batch A)
# ─────────────────────────────────────────────────────────────────────────────
echo "▶ PHASE 2 — FUN transient (9 cases, Batch B)"
echo ""

for exp in "${FUN_EXPS[@]}"; do
    for site in "${ALL_SITES[@]}"; do
        code=$(site_code "${site}")
        pf=$(paramfile_for "${exp}" "${site}")

        TR_CASE="${CASEROOT}/${exp}_${site}_${DATE}_BNF-${code}_I20TRCNPRDCTCBC"
        TR_RUN="${RUNROOT}/${exp}_${site}_${DATE}_BNF-${code}_I20TRCNPRDCTCBC/run"

        echo "  ── ${exp} / ${site} ──"
        echo "     paramfile → ${pf}"

        if [[ $DRY_RUN -eq 0 ]]; then
            sed -i "s| paramfile = .*| paramfile = '${PARAMDIR}/${pf}'|" \
                "${TR_CASE}/user_nl_clm"
        fi

        # Bon only: gelisol surfdata
        if [[ "${site}" == "bon" ]]; then
            echo "     fsurdat → surfdata_bon_gelisol.nc  (Bon only)"
            if [[ $DRY_RUN -eq 0 ]]; then
                sed -i "s| fsurdat = .*| fsurdat = '${PARAMDIR}/surfdata_bon_gelisol.nc'|" \
                    "${TR_CASE}/user_nl_clm"
            fi
        fi

        # REST_N=5 for 2015 checkpoint, reset CONTINUE_RUN
        echo "     REST_OPTION=nyears, REST_N=5, CONTINUE_RUN=FALSE"
        if [[ $DRY_RUN -eq 0 ]]; then
            (cd "${TR_CASE}" && ./xmlchange REST_OPTION=nyears)
            (cd "${TR_CASE}" && ./xmlchange REST_N=5)
            (cd "${TR_CASE}" && ./xmlchange CONTINUE_RUN=FALSE)
        fi

        # Remove old h0 files
        if [[ -d "${TR_RUN}" ]]; then
            NH=$(find "${TR_RUN}" -maxdepth 1 -name "*.clm2.h0.*.nc" 2>/dev/null | wc -l)
            if [[ "${NH}" -gt 0 ]]; then
                echo "     Removing ${NH} old h0 files"
                [[ $DRY_RUN -eq 0 ]] && rm -f "${TR_RUN}"/*.clm2.h0.*.nc
            fi
        fi

        # Submit with dependency on funsp
        if [[ $DRY_RUN -eq 0 ]]; then
            FUNSP_JID="${FUNSP_JIDS[${exp}_${site}]}"
            echo "     Submitting transient (dep afterok:${FUNSP_JID})..."
            SUBMIT_OUT=$(cd "${TR_CASE}" && \
                ./case.submit --batch-args="--dependency=afterok:${FUNSP_JID}" 2>&1)
            echo "${SUBMIT_OUT}" | tail -4
            JID=$(echo "${SUBMIT_OUT}" | \
                grep -oP '(?:Submitted batch job|Submitted job case\.run with id) \K[0-9]+' | head -1)
            if [[ -z "${JID}" ]]; then
                echo "  ERROR: could not capture transient job ID for ${exp}/${site}" >&2
                exit 1
            fi
            TR_JIDS["${exp}_${site}"]="${JID}"
            echo "  transient ${exp}/${site}  JOB=${JID}  (dep funsp ${FUNSP_JID})" \
                | tee -a "${JOBLOG}"
        else
            echo "     [DRY] would submit transient with dep on funsp"
        fi
        echo ""
    done
done

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 3 — nofun transient cases (Batch C, independent)
# ─────────────────────────────────────────────────────────────────────────────
echo "▶ PHASE 3 — nofun transient (3 cases, Batch C)"
echo ""

for site in "${ALL_SITES[@]}"; do
    code=$(site_code "${site}")

    NOFUN_TR="${CASEROOT}/nofun_baseline_${site}_${DATE}_BNF-${code}_I20TRCNPRDCTCBC"
    NOFUN_RUN="${RUNROOT}/nofun_baseline_${site}_${DATE}_BNF-${code}_I20TRCNPRDCTCBC/run"

    echo "  ── nofun_baseline / ${site} ──"

    # No paramfile change needed (already sfix01); only env_run.xml fixes
    echo "     REST_OPTION=nyears, REST_N=5, CONTINUE_RUN=FALSE"
    if [[ $DRY_RUN -eq 0 ]]; then
        (cd "${NOFUN_TR}" && ./xmlchange REST_OPTION=nyears)
        (cd "${NOFUN_TR}" && ./xmlchange REST_N=5)
        (cd "${NOFUN_TR}" && ./xmlchange CONTINUE_RUN=FALSE)
    fi

    # Remove old h0 files
    if [[ -d "${NOFUN_RUN}" ]]; then
        NH=$(find "${NOFUN_RUN}" -maxdepth 1 -name "*.clm2.h0.*.nc" 2>/dev/null | wc -l)
        if [[ "${NH}" -gt 0 ]]; then
            echo "     Removing ${NH} old h0 files"
            [[ $DRY_RUN -eq 0 ]] && rm -f "${NOFUN_RUN}"/*.clm2.h0.*.nc
        fi
    fi

    # Submit (no dependency)
    if [[ $DRY_RUN -eq 0 ]]; then
        echo "     Submitting nofun transient..."
        SUBMIT_OUT=$(cd "${NOFUN_TR}" && ./case.submit 2>&1)
        echo "${SUBMIT_OUT}" | tail -4
        JID=$(echo "${SUBMIT_OUT}" | \
            grep -oP '(?:Submitted batch job|Submitted job case\.run with id) \K[0-9]+' | head -1)
        if [[ -z "${JID}" ]]; then
            echo "  ERROR: could not capture nofun transient job ID for ${site}" >&2
            exit 1
        fi
        TR_JIDS["nofun_baseline_${site}"]="${JID}"
        echo "  transient nofun_baseline/${site}  JOB=${JID}" | tee -a "${JOBLOG}"
    else
        echo "     [DRY] would submit nofun transient"
    fi
    echo ""
done

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 4 — Fixed cases (Batch D, clone from transient + dep on B/C)
# ─────────────────────────────────────────────────────────────────────────────
echo "▶ PHASE 4 — Fixed runs (12 new cases, Batch D)"
echo ""

for exp in "${ALL_EXPS[@]}"; do
    for site in "${ALL_SITES[@]}"; do
        code=$(site_code "${site}")

        # Source transient (already edited in Phase 2/3)
        SRC_TR="${CASEROOT}/${exp}_${site}_${DATE}_BNF-${code}_I20TRCNPRDCTCBC"

        # New fixed case
        FIXED_CASEID="${exp}_${site}_${FIXDATE}_fixed_BNF-${code}_I20TRCNPRDCTCBC"
        FIXED_CASE="${CASEROOT}/${FIXED_CASEID}"

        # finidat: 2015 restart written by the transient rerun
        TR_CASEID="${exp}_${site}_${DATE}_BNF-${code}_I20TRCNPRDCTCBC"
        FINIDAT="${RUNROOT}/${TR_CASEID}/run/${TR_CASEID}.clm2.r.2015-01-01-00000.nc"

        # Dependency job ID
        if [[ "${exp}" == "nofun_baseline" ]]; then
            DEP_KEY="nofun_baseline_${site}"
        else
            DEP_KEY="${exp}_${site}"
        fi

        echo "  ── ${exp} / ${site} ──"
        echo "     new case: ${FIXED_CASEID}"
        echo "     finidat:  ${FINIDAT}"
        echo "     CO2:      ${CO2_2014} ppmv constant"
        echo "     Ndep:     cycling at 2014"

        if [[ $DRY_RUN -eq 0 ]]; then
            DEP_JID="${TR_JIDS[${DEP_KEY}]}"

            # Create clone (skip if already exists to allow re-entry)
            if [[ ! -d "${FIXED_CASE}" ]]; then
                echo "     Cloning with --keepexe..."
                "${CREATE_CLONE}" \
                    --case "${FIXED_CASE}" \
                    --clone "${SRC_TR}" \
                    --keepexe \
                    --silent 2>&1 | tail -3
            else
                echo "     Clone already exists — reusing"
            fi

            # Apply fixed-run settings via xmlchange
            echo "     Applying env_run.xml settings..."
            cd "${FIXED_CASE}"
            ./xmlchange RUN_TYPE=startup
            ./xmlchange RUN_STARTDATE=2015-01-01
            ./xmlchange STOP_OPTION=nyears
            ./xmlchange STOP_N=86
            ./xmlchange REST_OPTION=nyears
            ./xmlchange REST_N=5
            ./xmlchange CLM_CO2_TYPE=constant
            ./xmlchange CCSM_CO2_PPMV="${CO2_2014}"
            ./xmlchange CONTINUE_RUN=FALSE

            # Update user_nl_clm: replace finidat line
            if grep -q "finidat" "${FIXED_CASE}/user_nl_clm"; then
                sed -i "s| finidat = .*| finidat = '${FINIDAT}'|" \
                    "${FIXED_CASE}/user_nl_clm"
            else
                echo " finidat = '${FINIDAT}'" >> "${FIXED_CASE}/user_nl_clm"
            fi

            # Append Ndep stream year settings (guard against duplicate appends)
            if ! grep -q "stream_year_first_ndep" "${FIXED_CASE}/user_nl_clm"; then
                cat >> "${FIXED_CASE}/user_nl_clm" << 'NLEOF'
 stream_year_first_ndep = 2014
 stream_year_last_ndep = 2014
NLEOF
            fi

            # Submit with dependency on transient
            echo "     Submitting fixed run (dep afterok:${DEP_JID})..."
            SUBMIT_OUT=$(cd "${FIXED_CASE}" && \
                ./case.submit --batch-args="--dependency=afterok:${DEP_JID}" 2>&1)
            echo "${SUBMIT_OUT}" | tail -4
            JID=$(echo "${SUBMIT_OUT}" | \
                grep -oP '(?:Submitted batch job|Submitted job case\.run with id) \K[0-9]+' | head -1)
            if [[ -z "${JID}" ]]; then
                echo "  WARNING: could not capture fixed job ID for ${exp}/${site}"
                echo "  fixed ${exp}/${site}  JOB=UNKNOWN  (dep transient ${DEP_JID})" \
                    | tee -a "${JOBLOG}"
            else
                echo "  fixed ${exp}/${site}  JOB=${JID}  (dep transient ${DEP_JID})" \
                    | tee -a "${JOBLOG}"
            fi
        else
            DEP_JID="<Phase2/3_JID>"
            echo "     [DRY] would clone ${SRC_TR}"
            echo "     [DRY] xmlchange: RUN_TYPE=startup RUN_STARTDATE=2015-01-01"
            echo "                       STOP_N=86 REST_N=5"
            echo "                       CLM_CO2_TYPE=constant CCSM_CO2_PPMV=${CO2_2014}"
            echo "     [DRY] finidat → ${FINIDAT}"
            echo "     [DRY] ndep_taxmode=cycle stream_year=2014"
            echo "     [DRY] would submit with dep on transient ${DEP_JID}"
        fi
        echo ""
    done
done

# ─────────────────────────────────────────────────────────────────────────────
echo "══════════════════════════════════════════════════════════════════"
if [[ $DRY_RUN -eq 1 ]]; then
    echo "  DRY RUN complete. Re-run without --dry-run to execute."
else
    echo "  All 33 jobs submitted."
    echo "  Job log: ${JOBLOG}"
    echo ""
    echo "  Monitor with:  squeue -u braghiere"
    echo ""
    echo "  Job summary:"
    cat "${JOBLOG}"
fi
echo "══════════════════════════════════════════════════════════════════"
