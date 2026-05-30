#!/bin/bash
# resubmit_phase4_fixed.sh
#
# Creates the 12 "fixed" cases (Phase 4 of BNFMIP resubmit v2) and submits
# SLURM wrapper jobs that run after the transients complete.
#
# Strategy: CIME's case.submit checks for input file existence at submit time,
# but the finidat (2015-01-01 restart) doesn't exist until the transient runs.
# Solution: submit a small SLURM wrapper job (dep=afterok:transient_JID) that
# calls ./case.submit when the transient has finished and the finidat exists.
#
# Fixed run settings:
#   RUN_TYPE=startup, RUN_STARTDATE=2015-01-01, STOP_N=86 yr (2015-2100)
#   CLM_CO2_TYPE=constant, CCSM_CO2_PPMV=397.7641
#   Ndep: stream_year_first/last_ndep=2014
#   finidat = transient's 2015-01-01-00000 restart (written by transient run)
#
# Usage:
#   bash resubmit_phase4_fixed.sh            # run
#   bash resubmit_phase4_fixed.sh --dry-run  # preview only
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

DATE=20260521
FIXDATE=20260529
CASEROOT=/home/braghiere/BNF_tom/OLMT_BNF/cime_case_dirs
RUNROOT=/lustre/or-scratch/cades-ccsi/scratch/braghiere
PARAMDIR=/home/braghiere/BNF_tom
CREATE_CLONE=/home/braghiere/BNF_tom/E3SM_global_silent/cime/scripts/create_clone
CO2_2014=397.7641

LOGDIR=/home/braghiere/BNF_tom/OLMT_BNF/bnfmip_phase4_$(date +%Y%m%d_%H%M)
JOBLOG="${LOGDIR}/job_ids_phase4.log"
[[ $DRY_RUN -eq 0 ]] && mkdir -p "${LOGDIR}" && touch "${JOBLOG}"

ALL_EXPS=(fun_transient_only noacc_transient acc_transient nofun_baseline)
ALL_SITES=(manaus ha1 bon)

site_code() {
    case "$1" in
        manaus) echo "Man" ;; ha1) echo "Ha1" ;; bon) echo "Bon" ;;
        *) echo "ERROR: unknown site $1" >&2; exit 1 ;;
    esac
}

# ── Hardcoded transient job IDs from Phase 1-3 ───────────────────────────────
declare -A TR_JIDS
TR_JIDS[fun_transient_only_manaus]=5390793
TR_JIDS[fun_transient_only_ha1]=5390794
TR_JIDS[fun_transient_only_bon]=5390795
TR_JIDS[noacc_transient_manaus]=5390796
TR_JIDS[noacc_transient_ha1]=5390797
TR_JIDS[noacc_transient_bon]=5390798
TR_JIDS[acc_transient_manaus]=5390799
TR_JIDS[acc_transient_ha1]=5390800
TR_JIDS[acc_transient_bon]=5390801
TR_JIDS[nofun_baseline_manaus]=5390802
TR_JIDS[nofun_baseline_ha1]=5390803
TR_JIDS[nofun_baseline_bon]=5390804

echo "══════════════════════════════════════════════════════════════════"
echo "  BNFMIP Phase 4 — Fixed runs  —  $(date)"
[[ $DRY_RUN -eq 1 ]] && echo "  *** DRY RUN ***"
echo "══════════════════════════════════════════════════════════════════"
echo ""

for exp in "${ALL_EXPS[@]}"; do
    for site in "${ALL_SITES[@]}"; do
        code=$(site_code "${site}")

        # Source transient (already updated by Phase 2/3)
        SRC_TR="${CASEROOT}/${exp}_${site}_${DATE}_BNF-${code}_I20TRCNPRDCTCBC"

        # New fixed case
        FIXED_CASEID="${exp}_${site}_${FIXDATE}_fixed_BNF-${code}_I20TRCNPRDCTCBC"
        FIXED_CASE="${CASEROOT}/${FIXED_CASEID}"

        # finidat: 2015 restart written by the transient run
        TR_CASEID="${exp}_${site}_${DATE}_BNF-${code}_I20TRCNPRDCTCBC"
        FINIDAT="${RUNROOT}/${TR_CASEID}/run/${TR_CASEID}.clm2.r.2015-01-01-00000.nc"

        DEP_JID="${TR_JIDS[${exp}_${site}]}"

        echo "  ── ${exp} / ${site} ──"
        echo "     new case: ${FIXED_CASEID}"
        echo "     finidat:  ${FINIDAT}"
        echo "     dep JID:  ${DEP_JID}"

        if [[ $DRY_RUN -eq 0 ]]; then

            # Create clone (skip if already exists)
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

            # Apply fixed-run env settings
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

            # Update user_nl_clm finidat (points to future restart — will exist at run time)
            if grep -q "finidat" "${FIXED_CASE}/user_nl_clm"; then
                sed -i "s| finidat = .*| finidat = '${FINIDAT}'|" \
                    "${FIXED_CASE}/user_nl_clm"
            else
                echo " finidat = '${FINIDAT}'" >> "${FIXED_CASE}/user_nl_clm"
            fi

            # Append Ndep stream year lock (guard against duplicate appends)
            if ! grep -q "stream_year_first_ndep" "${FIXED_CASE}/user_nl_clm"; then
                printf ' stream_year_first_ndep = 2014\n stream_year_last_ndep = 2014\n' \
                    >> "${FIXED_CASE}/user_nl_clm"
            fi

            # ── Create SLURM wrapper job ──────────────────────────────────────
            # The wrapper runs after the transient (finidat now exists) and
            # calls case.submit which will then succeed.
            WRAPPER="${LOGDIR}/submit_fixed_${exp}_${site}.sh"
            cat > "${WRAPPER}" << WRAPEOF
#!/bin/bash
#SBATCH -J fix_${exp:0:6}_${site:0:3}
#SBATCH -A ccsi
#SBATCH -p batch
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH -t 00:15:00
#SBATCH --mem=4G
#SBATCH -o ${LOGDIR}/submit_fixed_${exp}_${site}_%j.out
#SBATCH -e ${LOGDIR}/submit_fixed_${exp}_${site}_%j.err

echo "Wrapper running at \$(date) on \$(hostname)"
echo "Submitting fixed run: ${FIXED_CASEID}"

# Verify finidat exists before submitting
if [[ ! -f "${FINIDAT}" ]]; then
    echo "ERROR: finidat not found: ${FINIDAT}"
    echo "Transient run (job ${DEP_JID}) may have failed to write the 2015 restart."
    exit 1
fi
echo "finidat confirmed: ${FINIDAT}"

cd "${FIXED_CASE}" && ./case.submit
echo "Submission complete at \$(date)"
WRAPEOF
            chmod +x "${WRAPPER}"

            # Submit wrapper with dependency on transient
            WRAP_OUT=$(sbatch --dependency=afterok:${DEP_JID} "${WRAPPER}" 2>&1)
            echo "${WRAP_OUT}"
            WRAP_JID=$(echo "${WRAP_OUT}" | awk '/Submitted/{print $NF}')
            if [[ -z "${WRAP_JID}" ]]; then
                echo "  WARNING: could not capture wrapper job ID for ${exp}/${site}"
                echo "  fixed ${exp}/${site}  WRAPPER=UNKNOWN  (dep transient ${DEP_JID})" \
                    | tee -a "${JOBLOG}"
            else
                echo "  fixed ${exp}/${site}  WRAPPER=${WRAP_JID}  (dep transient ${DEP_JID})" \
                    | tee -a "${JOBLOG}"
            fi
        else
            echo "     [DRY] would clone ${SRC_TR}"
            echo "     [DRY] xmlchange: startup 2015-01-01, STOP_N=86, CO2=${CO2_2014} constant"
            echo "     [DRY] finidat = ${FINIDAT}"
            echo "     [DRY] Ndep stream years locked at 2014"
            echo "     [DRY] would sbatch wrapper with dep afterok:${DEP_JID}"
        fi
        echo ""
    done
done

echo "══════════════════════════════════════════════════════════════════"
if [[ $DRY_RUN -eq 1 ]]; then
    echo "  DRY RUN complete."
else
    echo "  Phase 4 setup complete."
    echo "  SLURM wrappers in: ${LOGDIR}/"
    echo "  Job log: ${JOBLOG}"
    echo ""
    echo "  Each wrapper submits the actual fixed run after its transient completes."
    echo "  Monitor: squeue -u braghiere"
    echo ""
    cat "${JOBLOG}"
fi
echo "══════════════════════════════════════════════════════════════════"
