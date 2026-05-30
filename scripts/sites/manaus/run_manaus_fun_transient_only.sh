#!/bin/bash
# Manaus FUN+FUNP transient-only experiment (Exp 3):
#   Reuses nofun_baseline AD+FN spinup (600yr, FUN/FUNP OFF).
#   Builds new exe with fun_fpg1_nfix SourceMods.
#   Runs ONLY the transient (1850-2101) with FUN+FUNP ON.
#
# SourceMods: fun_fpg1_nfix
#   - fpg(c)   = 1.0 when use_fun=TRUE  (diagnostic fix)
#   - fpg_p(c) = 1.0 when use_funp=TRUE (diagnostic fix)
#   - Houlton s_fix=-0.1 (from paramfile, not modified here)
#
# USAGE:
#   bash run_manaus_fun_transient_only.sh <NOFUN_CASEID>
#   where NOFUN_CASEID is the CASEID used by run_manaus_nofun_baseline.sh
#   e.g.: bash run_manaus_fun_transient_only.sh nofun_baseline_manaus_20241210
#
# Run on a compute node:
#   srun -A ccsi -p burst -N 1 -n 1 -t 4:00:00 --mem 32G \
#        --exclude=or-condo-c105,or-condo-c67 --pty bash
#   cd /home/braghiere/BNF_tom/OLMT_BNF && bash run_manaus_fun_transient_only.sh <NOFUN_CASEID>
set -e

# ── Safety: abort if on a login node ──
if [[ "$(hostname)" == *login* ]]; then
  echo "ERROR: This script must run on a compute node, not $(hostname)!"
  exit 1
fi

# ── Require NOFUN_CASEID argument ──
if [[ -z "$1" ]]; then
  echo "ERROR: Missing NOFUN_CASEID argument."
  echo "USAGE: bash $0 <NOFUN_CASEID>"
  echo "  e.g.: bash $0 nofun_baseline_manaus_20241210"
  exit 1
fi
NOFUN_CASEID="$1"

source ~/elm_env_cades_gcc12.sh

OLMT=/home/braghiere/BNF_tom/OLMT_BNF
MODEL_ROOT=/home/braghiere/BNF_tom/E3SM_global_silent
CCSM_INPUT="${CCSM_INPUT:-/lustre/or-scratch/cades-ccsi/proj-shared/project_acme/e3sm_inputdata}"
RUNROOT=/lustre/or-scratch/cades-ccsi/scratch/braghiere
CASEROOT=/home/braghiere/BNF_tom/OLMT_BNF/cime_case_dirs
CLM_PARAMFILE=/home/braghiere/BNF_tom/clm_params_fun3_sfix6_manaus_tuned.nc
CNP_SOILORDERFILE=${CNP_SOILORDERFILE_OVERRIDE:-/home/braghiere/BNF_tom/CNP_parameters_manaus_oxisol.nc}
CLM1PT_DIR=/home/braghiere/BNF_tom/inputdata/BNFMIP_forcing_from_OCN/BNF_Man/CLM1PT_data
CASEID=fun_transient_only_manaus_$(date +%Y%m%d)
SITE=BNF-Man
SOURCEMODS=${CASEROOT}/source_codes/fun_fpg1_nfix

# Derived case directories for THIS experiment
AD_CASE=${CASEROOT}/${CASEID}_${SITE}_I1850CNRDCTCBC_ad_spinup
FN_CASE=${CASEROOT}/${CASEID}_${SITE}_I1850CNPRDCTCBC
TR_CASE=${CASEROOT}/${CASEID}_${SITE}_I20TRCNPRDCTCBC

# Finidat: yr 751 restart from the nofun_baseline FN spinup
NOFUN_FN_RUNDIR=${RUNROOT}/${NOFUN_CASEID}_${SITE}_I1850CNPRDCTCBC
NOFUN_FN_RESTART=${NOFUN_FN_RUNDIR}/run/${NOFUN_CASEID}_${SITE}_I1850CNPRDCTCBC.clm2.r.0751-01-01-00000.nc

# ── Verify the nofun_baseline restart exists ──
echo "=== Verifying nofun_baseline restart ==="
if [ ! -f "${NOFUN_FN_RESTART}" ]; then
  echo "ERROR: nofun_baseline FN restart not found:"
  echo "  ${NOFUN_FN_RESTART}"
  echo "Make sure run_manaus_nofun_baseline.sh has completed successfully."
  exit 1
fi
echo "  Found: $(basename ${NOFUN_FN_RESTART})"

# ── Clean up any existing cases with today's CASEID ──
echo ""
echo "=== Cleaning up ${CASEID}_${SITE}_* cases ==="
for suffix in _I1850CNRDCTCBC_ad_spinup _I1850CNRDCTCBC _I1850CNPRDCTCBC _I20TRCNPRDCTCBC; do
  d=${CASEROOT}/${CASEID}_${SITE}${suffix}
  [ -d "$d" ] && rm -rf "$d" && echo "  Removed $d"
  r=${RUNROOT}/${CASEID}_${SITE}${suffix}
  [ -d "$r" ] && rm -rf "$r" && echo "  Removed $r"
done

cd ${OLMT}

# ══════════════════════════════════════════════════════════════════════
# Step 1: Create case directories (all 3, no build, no submit)
#   We only intend to run the transient. AD case is only used for building exe.
#   FN case is created but NOT submitted (we reuse nofun_baseline FN spinup).
# ══════════════════════════════════════════════════════════════════════
echo ""
echo "=== Step 1: OLMT creates cases (no build, no submit) ==="
python3 site_fullrun.py \
    --site ${SITE} \
    --sitegroup BNF \
    --machine cades \
    --caseidprefix ${CASEID} \
    --model_root ${MODEL_ROOT} \
    --ccsm_input ${CCSM_INPUT} \
    --runroot    ${RUNROOT} \
    --caseroot   ${CASEROOT} \
    --mpilib openmpi \
    --np 1 \
    --walltime 24 \
    --nofire \
    --clm_paramfile ${CLM_PARAMFILE} \
    --clm1pt_dir ${CLM1PT_DIR} \
    --nyears_ad_spinup 200 \
    --nyears_final_spinup 600 \
    --batch_build \
    --no_submit

# ══════════════════════════════════════════════════════════════════════
# Step 2: Copy SourceMods into AD case and build exe
#   The AD case is used only as the build target.
#   fun_fpg1_nfix mods are safe during AD (FUN/FUNP flags are off there).
# ══════════════════════════════════════════════════════════════════════
echo ""
echo "=== Step 2: Copy SourceMods (fun_fpg1_nfix) and build exe ==="
mkdir -p ${AD_CASE}/SourceMods/src.clm
cp ${SOURCEMODS}/*.F90 ${AD_CASE}/SourceMods/src.clm/
if [[ -d ${CASEROOT}/source_codes/_shared_elm_fun_col_es ]]; then
  cp ${CASEROOT}/source_codes/_shared_elm_fun_col_es/*.F90 ${AD_CASE}/SourceMods/src.clm/
fi
echo "  Copied $(ls ${AD_CASE}/SourceMods/src.clm/*.F90 | wc -l) SourceMod files"
cd ${AD_CASE}
./case.build 2>&1 | tee build_fun_transient.log
EXEROOT=${RUNROOT}/${CASEID}_${SITE}_I1850CNRDCTCBC_ad_spinup/bld
if [ ! -f "${EXEROOT}/e3sm.exe" ]; then
  echo "ERROR: Build FAILED. Check ${AD_CASE}/build_fun_transient.log"
  exit 1
fi
echo "  exe built: ${EXEROOT}/e3sm.exe"

# ══════════════════════════════════════════════════════════════════════
# Step 3: Set BUILD_COMPLETE + EXEROOT on transient case
#   (FN case also updated in case it's ever used, but won't be submitted)
# ══════════════════════════════════════════════════════════════════════
echo ""
echo "=== Step 3: Set BUILD_COMPLETE on transient case ==="
for casedir in ${FN_CASE} ${TR_CASE}; do
  if [ -d "$casedir" ]; then
    cd "$casedir"
    ./xmlchange BUILD_COMPLETE=TRUE
    ./xmlchange EXEROOT=${EXEROOT}
    echo "  $(basename $casedir): BUILD_COMPLETE=TRUE, EXEROOT set"
  else
    echo "  ERROR: $casedir not found" >&2
    exit 1
  fi
done

# ══════════════════════════════════════════════════════════════════════
# Step 3b: Inject fsoilordercon into transient case
#   Transient uses CNP (P cycle active), so needs the Manaus oxisol P rates.
#   We inject into TR only (we're not running FN for this experiment).
# ══════════════════════════════════════════════════════════════════════
echo ""
echo "=== Step 3b: Inject fsoilordercon (Manaus oxisol P rates) into transient ==="
nl="${TR_CASE}/user_nl_clm"
if grep -q 'fsoilordercon' "${nl}"; then
  sed -i "s|fsoilordercon.*|fsoilordercon = '${CNP_SOILORDERFILE}'|" "${nl}"
  echo "  transient: fsoilordercon replaced"
else
  echo " fsoilordercon = '${CNP_SOILORDERFILE}'" >> "${nl}"
  echo "  transient: fsoilordercon appended"
fi

# ══════════════════════════════════════════════════════════════════════
# Step 4: Configure transient case
#   - Enable FUN+FUNP
#   - finidat → nofun_baseline FN spinup yr 751 restart
#   - RUN_REFDATE → 0751-01-01
# ══════════════════════════════════════════════════════════════════════
echo ""
echo "=== Step 4: Configure transient (FUN+FUNP ON, finidat → nofun_baseline yr 751) ==="
cd ${TR_CASE}

# Enable FUN and FUNP
sed -i 's/use_fun = .false./use_fun = .true./' user_nl_clm
sed -i 's/use_funp = .false./use_funp = .true./' user_nl_clm
grep -q 'use_fun'  user_nl_clm || echo 'use_fun  = .true.' >> user_nl_clm
grep -q 'use_funp' user_nl_clm || echo 'use_funp = .true.' >> user_nl_clm

# Point finidat at nofun_baseline FN spinup yr 751 restart
sed -i "s|finidat = .*|finidat = '${NOFUN_FN_RESTART}'|" user_nl_clm
# Fix RUN_REFDATE
./xmlchange RUN_REFDATE=0751-01-01

./preview_namelists 2>&1 | tail -3

# Verify
if grep -q 'use_fun = .true.' user_nl_clm && grep -q 'use_funp = .true.' user_nl_clm; then
  echo "  transient: FUN/FUNP ON confirmed"
else
  echo "ERROR: FUN/FUNP not enabled in transient" >&2
  exit 1
fi
echo "  transient: finidat → ${NOFUN_CASEID} yr 751 restart"
echo "  transient: RUN_REFDATE=0751-01-01"

# ══════════════════════════════════════════════════════════════════════
# Step 5: Patch PBS script (exclude broken nodes)
# ══════════════════════════════════════════════════════════════════════
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
  else
    echo "  WARNING: ${TR_PBS} not found"
  fi
else
  echo "  WARNING: PBS script dir not found: ${PBSDIR}"
fi

# ══════════════════════════════════════════════════════════════════════
# Step 6: Submit TRANSIENT ONLY
#   AD and FN spinup are NOT rerun — we rely on nofun_baseline FN spinup.
# ══════════════════════════════════════════════════════════════════════
cd ${OLMT}

echo ""
echo "=== Step 6: Submitting transient case only ==="
TR_PBS="${PBSDIR}/transient_group0.pbs"
if [ ! -f "${TR_PBS}" ]; then
  echo "ERROR: Transient PBS script not found: ${TR_PBS}" >&2
  exit 1
fi

out=$(sbatch "${TR_PBS}" 2>&1)
rc=$?
if [ $rc -ne 0 ] || ! echo "$out" | grep -q 'Submitted batch job'; then
  echo "ERROR: Failed to submit transient: $out" >&2
  exit 1
fi
JID=$(echo "$out" | awk '{print $4}')

echo ""
echo "════════════════════════════════════════════════════════════"
echo "=== TRANSIENT JOB SUBMITTED ==="
echo "CASEID:         ${CASEID}"
echo "Job ID:         ${JID}"
echo "SourceMods:     fun_fpg1_nfix (fpg=fpg_p=1.0 diagnostic fix)"
echo "Param file:     ${CLM_PARAMFILE}"
echo "SoilOrder:      ${CNP_SOILORDERFILE}  (r_weather[4]=0.0001, r_mort[4]=0.01)"
echo "Spinup reused:  ${NOFUN_CASEID}  (nofun_baseline FN spinup yr 751)"
echo "Nfixation:      Standard Houlton (s_fix=-0.1, no acclimation override)"
echo "Transient:      1850-2101, FUN+FUNP ON, branching from nofun_baseline yr 751"
echo "Monitor with:   squeue -u \$USER"
echo "════════════════════════════════════════════════════════════"
