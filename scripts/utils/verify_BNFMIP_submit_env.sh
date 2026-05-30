#!/bin/bash
# verify_BNFMIP_submit_env.sh — quick checks before submit_all_BNFMIP_experiments.sh
# Exit 0 if ready; non-zero if something required is missing.
set -e
ERR=0

export PTCLM_DIR="${PTCLM_DIR:-/home/braghiere/BNF_tom/OLMT_BNF/PTCLM}"
CCSM_INPUT="${CCSM_INPUT:-/lustre/or-scratch/cades-ccsi/proj-shared/project_acme/e3sm_inputdata}"

echo "══════════════════════════════════════════════════════════════════"
echo " BNFMIP submit — environment verification"
echo "══════════════════════════════════════════════════════════════════"

echo ""
echo "== PTCLM_DIR = ${PTCLM_DIR}"
for f in BNF_sitedata.txt BNF_pftdata.txt BNF_soildata.txt; do
  if [[ -f "${PTCLM_DIR}/${f}" ]]; then
    echo "  OK  ${f}"
  else
    echo "  MISSING ${f}" >&2
    ERR=1
  fi
done

echo ""
echo "== CCSM_INPUT (E3SM DIN_LOC_ROOT) = ${CCSM_INPUT}"
if timeout 15 bash -c "[[ -d '${CCSM_INPUT}' ]]"; then
  echo "  OK  directory exists and is reachable (within 15s)"
  if [[ -d "${CCSM_INPUT}/lnd/clm2" ]]; then
    echo "  OK  lnd/clm2 present"
  else
    echo "  WARN  no lnd/clm2 — tree may be incomplete for full case setup" >&2
  fi
else
  echo "  FAIL  directory missing or NFS hung — use login node or export CCSM_INPUT" >&2
  ERR=1
fi

echo ""
echo "== submit_all_BNFMIP_experiments.sh (compute node, not login)"
if [[ "$(hostname)" == *login* ]]; then
  echo "  WARN  hostname matches *login* — submit script will refuse to run" >&2
  ERR=1
else
  echo "  OK  hostname: $(hostname)"
fi

echo ""
echo "== SOIL10 / col_es wiring (SourceMods overlay — not E3SM_global_silent base)"
SHARED=/home/braghiere/BNF_tom/OLMT_BNF/cime_case_dirs/source_codes/_shared_elm_fun_col_es
if grep -q 'call col_es%InitAccBuffer' "${SHARED}/clm_initializeMod.F90" 2>/dev/null; then
  echo "  OK  _shared_elm_fun_col_es/clm_initializeMod: col_es%InitAccBuffer"
else
  echo "  MISSING col_es calls in ${SHARED}/clm_initializeMod.F90" >&2
  ERR=1
fi
if grep -q 'call col_es%UpdateAccVars' "${SHARED}/clm_driver.F90" 2>/dev/null; then
  echo "  OK  _shared_elm_fun_col_es/clm_driver: col_es%UpdateAccVars"
else
  echo "  MISSING col_es%UpdateAccVars in ${SHARED}/clm_driver.F90" >&2
  ERR=1
fi
if grep -q 'call col_es%InitAccBuffer' /home/braghiere/BNF_tom/E3SM_global_silent/components/clm/src/main/clm_initializeMod.F90 2>/dev/null; then
  echo "  WARN  E3SM_global_silent base still has col_es calls — should be reverted (use SourceMods only)" >&2
  ERR=1
fi

echo ""
echo "== ColumnDataType (canonical src.clm)"
if grep -q 'init_acc_buffer_col_es' /home/braghiere/BNF_tom/src.clm/ColumnDataType.F90; then
  echo "  OK  init_acc_buffer_col_es in BNF_tom/src.clm/ColumnDataType.F90"
else
  echo "  MISSING init_acc_buffer_col_es" >&2
  ERR=1
fi

echo ""
echo "== Bash syntax: submit_all_BNFMIP_experiments.sh"
if bash -n /home/braghiere/BNF_tom/OLMT_BNF/submit_all_BNFMIP_experiments.sh; then
  echo "  OK  bash -n"
else
  ERR=1
fi

echo "══════════════════════════════════════════════════════════════════"
if [[ $ERR -eq 0 ]]; then
  echo " RESULT: all automated checks passed."
else
  echo " RESULT: fix items above before: bash submit_all_BNFMIP_experiments.sh" >&2
fi
echo "══════════════════════════════════════════════════════════════════"
exit $ERR
