#!/bin/bash
# resubmit_missing6.sh
# Fix: remove stale rpointers and resubmit 6 failed transient runs,
# then queue fixed-case wrappers as dependencies.
#
# All 6 failures had the same cause: CONTINUE_RUN=FALSE + existing rpointers
# pointing to a completed previous run. Finidat files confirmed present.

set -e

SCRATCH=/lustre/or-scratch/cades-ccsi/scratch/braghiere
CDIR=/home/braghiere/BNF_tom/OLMT_BNF/cime_case_dirs
WDIR=/home/braghiere/BNF_tom/OLMT_BNF/bnfmip_phase4_20260529_0313
LOGDIR=/home/braghiere/BNF_tom/OLMT_BNF/bnfmip_missing6_$(date +%Y%m%d_%H%M)
mkdir -p ${LOGDIR}

echo "Log dir: ${LOGDIR}"
echo ""

# Arrays: parallel lists of transient case names and corresponding wrapper scripts
TRANS_CASES=(
  "fun_transient_only_manaus_20260521_BNF-Man_I20TRCNPRDCTCBC"
  "noacc_transient_ha1_20260521_BNF-Ha1_I20TRCNPRDCTCBC"
  "nofun_baseline_manaus_20260521_BNF-Man_I20TRCNPRDCTCBC"
  "nofun_baseline_ha1_20260521_BNF-Ha1_I20TRCNPRDCTCBC"
  "acc_transient_manaus_20260521_BNF-Man_I20TRCNPRDCTCBC"
  "acc_transient_bon_20260521_BNF-Bon_I20TRCNPRDCTCBC"
)

WRAPPER_SCRIPTS=(
  "submit_fixed_fun_transient_only_manaus.sh"
  "submit_fixed_noacc_transient_ha1.sh"
  "submit_fixed_nofun_baseline_manaus.sh"
  "submit_fixed_nofun_baseline_ha1.sh"
  "submit_fixed_acc_transient_manaus.sh"
  "submit_fixed_acc_transient_bon.sh"
)

TOTAL=${#TRANS_CASES[@]}

for (( i=0; i<TOTAL; i++ )); do
  CASE="${TRANS_CASES[$i]}"
  WRAPPER="${WRAPPER_SCRIPTS[$i]}"
  RUNDIR="${SCRATCH}/${CASE}/run"
  CASEDIR="${CDIR}/${CASE}"

  echo "=============================="
  echo "Case: ${CASE}"

  # --- 1. Verify finidat exists ---
  FINIDAT=$(grep "^[[:space:]]*finidat" ${CASEDIR}/user_nl_clm | grep -o "'[^']*'" | tr -d "'")
  if [[ ! -f "${FINIDAT}" ]]; then
    echo "  ERROR: finidat not found: ${FINIDAT}"
    echo "  Skipping ${CASE}"
    continue
  fi
  echo "  finidat OK: ${FINIDAT##*/}"

  # --- 2. Remove stale rpointers ---
  echo "  Removing stale rpointers..."
  rm -f "${RUNDIR}/rpointer.lnd" "${RUNDIR}/rpointer.atm" "${RUNDIR}/rpointer.drv"

  # --- 3. Submit transient via case.submit ---
  echo "  Submitting transient..."
  SUBMIT_OUT=$(cd "${CASEDIR}" && ./case.submit 2>&1)
  JOB_ID=$(echo "${SUBMIT_OUT}" | grep -oP '(?<=job )\d+' | tail -1)
  if [[ -z "${JOB_ID}" ]]; then
    # Try alternate pattern: "Submitted batch job NNNNN"
    JOB_ID=$(echo "${SUBMIT_OUT}" | grep -oP '(?<=Submitted batch job )\d+' | tail -1)
  fi

  if [[ -z "${JOB_ID}" ]]; then
    echo "  ERROR: Could not extract job ID from case.submit output:"
    echo "${SUBMIT_OUT}" | tail -10
    echo "  Skipping wrapper for ${CASE}"
    continue
  fi
  echo "  Transient job: ${JOB_ID}"

  # --- 4. Submit fixed-case wrapper with dependency ---
  echo "  Queuing fixed-case wrapper (after ${JOB_ID})..."
  WRAP_ID=$(sbatch --dependency=afterok:${JOB_ID} "${WDIR}/${WRAPPER}" 2>&1 | awk '{print $NF}')
  echo "  Fixed wrapper job: ${WRAP_ID}"

  echo "${CASE}: transient=${JOB_ID} wrapper=${WRAP_ID}" >> "${LOGDIR}/job_ids.log"
  echo ""
done

echo "=============================="
echo "All done. Summary:"
cat "${LOGDIR}/job_ids.log"
echo ""
echo "Monitor with: squeue -u braghiere"
