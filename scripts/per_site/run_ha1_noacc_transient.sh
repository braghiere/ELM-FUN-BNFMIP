#!/bin/bash
# Harvard Forest (BNF-Ha1) noACC Nfixation transient-only experiment (Exp 4):
#   Reuses nofun_baseline AD+FN spinup (600yr, FUN/FUNP OFF).
#   Builds new exe with noACC_fixed_funp_nfix SourceMods.
#   Runs ONLY the transient (1851-2100) with FUN+FUNP ON + noACC Nfixation.
#
# SourceMods: noACC_fixed_funp_nfix
#   - Bytnerowicz Nfixation temperature response WITHOUT acclimation:
#     Tmin_fix = -2.04 C, Topt_fix = 32.10 C, Tmax_fix = 43.98 C  (temperate params)
#   - fun_cost_fix_Bytnerowicz_noAcc() is active
#   - fpg_p = 1.0 guard when use_funp=TRUE
#
# Soil: US-Ha1 Inceptisol CNP_parameters passed via --mod_parm_file_P
#
# USAGE:
#   bash run_ha1_noacc_transient.sh <NOFUN_CASEID>
set -e

# ── Safety ──
if [[ "$(hostname)" == *login* ]]; then
  echo "ERROR: This script must run on a compute node, not $(hostname)!"
  exit 1
fi
if [[ -z "$1" ]]; then
  echo "ERROR: Missing NOFUN_CASEID argument."
  echo "USAGE: bash $0 <NOFUN_CASEID>"
  exit 1
fi
NOFUN_CASEID="$1"

source ~/elm_env_cades_gcc12.sh

OLMT=/home/braghiere/BNF_tom/OLMT_BNF
MODEL_ROOT=/home/braghiere/BNF_tom/E3SM_global_silent
CCSM_INPUT="${CCSM_INPUT:-/lustre/or-scratch/cades-ccsi/proj-shared/project_acme/e3sm_inputdata}"
RUNROOT=/lustre/or-scratch/cades-ccsi/scratch/braghiere
CASEROOT=/home/braghiere/BNF_tom/OLMT_BNF/cime_case_dirs
CLM_PARAMFILE=/home/braghiere/BNF_tom/clm_params_fun3_sfix6.nc
CNP_FILE=/home/braghiere/BNF_tom/OLMT_BNF/define_site_files/US-Ha1/CNP_parameters.nc
CLM1PT_DIR=/home/braghiere/BNF_tom/inputdata/BNFMIP_forcing_from_OCN/BNF_Har/CLM1PT_data
CASEID=noacc_transient_ha1_$(date +%Y%m%d)
SITE=BNF-Ha1
SOURCEMODS=${CASEROOT}/source_codes/noACC_temperate_funp_nfix

AD_CASE=${CASEROOT}/${CASEID}_${SITE}_I1850CNRDCTCBC_ad_spinup
FN_CASE=${CASEROOT}/${CASEID}_${SITE}_I1850CNPRDCTCBC
TR_CASE=${CASEROOT}/${CASEID}_${SITE}_I20TRCNPRDCTCBC

NOFUN_FN_RUNDIR=${RUNROOT}/${NOFUN_CASEID}_${SITE}_I1850CNPRDCTCBC
NOFUN_FN_RESTART=${NOFUN_FN_RUNDIR}/run/${NOFUN_CASEID}_${SITE}_I1850CNPRDCTCBC.clm2.r.0751-01-01-00000.nc

echo "=== Verifying nofun_baseline restart ==="
if [ ! -f "${NOFUN_FN_RESTART}" ]; then
  echo "ERROR: nofun_baseline FN restart not found:"
  echo "  ${NOFUN_FN_RESTART}"
  exit 1
fi
echo "  Found: $(basename ${NOFUN_FN_RESTART})"

echo ""
echo "=== Cleaning up ${CASEID}_${SITE}_* cases ==="
for suffix in _I1850CNRDCTCBC_ad_spinup _I1850CNRDCTCBC _I1850CNPRDCTCBC _I20TRCNPRDCTCBC; do
  d=${CASEROOT}/${CASEID}_${SITE}${suffix}
  [ -d "$d" ] && rm -rf "$d" && echo "  Removed $d"
  r=${RUNROOT}/${CASEID}_${SITE}${suffix}
  [ -d "$r" ] && rm -rf "$r" && echo "  Removed $r"
done

cd ${OLMT}

echo ""
echo "=== Step 1: OLMT creates cases ==="
python3 site_fullrun.py \
    --site ${SITE} --sitegroup BNF --machine cades \
    --caseidprefix ${CASEID} \
    --model_root ${MODEL_ROOT} --ccsm_input ${CCSM_INPUT} \
    --runroot ${RUNROOT} --caseroot ${CASEROOT} \
    --mpilib openmpi --np 1 --walltime 24 --nofire \
    --clm_paramfile ${CLM_PARAMFILE} \
    --mod_parm_file_P ${CNP_FILE} \
    --clm1pt_dir ${CLM1PT_DIR} \
    --nyears_ad_spinup 200 --nyears_final_spinup 600 \
    --batch_build \
    --no_submit

echo ""
echo "=== Step 2: Copy SourceMods (noACC_fixed_funp_nfix) and build exe ==="
mkdir -p ${AD_CASE}/SourceMods/src.clm
cp ${SOURCEMODS}/*.F90 ${AD_CASE}/SourceMods/src.clm/
if [[ -d ${CASEROOT}/source_codes/_shared_elm_fun_col_es ]]; then
  cp ${CASEROOT}/source_codes/_shared_elm_fun_col_es/*.F90 ${AD_CASE}/SourceMods/src.clm/
fi
echo "  Copied $(ls ${AD_CASE}/SourceMods/src.clm/*.F90 | wc -l) SourceMod files"
cd ${AD_CASE}
./case.build 2>&1 | tee build_noacc_transient_ha1.log
EXEROOT=${RUNROOT}/${CASEID}_${SITE}_I1850CNRDCTCBC_ad_spinup/bld
if [ ! -f "${EXEROOT}/e3sm.exe" ]; then
  echo "ERROR: Build FAILED. Check ${AD_CASE}/build_noacc_transient_ha1.log"
  exit 1
fi
echo "  exe built: ${EXEROOT}/e3sm.exe"

echo ""
echo "=== Step 3: Set BUILD_COMPLETE on FN and transient cases ==="
for casedir in ${FN_CASE} ${TR_CASE}; do
  if [ -d "$casedir" ]; then
    cd "$casedir"
    ./xmlchange BUILD_COMPLETE=TRUE
    ./xmlchange EXEROOT=${EXEROOT}
    echo "  $(basename $casedir): BUILD_COMPLETE=TRUE, EXEROOT set"
  else
    echo "  ERROR: $casedir not found" >&2; exit 1
  fi
done

echo ""
echo "=== Step 4: Configure transient (FUN+FUNP ON, finidat → nofun_baseline yr 751) ==="
cd ${TR_CASE}

sed -i 's/use_fun = .false./use_fun = .true./' user_nl_clm
sed -i 's/use_funp = .false./use_funp = .true./' user_nl_clm
grep -q 'use_fun'  user_nl_clm || echo 'use_fun  = .true.' >> user_nl_clm
grep -q 'use_funp' user_nl_clm || echo 'use_funp = .true.' >> user_nl_clm

sed -i "s|finidat = .*|finidat = '${NOFUN_FN_RESTART}'|" user_nl_clm
./xmlchange RUN_REFDATE=0751-01-01
./preview_namelists 2>&1 | tail -3

if grep -q 'use_fun = .true.' user_nl_clm && grep -q 'use_funp = .true.' user_nl_clm; then
  echo "  transient: FUN/FUNP ON confirmed"
else
  echo "ERROR: FUN/FUNP not enabled in transient" >&2; exit 1
fi
echo "  transient: finidat → ${NOFUN_CASEID} yr 751 restart"

PBSDIR=${OLMT}/scripts/${CASEID}
echo ""
echo "=== Step 5: Patching transient PBS script ==="
if [ -d "$PBSDIR" ]; then
  TR_PBS="${PBSDIR}/transient_group0.pbs"
  if [ -f "${TR_PBS}" ]; then
    if ! grep -q "exclude" "${TR_PBS}"; then
      sed -i '/#SBATCH  --nodes=1/a #SBATCH  --exclude=or-condo-c105,or-condo-c67,or-condo-c04' "${TR_PBS}"
      echo "  transient_group0.pbs: added --exclude"
    else
      echo "  transient_group0.pbs: already patched"
    fi
  fi
fi

cd ${OLMT}
echo ""
echo "=== Step 6: Submitting transient case only ==="
TR_PBS="${PBSDIR}/transient_group0.pbs"
if [ ! -f "${TR_PBS}" ]; then
  echo "ERROR: Transient PBS script not found: ${TR_PBS}" >&2; exit 1
fi

out=$(sbatch "${TR_PBS}" 2>&1)
rc=$?
if [ $rc -ne 0 ] || ! echo "$out" | grep -q 'Submitted batch job'; then
  echo "ERROR: Failed to submit transient: $out" >&2; exit 1
fi
JID=$(echo "$out" | awk '{print $4}')

echo ""
echo "════════════════════════════════════════════════════════════"
echo "=== TRANSIENT JOB SUBMITTED (Ha1 Exp 4) ==="
echo "CASEID:         ${CASEID}"
echo "Job ID:         ${JID}"
echo "SourceMods:     noACC_fixed_funp_nfix (Bytnerowicz, temperate params)"
echo "Param file:     ${CLM_PARAMFILE}"
echo "CNP file:       ${CNP_FILE}"
echo "Spinup reused:  ${NOFUN_CASEID}  (nofun_baseline FN spinup yr 751)"
echo "Nfixation:      Bytnerowicz noACC  Tmin=-2.04 Topt=32.10 Tmax=43.98"
echo "Transient:      1851-2100, FUN+FUNP ON"
echo "Monitor with:   squeue -u \$USER"
echo "════════════════════════════════════════════════════════════"
