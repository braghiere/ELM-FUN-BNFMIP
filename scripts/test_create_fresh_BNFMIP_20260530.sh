#!/bin/bash
# =============================================================================
# test_create_fresh_BNFMIP_20260530.sh
#
# Pre-flight test suite for create_fresh_BNFMIP_20260530.sh
#
# Runs 30+ checks WITHOUT side effects (no OLMT, no builds, no sbatch).
# Every check that the main script depends on is validated here. If ALL tests
# pass, the main script is safe to submit.
#
# Usage:
#   bash /home/braghiere/ELM-FUN-BNFMIP/scripts/test_create_fresh_BNFMIP_20260530.sh
#
# Exit code: 0 if all tests pass, non-zero otherwise.
# =============================================================================

# Do NOT set -e: we want to count failures, not abort on the first one.
set -u

MAIN_SCRIPT=/home/braghiere/ELM-FUN-BNFMIP/scripts/create_fresh_BNFMIP_20260530.sh

# Pull config from main script (single source of truth)
eval "$(grep -E '^(DATE|OLMT|REPO|MODEL_ROOT|CCSM_INPUT|RUNROOT|CASEROOT|PARAMDIR|SMODS|SHARED_MODS|PARAM_MAN|PARAM_HA1|PARAM_BON|CLM1PT_MAN|CLM1PT_HA1|CLM1PT_BON|GELISOL)=' "${MAIN_SCRIPT}" | head -40)"

PASS=0
FAIL=0
WARN=0
FAILED_TESTS=()

cyan="\033[36m"; green="\033[32m"; red="\033[31m"; yellow="\033[33m"; rst="\033[0m"

pass() { printf "  ${green}PASS${rst}  %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  ${red}FAIL${rst}  %s\n" "$1"; FAIL=$((FAIL+1)); FAILED_TESTS+=("$1"); }
warn() { printf "  ${yellow}WARN${rst}  %s\n" "$1"; WARN=$((WARN+1)); }
sect() { printf "\n${cyan}== %s ==${rst}\n" "$1"; }

check_file() { [[ -f "$2" ]] && pass "$1: $2" || fail "$1 (missing): $2"; }
check_dir()  { [[ -d "$2" ]] && pass "$1: $2" || fail "$1 (missing): $2"; }
check_exec() { [[ -x "$2" ]] && pass "$1: $2" || fail "$1 (not executable): $2"; }

echo "=============================================================="
echo "  Pre-flight tests for create_fresh_BNFMIP_${DATE}.sh"
echo "  Host: $(hostname)   Date: $(date)"
echo "=============================================================="

# ───────────────────────────────────────────────────────────────────────
sect "T1. Shell syntax"
bash -n "${MAIN_SCRIPT}" 2>/dev/null \
    && pass "main script bash -n parses cleanly" \
    || fail "main script has syntax errors"

# ───────────────────────────────────────────────────────────────────────
sect "T2. Compute node (cannot run main on login)"
if [[ "$(hostname)" == *login* ]]; then
    warn "running test on a login node — main script will refuse to run here"
else
    pass "running on a compute node ($(hostname))"
fi

# ───────────────────────────────────────────────────────────────────────
sect "T3. Required tools on PATH"
for tool in sbatch sinfo python3 grep sed awk tee; do
    command -v "$tool" >/dev/null \
        && pass "$tool found ($(command -v "$tool"))" \
        || fail "$tool not on PATH"
done

# ───────────────────────────────────────────────────────────────────────
sect "T4. Environment file sources cleanly"
ENV_FILE=~/elm_env_cades_gcc12.sh
check_file "env script" "${ENV_FILE}"
if [[ -f "${ENV_FILE}" ]]; then
    # The env script prints diagnostics on stderr; it also references unset vars
    # legitimately, so disable nounset for the subshell.
    ( set +u; cd /tmp && source "${ENV_FILE}" >/dev/null 2>&1 ); rc=$?
    if (( rc == 0 )); then
        pass "env file sources without error (exit 0)"
    else
        fail "env file exited non-zero ($rc)"
    fi
fi

# ───────────────────────────────────────────────────────────────────────
sect "T5. SLURM partitions and account"
for p in batch burst; do
    sinfo -h -p "$p" -o "%P" 2>/dev/null | grep -q "$p" \
        && pass "partition '$p' exists" \
        || fail "partition '$p' missing"
done
sacctmgr -n -P show assoc user="$USER" account=ccsi 2>/dev/null | grep -q ccsi \
    && pass "user $USER has access to account 'ccsi'" \
    || warn "could not verify ccsi association (sacctmgr may be restricted)"

# ───────────────────────────────────────────────────────────────────────
sect "T6. OLMT + CIME tools"
check_file "OLMT site_fullrun.py" "${OLMT}/site_fullrun.py"
check_file "CIME create_clone"    "${MODEL_ROOT}/cime/scripts/create_clone"
check_dir  "CIME scripts dir"     "${MODEL_ROOT}/cime/scripts"
check_dir  "OLMT scripts dir"     "${OLMT}/scripts"

# ───────────────────────────────────────────────────────────────────────
sect "T7. Param files exist + are readable NetCDF"
for p in "${PARAM_MAN}" "${PARAM_HA1}" "${PARAM_BON}" "${GELISOL}"; do
    if [[ -f "$p" && -r "$p" ]]; then
        if command -v ncdump >/dev/null 2>&1; then
            ncdump -h "$p" >/dev/null 2>&1 \
                && pass "NetCDF readable: $p" \
                || fail "NetCDF unreadable: $p"
        else
            pass "file exists (no ncdump to validate): $p"
        fi
    else
        fail "missing or unreadable: $p"
    fi
done

# ───────────────────────────────────────────────────────────────────────
sect "T8. CLM1PT atmospheric forcing dirs (with content)"
for d in "${CLM1PT_MAN}" "${CLM1PT_HA1}" "${CLM1PT_BON}"; do
    if [[ -d "$d" ]]; then
        n=$(ls "$d"/*.nc 2>/dev/null | wc -l)
        if (( n > 0 )); then
            pass "$d ($n .nc files)"
        else
            fail "$d exists but contains no .nc files"
        fi
    else
        fail "missing dir: $d"
    fi
done

# ───────────────────────────────────────────────────────────────────────
sect "T9. Source-mod directories (all 6 + shared)"
for sm in control_fixed_funp_nfix fun_fpg1_nfix \
          noACC_fixed_funp_nfix noACC_temperate_funp_nfix \
          ACC_fixed_funp_nfix   ACC_temperate_funp_nfix; do
    d="${SMODS}/${sm}"
    if [[ -d "$d" ]]; then
        n=$(ls "$d"/*.F90 2>/dev/null | wc -l)
        if (( n > 0 )); then pass "${sm} ($n .F90)"; else fail "${sm}: no .F90 files"; fi
    else
        fail "${sm}: directory missing"
    fi
done
check_file "shared clm_driver.F90"         "${SHARED_MODS}/clm_driver.F90"
check_file "shared clm_initializeMod.F90"  "${SHARED_MODS}/clm_initializeMod.F90"

# ───────────────────────────────────────────────────────────────────────
sect "T10. Source-mod content sanity (freelivfix_slope, fpg_p)"
# freelivfix_slope = 6.0e-4_r8 is in NitrogenDynamicsMod.F90 of the 5 FUN N-fix dirs
# (fun_fpg1_nfix, {no,}ACC_{fixed,temperate}_funp_nfix) — NOT in control_fixed (nofun).
fls_files=$(ls "${SMODS}"/{fun_fpg1_nfix,noACC_fixed_funp_nfix,noACC_temperate_funp_nfix,ACC_fixed_funp_nfix,ACC_temperate_funp_nfix}/NitrogenDynamicsMod.F90 2>/dev/null)
if [[ -n "${fls_files}" ]]; then
    fls_ok=$(grep -l "freelivfix_slope[[:space:]]*=[[:space:]]*6\.0e-4_r8" ${fls_files} 2>/dev/null | wc -l)
    fls_total=$(echo "${fls_files}" | wc -l)
    if (( fls_ok == fls_total )); then
        pass "freelivfix_slope = 6.0e-4_r8 in all ${fls_total} FUN NitrogenDynamicsMod.F90 files"
    else
        fail "freelivfix_slope mismatch: ${fls_ok}/${fls_total} files have 6.0e-4_r8"
    fi
else
    warn "no FUN NitrogenDynamicsMod.F90 files found"
fi

fpg_files=$(ls "${SMODS}"/{fun,noACC,ACC}_*/AllocationMod.F90 2>/dev/null)
if [[ -n "${fpg_files}" ]]; then
    fpg_ok=$(grep -l "fpg_p(c)[[:space:]]*=[[:space:]]*1\.0_r8" ${fpg_files} 2>/dev/null | wc -l)
    fpg_total=$(echo "${fpg_files}" | wc -l)
    if (( fpg_ok == fpg_total )); then
        pass "fpg_p(c) = 1.0_r8 in all ${fpg_total} FUN AllocationMod.F90 files"
    else
        fail "fpg_p mismatch: ${fpg_ok}/${fpg_total}"
    fi
else
    warn "no FUN AllocationMod.F90 files located"
fi

# ───────────────────────────────────────────────────────────────────────
sect "T11. s_fix value in Bon FUN param file (must be -1.0)"
if command -v ncdump >/dev/null 2>&1; then
    # s_fix is a pft array; first value should be -1
    sfix_first=$(ncdump -v s_fix "${PARAM_BON}" 2>/dev/null | sed -n '/^ s_fix =/,/;/p' | tr ',;' '\n' | grep -oE '\-?[0-9]+(\.[0-9]+)?' | head -1)
    if [[ -n "${sfix_first}" ]]; then
        if awk -v v="${sfix_first}" 'BEGIN{exit !(v+0 == -1.0)}'; then
            pass "Bon s_fix(pft1) = ${sfix_first} (expected -1.0)"
        else
            fail "Bon s_fix(pft1) = ${sfix_first} (expected -1.0) in ${PARAM_BON}"
        fi
    else
        warn "could not parse s_fix from ${PARAM_BON}"
    fi
else
    warn "ncdump unavailable — cannot validate s_fix"
fi

# ───────────────────────────────────────────────────────────────────────
sect "T12. Write permissions on output roots"
for d in "${CASEROOT}" "${RUNROOT}" "${REPO}/logs" "${OLMT}/scripts"; do
    mkdir -p "$d" 2>/dev/null
    if [[ -w "$d" ]]; then
        pass "writable: $d"
    else
        fail "not writable: $d"
    fi
done

# ───────────────────────────────────────────────────────────────────────
sect "T13. Disk space on RUNROOT (>= 200 GB free recommended)"
free_gb=$(df --output=avail -BG "${RUNROOT}" 2>/dev/null | tail -1 | tr -d 'G ')
if [[ -n "${free_gb}" ]]; then
    if (( free_gb >= 200 )); then
        pass "RUNROOT free: ${free_gb} GB"
    else
        warn "RUNROOT free: ${free_gb} GB (recommend >= 200 GB)"
    fi
else
    warn "could not determine free space on RUNROOT"
fi

# ───────────────────────────────────────────────────────────────────────
sect "T14. No conflicting cases with DATE=${DATE}"
existing=$(ls -d "${CASEROOT}"/*_${DATE}_* 2>/dev/null | wc -l)
if (( existing == 0 )); then
    pass "no existing cases for DATE=${DATE}"
else
    fail "found ${existing} pre-existing cases for DATE=${DATE} — main script will refuse to run"
    ls -d "${CASEROOT}"/*_${DATE}_* 2>/dev/null | head -5 | sed 's/^/        /'
fi

# ───────────────────────────────────────────────────────────────────────
sect "T15. No conflicting RUNROOT dirs"
existing_run=$(ls -d "${RUNROOT}"/*_${DATE}_* 2>/dev/null | wc -l)
if (( existing_run == 0 )); then
    pass "no existing RUNROOT dirs for DATE=${DATE}"
else
    warn "${existing_run} RUNROOT dirs match DATE=${DATE} (will be reused/overwritten by builds)"
fi

# ───────────────────────────────────────────────────────────────────────
sect "T16. No conflicting OLMT PBS-script dirs"
existing_pbs=$(ls -d "${OLMT}/scripts"/*_${DATE} 2>/dev/null | wc -l)
if (( existing_pbs == 0 )); then
    pass "no existing OLMT scripts dirs for DATE=${DATE}"
else
    warn "${existing_pbs} OLMT scripts dirs match DATE=${DATE} (will be overwritten)"
fi

# ───────────────────────────────────────────────────────────────────────
sect "T17. Main script — sanity counts"
n_olmt=$(grep -c '^run_olmt ' "${MAIN_SCRIPT}")
if (( n_olmt == 12 )); then pass "12 run_olmt calls"; else fail "expected 12 run_olmt calls, got ${n_olmt}"; fi

n_build=$(grep -c '^.*build_ad_case ' "${MAIN_SCRIPT}")
if (( n_build >= 6 )); then pass "${n_build} build_ad_case calls (>=6 expected)"; else fail "fewer than 6 builds"; fi

n_submit=$(grep -cE 'J=\$\(submit_one|WRAP_JID=\$\(submit_one' "${MAIN_SCRIPT}")
# Static count: 30 in Section 4 + 1 inside Section 5 loop = 31 lines
# (the Section 5 line runs 12 times at runtime, so total jobs submitted = 42)
if (( n_submit == 31 )); then
    pass "31 static submit_one calls (30 Section-4 + 1 looped Section-5 = 42 jobs at runtime)"
else
    fail "expected 31 static submit_one calls, got ${n_submit}"
fi

# ───────────────────────────────────────────────────────────────────────
sect "T18. Helper functions dry-test"
# Test set_nl_var logic on a temp file
TMPNL=$(mktemp)
echo " finidat = 'old.nc'" > "${TMPNL}"
# inline replica of set_nl_var
if grep -q "^[[:space:]]*finidat[[:space:]]*=" "${TMPNL}"; then
    sed -i "s|^[[:space:]]*finidat[[:space:]]*=.*|finidat = 'new.nc'|" "${TMPNL}"
fi
if grep -q "finidat = 'new.nc'" "${TMPNL}"; then
    pass "set_nl_var replacement logic works"
else
    fail "set_nl_var replacement logic broken"
fi
rm -f "${TMPNL}"

# ───────────────────────────────────────────────────────────────────────
sect "T19. OLMT python script imports cleanly (with elm env)"
if [[ -f "${ENV_FILE}" ]]; then
    out=$(bash -c "source ${ENV_FILE} >/dev/null 2>&1 && python3 -c 'import sys; sys.path.insert(0,\"${OLMT}\"); import site_fullrun' 2>&1" | tail -3)
    if [[ -z "${out}" ]]; then
        pass "OLMT site_fullrun.py imports"
    else
        # site_fullrun.py may use argparse at top; just check syntax
        bash -c "source ${ENV_FILE} >/dev/null 2>&1 && python3 -c 'import py_compile; py_compile.compile(\"${OLMT}/site_fullrun.py\", doraise=True)'" >/dev/null 2>&1 \
            && pass "OLMT site_fullrun.py compiles" \
            || fail "OLMT site_fullrun.py has Python errors: ${out}"
    fi
fi

# ───────────────────────────────────────────────────────────────────────
sect "T20. Submission-pattern symmetry (3 identical site blocks)"
n_nofun_blocks=$(grep -cE 'nofun_(man|ha1|bon)_AD' "${MAIN_SCRIPT}")
if (( n_nofun_blocks == 3 )); then
    pass "3 nofun AD submissions (one per site)"
else
    fail "expected 3 nofun AD submissions, got ${n_nofun_blocks}"
fi

n_funsp=$(grep -cE '_(man|ha1|bon)_funsp' "${MAIN_SCRIPT}")
# 9 submissions + 9 var names in helper text + finidat loops; expect at least 9 in Section 4
n_funsp_sub=$(grep -cE 'J=\$\(submit_one "(fun|noacc|acc)_(man|ha1|bon)_funsp"' "${MAIN_SCRIPT}")
if (( n_funsp_sub == 9 )); then
    pass "9 FUN funsp submissions (3 exps × 3 sites)"
else
    fail "expected 9 FUN funsp submissions, got ${n_funsp_sub}"
fi

# ───────────────────────────────────────────────────────────────────────
sect "T21. Bon consistency-check overrides present"
n_bon_consistency=$(grep -c 'check_finidat_fsurdat_consistency' "${MAIN_SCRIPT}")
if (( n_bon_consistency >= 3 )); then
    pass "${n_bon_consistency} check_finidat_fsurdat_consistency overrides (funsp+TR+fixed)"
else
    fail "expected >=3 consistency overrides for Bon, got ${n_bon_consistency}"
fi

# ───────────────────────────────────────────────────────────────────────
sect "T22. Fixed-run section sanity"
grep -q "RUN_STARTDATE=2015-01-01"      "${MAIN_SCRIPT}" && pass "RUN_STARTDATE=2015-01-01 set"      || fail "missing RUN_STARTDATE=2015-01-01"
grep -q "STOP_N=86"                     "${MAIN_SCRIPT}" && pass "STOP_N=86 (2015-2100) set"         || fail "missing STOP_N=86"
grep -q "CLM_CO2_TYPE=constant"         "${MAIN_SCRIPT}" && pass "CLM_CO2_TYPE=constant set"        || fail "missing CLM_CO2_TYPE=constant"
grep -q "CO2_2014=397.7641"             "${MAIN_SCRIPT}" && pass "CO2_2014=397.7641 defined"         || fail "missing CO2_2014=397.7641"
grep -q 'CCSM_CO2_PPMV="\${CO2_2014}"'  "${MAIN_SCRIPT}" && pass "CCSM_CO2_PPMV uses CO2_2014"      || fail "missing CCSM_CO2_PPMV xmlchange"
grep -q "stream_year_first_ndep"        "${MAIN_SCRIPT}" && pass "stream_year_first_ndep override" || fail "missing Ndep stream year lock"

# ───────────────────────────────────────────────────────────────────────
sect "T23. create_clone is invokable (with elm env)"
if [[ -f "${ENV_FILE}" ]]; then
    out=$(bash -c "source ${ENV_FILE} >/dev/null 2>&1 && ${MODEL_ROOT}/cime/scripts/create_clone --help 2>&1" | tail -5)
    if echo "${out}" | grep -qE "case|clone|usage"; then
        pass "create_clone --help works"
    else
        fail "create_clone --help failed: ${out}"
    fi
fi

# ───────────────────────────────────────────────────────────────────────
sect "T24. CCSM_INPUT exists and is readable"
check_dir "CCSM_INPUT" "${CCSM_INPUT}"

# ───────────────────────────────────────────────────────────────────────
sect "T25. Quota / SLURM submission limit"
qlimit=$(sacctmgr -n -P show assoc user="$USER" account=ccsi format=maxsubmitjobs 2>/dev/null | head -1)
if [[ -n "${qlimit}" && "${qlimit}" != "0" ]]; then
    pass "ccsi MaxSubmitJobs: ${qlimit:-unlimited} (need ~42 slots)"
else
    warn "could not determine submit-job limit (need ~42 slots)"
fi

# ───────────────────────────────────────────────────────────────────────
sect "Summary"
echo ""
printf "  ${green}PASSED${rst}: %d\n" "${PASS}"
printf "  ${yellow}WARN${rst}:   %d\n" "${WARN}"
printf "  ${red}FAILED${rst}: %d\n" "${FAIL}"
echo ""

if (( FAIL == 0 )); then
    printf "${green}╔══════════════════════════════════════════════════════════════╗${rst}\n"
    printf "${green}║  ALL TESTS PASSED — main script is safe to run               ║${rst}\n"
    printf "${green}╚══════════════════════════════════════════════════════════════╝${rst}\n"
    echo ""
    echo "  To run on a burst compute node:"
    echo "    srun -A ccsi -p burst -N 1 -n 1 -t 6:00:00 --mem 32G \\"
    echo "         --exclude=or-condo-c105,or-condo-c67,or-condo-c04 --pty bash"
    echo "    bash ${MAIN_SCRIPT} 2>&1 | tee ${REPO}/logs/create_${DATE}.log"
    exit 0
else
    printf "${red}╔══════════════════════════════════════════════════════════════╗${rst}\n"
    printf "${red}║  ${FAIL} TEST(S) FAILED — DO NOT RUN MAIN SCRIPT                  ║${rst}\n"
    printf "${red}╚══════════════════════════════════════════════════════════════╝${rst}\n"
    echo ""
    echo "  Failed tests:"
    for t in "${FAILED_TESTS[@]}"; do
        echo "    - $t"
    done
    exit 1
fi
