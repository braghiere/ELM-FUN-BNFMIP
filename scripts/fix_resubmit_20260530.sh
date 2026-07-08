#!/bin/bash
# fix_resubmit_20260530.sh
#
# Root cause: The 3 nofun_baseline AD batch jobs (5395986/5395990/5395994) FAILED because
# their PBS scripts ran `./xmlchange BUILD_COMPLETE=FALSE && ./case.build`, triggering a
# re-build in the SHARED EXEROOT (nofun_man's build dir on Lustre) simultaneously from 3
# batch nodes → Fortran .mod0 file race condition.
#
# Fix:
#   1. Cancel all queued/DNS 20260530 jobs
#   2. Patch the 3 AD PBS scripts to skip the rebuild (builds are done in Section 2)
#   3. Mark BUILD_COMPLETE=TRUE in the 3 nofun AD case dirs
#   4. Re-submit all 12 experiment chains + 12 fixed-run wrappers

set -euo pipefail

# ── Config ─────────────────────────────────────────────────────────────────
DATE=20260530
OLMT=/home/braghiere/BNF_tom/OLMT_BNF
CASEROOT=${OLMT}/cime_case_dirs
LOGDIR=/home/braghiere/ELM-FUN-BNFMIP/logs

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

NF_MAN_AD=${CASEROOT}/nofun_baseline_manaus_${DATE}_BNF-Man_I1850CNRDCTCBC_ad_spinup
NF_HA1_AD=${CASEROOT}/nofun_baseline_ha1_${DATE}_BNF-Ha1_I1850CNRDCTCBC_ad_spinup
NF_BON_AD=${CASEROOT}/nofun_baseline_bon_${DATE}_BNF-Bon_I1850CNRDCTCBC_ad_spinup

FIXED_WRAP_DIR=${LOGDIR}/fixed_${DATE}

# ── Helper ──────────────────────────────────────────────────────────────────
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

# ── Step 1: Cancel all queued 20260530 jobs ─────────────────────────────────
echo "=== Step 1: Cancelling all queued 20260530 SLURM jobs ==="
# Get all queued job IDs (exclude the persisted bash session 5396139)
TO_CANCEL=$(squeue -u braghiere -h -o "%i" | grep -v "^5396139$" | tr '\n' ' ')
if [[ -n "${TO_CANCEL}" ]]; then
    echo "  Cancelling: ${TO_CANCEL}"
    echo "${TO_CANCEL}" | xargs scancel
    echo "  Done."
else
    echo "  No jobs to cancel."
fi
sleep 3

# ── Step 2: Patch the 3 nofun AD PBS scripts to skip rebuild ────────────────
echo ""
echo "=== Step 2: Patching nofun AD PBS scripts to skip rebuild ==="
# The builds completed in Section 2; these scripts must NOT re-trigger a build.
# All 3 nofun cases share the same EXEROOT (nofun_man's build dir), so running
# case.build from multiple batch nodes simultaneously causes a Lustre race condition.

for SCRIPT in \
    "${PBS_NF_MAN}/ad_spinup_group0.pbs" \
    "${PBS_NF_HA1}/ad_spinup_group0.pbs" \
    "${PBS_NF_BON}/ad_spinup_group0.pbs"; do

    # Remove BUILD_COMPLETE=FALSE line
    sed -i '/xmlchange BUILD_COMPLETE=FALSE/d' "${SCRIPT}"
    # Remove case.build line (with || exit 1)
    sed -i '/\.\/case\.build.*exit/d' "${SCRIPT}"
    echo "  Patched: ${SCRIPT}"
done

# ── Step 3: Mark BUILD_COMPLETE=TRUE in the 3 nofun AD case dirs ────────────
echo ""
echo "=== Step 3: Marking BUILD_COMPLETE=TRUE ==="
for CASEDIR in "${NF_MAN_AD}" "${NF_HA1_AD}" "${NF_BON_AD}"; do
    pushd "${CASEDIR}" > /dev/null
    ./xmlchange BUILD_COMPLETE=TRUE
    popd > /dev/null
    echo "  BUILD_COMPLETE=TRUE: ${CASEDIR}"
done

# ── Step 4: Re-submit all 12 chains ─────────────────────────────────────────
echo ""
echo "=== Step 4: Re-submitting all 12 experiment chains ==="

# ── nofun_baseline_manaus ────────────────────────────────────────────────────
echo "Submitting nofun_baseline_manaus chain..."
J=$(submit_one "nofun_man_AD"  "${PBS_NF_MAN}/ad_spinup_group0.pbs")
J=$(submit_one "nofun_man_ini" "${PBS_NF_MAN}/iniadjust_group0.pbs" "--dependency=afterok:${J}")
J=$(submit_one "nofun_man_FN"  "${PBS_NF_MAN}/fn_spinup_group0.pbs" "--dependency=afterok:${J}")
NF_MAN_FN_JID="${J}"
J=$(submit_one "nofun_man_TR"  "${PBS_NF_MAN}/transient_group0.pbs" "--dependency=afterok:${J}")
NF_MAN_TR_JID="${J}"

# ── nofun_baseline_ha1 ───────────────────────────────────────────────────────
echo "Submitting nofun_baseline_ha1 chain..."
J=$(submit_one "nofun_ha1_AD"  "${PBS_NF_HA1}/ad_spinup_group0.pbs")
J=$(submit_one "nofun_ha1_ini" "${PBS_NF_HA1}/iniadjust_group0.pbs" "--dependency=afterok:${J}")
J=$(submit_one "nofun_ha1_FN"  "${PBS_NF_HA1}/fn_spinup_group0.pbs" "--dependency=afterok:${J}")
NF_HA1_FN_JID="${J}"
J=$(submit_one "nofun_ha1_TR"  "${PBS_NF_HA1}/transient_group0.pbs" "--dependency=afterok:${J}")
NF_HA1_TR_JID="${J}"

# ── nofun_baseline_bon ───────────────────────────────────────────────────────
echo "Submitting nofun_baseline_bon chain..."
J=$(submit_one "nofun_bon_AD"  "${PBS_NF_BON}/ad_spinup_group0.pbs")
J=$(submit_one "nofun_bon_ini" "${PBS_NF_BON}/iniadjust_group0.pbs" "--dependency=afterok:${J}")
J=$(submit_one "nofun_bon_FN"  "${PBS_NF_BON}/fn_spinup_group0.pbs" "--dependency=afterok:${J}")
NF_BON_FN_JID="${J}"
J=$(submit_one "nofun_bon_TR"  "${PBS_NF_BON}/transient_group0.pbs" "--dependency=afterok:${J}")
NF_BON_TR_JID="${J}"

# ── fun_transient_only ───────────────────────────────────────────────────────
echo "Submitting fun_transient_only chains (funsp dep: nofun FN)..."
J=$(submit_one "fun_man_funsp" "${PBS_FUN_MAN}/fun_spinup_group0.pbs" "--dependency=afterok:${NF_MAN_FN_JID}")
J=$(submit_one "fun_man_TR"    "${PBS_FUN_MAN}/transient_group0.pbs"  "--dependency=afterok:${J}")
FUN_MAN_TR_JID="${J}"

J=$(submit_one "fun_ha1_funsp" "${PBS_FUN_HA1}/fun_spinup_group0.pbs" "--dependency=afterok:${NF_HA1_FN_JID}")
J=$(submit_one "fun_ha1_TR"    "${PBS_FUN_HA1}/transient_group0.pbs"  "--dependency=afterok:${J}")
FUN_HA1_TR_JID="${J}"

J=$(submit_one "fun_bon_funsp" "${PBS_FUN_BON}/fun_spinup_group0.pbs" "--dependency=afterok:${NF_BON_FN_JID}")
J=$(submit_one "fun_bon_TR"    "${PBS_FUN_BON}/transient_group0.pbs"  "--dependency=afterok:${J}")
FUN_BON_TR_JID="${J}"

# ── noacc_transient ──────────────────────────────────────────────────────────
echo "Submitting noacc_transient chains (funsp dep: nofun FN)..."
J=$(submit_one "noacc_man_funsp" "${PBS_NOACC_MAN}/fun_spinup_group0.pbs" "--dependency=afterok:${NF_MAN_FN_JID}")
J=$(submit_one "noacc_man_TR"    "${PBS_NOACC_MAN}/transient_group0.pbs"  "--dependency=afterok:${J}")
NOACC_MAN_TR_JID="${J}"

J=$(submit_one "noacc_ha1_funsp" "${PBS_NOACC_HA1}/fun_spinup_group0.pbs" "--dependency=afterok:${NF_HA1_FN_JID}")
J=$(submit_one "noacc_ha1_TR"    "${PBS_NOACC_HA1}/transient_group0.pbs"  "--dependency=afterok:${J}")
NOACC_HA1_TR_JID="${J}"

J=$(submit_one "noacc_bon_funsp" "${PBS_NOACC_BON}/fun_spinup_group0.pbs" "--dependency=afterok:${NF_BON_FN_JID}")
J=$(submit_one "noacc_bon_TR"    "${PBS_NOACC_BON}/transient_group0.pbs"  "--dependency=afterok:${J}")
NOACC_BON_TR_JID="${J}"

# ── acc_transient ────────────────────────────────────────────────────────────
echo "Submitting acc_transient chains (funsp dep: nofun FN)..."
J=$(submit_one "acc_man_funsp" "${PBS_ACC_MAN}/fun_spinup_group0.pbs" "--dependency=afterok:${NF_MAN_FN_JID}")
J=$(submit_one "acc_man_TR"    "${PBS_ACC_MAN}/transient_group0.pbs"  "--dependency=afterok:${J}")
ACC_MAN_TR_JID="${J}"

J=$(submit_one "acc_ha1_funsp" "${PBS_ACC_HA1}/fun_spinup_group0.pbs" "--dependency=afterok:${NF_HA1_FN_JID}")
J=$(submit_one "acc_ha1_TR"    "${PBS_ACC_HA1}/transient_group0.pbs"  "--dependency=afterok:${J}")
ACC_HA1_TR_JID="${J}"

J=$(submit_one "acc_bon_funsp" "${PBS_ACC_BON}/fun_spinup_group0.pbs" "--dependency=afterok:${NF_BON_FN_JID}")
J=$(submit_one "acc_bon_TR"    "${PBS_ACC_BON}/transient_group0.pbs"  "--dependency=afterok:${J}")
ACC_BON_TR_JID="${J}"

# ── Step 5: Re-submit 12 fixed-run wrappers ─────────────────────────────────
echo ""
echo "=== Step 5: Re-submitting 12 fixed-run wrappers ==="

declare -A FIXED_TR_DEP=(
    [nofun_baseline_manaus]="${NF_MAN_TR_JID}"
    [nofun_baseline_ha1]="${NF_HA1_TR_JID}"
    [nofun_baseline_bon]="${NF_BON_TR_JID}"
    [fun_transient_only_manaus]="${FUN_MAN_TR_JID}"
    [fun_transient_only_ha1]="${FUN_HA1_TR_JID}"
    [fun_transient_only_bon]="${FUN_BON_TR_JID}"
    [noacc_transient_manaus]="${NOACC_MAN_TR_JID}"
    [noacc_transient_ha1]="${NOACC_HA1_TR_JID}"
    [noacc_transient_bon]="${NOACC_BON_TR_JID}"
    [acc_transient_manaus]="${ACC_MAN_TR_JID}"
    [acc_transient_ha1]="${ACC_HA1_TR_JID}"
    [acc_transient_bon]="${ACC_BON_TR_JID}"
)

for KEY in "${!FIXED_TR_DEP[@]}"; do
    WRAPPER="${FIXED_WRAP_DIR}/submit_fixed_${KEY}.sh"
    DEP_JID="${FIXED_TR_DEP[$KEY]}"
    submit_one "fixed_${KEY}" "${WRAPPER}" "--dependency=afterok:${DEP_JID}"
done

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  ALL CHAINS RE-SUBMITTED                                     ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  Monitor: squeue -u braghiere --format='%.10i %.8P %.45j %.2t %.10M %R'"
echo ""
echo "  nofun FN JIDs (funsp starts after these):"
echo "    Man: ${NF_MAN_FN_JID}   Ha1: ${NF_HA1_FN_JID}   Bon: ${NF_BON_FN_JID}"
echo ""
echo "  Transient JIDs (fixed wrappers start after these):"
echo "    nofun:  Man=${NF_MAN_TR_JID}  Ha1=${NF_HA1_TR_JID}  Bon=${NF_BON_TR_JID}"
echo "    fun:    Man=${FUN_MAN_TR_JID}  Ha1=${FUN_HA1_TR_JID}  Bon=${FUN_BON_TR_JID}"
echo "    noacc:  Man=${NOACC_MAN_TR_JID}  Ha1=${NOACC_HA1_TR_JID}  Bon=${NOACC_BON_TR_JID}"
echo "    acc:    Man=${ACC_MAN_TR_JID}  Ha1=${ACC_HA1_TR_JID}  Bon=${ACC_BON_TR_JID}"
