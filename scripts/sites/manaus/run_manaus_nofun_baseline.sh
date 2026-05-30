#!/bin/bash
# Manaus no-FUN baseline pipeline:
#   ad_spinup (200yr, FUN/FUNP OFF) → iniadjust → fn_spinup (600yr, FUN/FUNP OFF)
#   → transient 1850-2101 (FUN/FUNP OFF)
#
# Uses standard ELM decomposition with Houlton BNF fix (s_fix=-0.1).
# SourceMods: control_fixed_funp_nfix
#   - use_funp guard: fpg_p=1.0 when use_funp=TRUE (irrelevant here, but harmless)
#   - Houlton s_fix=-0.1 tuned to ~2 gN/m²/yr at Manaus
#
# Run on a compute node:
#   srun -A ccsi -p burst -N 1 -n 1 -t 4:00:00 --mem 32G \
#        --exclude=or-condo-c105,or-condo-c67 --pty bash
#   cd /home/braghiere/BNF_tom/OLMT_BNF && bash run_manaus_nofun_baseline.sh
set -e

# ── Safety: abort if on a login node ──
if [[ "$(hostname)" == *login* ]]; then
  echo "ERROR: This script must run on a compute node, not $(hostname)!"
  exit 1
fi

source ~/elm_env_cades_gcc12.sh

OLMT=/home/braghiere/BNF_tom/OLMT_BNF
MODEL_ROOT=/home/braghiere/BNF_tom/E3SM_global_silent
CCSM_INPUT="${CCSM_INPUT:-/lustre/or-scratch/cades-ccsi/proj-shared/project_acme/e3sm_inputdata}"
RUNROOT=/lustre/or-scratch/cades-ccsi/scratch/braghiere
CASEROOT=/home/braghiere/BNF_tom/OLMT_BNF/cime_case_dirs
CLM_PARAMFILE=/home/braghiere/BNF_tom/clm_params_fun3_sfix01_manaus_tuned.nc
CNP_SOILORDERFILE=/home/braghiere/BNF_tom/CNP_parameters_manaus_oxisol.nc
CLM1PT_DIR=/home/braghiere/BNF_tom/inputdata/BNFMIP_forcing_from_OCN/BNF_Man/CLM1PT_data
CASEID=nofun_baseline_manaus_$(date +%Y%m%d)
SITE=BNF-Man
SOURCEMODS=${CASEROOT}/source_codes/control_fixed_funp_nfix

# Derived case directories
AD_CASE=${CASEROOT}/${CASEID}_${SITE}_I1850CNRDCTCBC_ad_spinup
FN_CASE=${CASEROOT}/${CASEID}_${SITE}_I1850CNPRDCTCBC
TR_CASE=${CASEROOT}/${CASEID}_${SITE}_I20TRCNPRDCTCBC
FN_RUNDIR=${RUNROOT}/${CASEID}_${SITE}_I1850CNPRDCTCBC

# ── Clean up any existing cases with today's CASEID ──
echo "=== Cleaning up ${CASEID}_${SITE}_* cases ==="
for suffix in _I1850CNRDCTCBC_ad_spinup _I1850CNRDCTCBC _I1850CNPRDCTCBC _I20TRCNPRDCTCBC; do
  d=${CASEROOT}/${CASEID}_${SITE}${suffix}
  [ -d "$d" ] && rm -rf "$d" && echo "  Removed $d"
  r=${RUNROOT}/${CASEID}_${SITE}${suffix}
  [ -d "$r" ] && rm -rf "$r" && echo "  Removed $r"
done

cd ${OLMT}

# ══════════════════════════════════════════════════════════════════════
# Step 1: Create ad_spinup, fn_spinup, and transient cases (no build)
# ══════════════════════════════════════════════════════════════════════
echo ""
echo "=== Step 1: OLMT creates cases ==="
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
# Step 2: Copy SourceMods into ad_spinup case and build exe
# ══════════════════════════════════════════════════════════════════════
echo ""
echo "=== Step 2: Copy SourceMods (control_fixed_funp_nfix) and build ==="

# 50-year output for ad_spinup (reduce I/O)
sed -i 's/hist_nhtfrq = .*/hist_nhtfrq = -438000, -438000/' ${AD_CASE}/user_nl_clm
echo "  ad_spinup: hist_nhtfrq set to -438000 (50-year output)"

mkdir -p ${AD_CASE}/SourceMods/src.clm
cp ${SOURCEMODS}/*.F90 ${AD_CASE}/SourceMods/src.clm/
if [[ -d ${CASEROOT}/source_codes/_shared_elm_fun_col_es ]]; then
  cp ${CASEROOT}/source_codes/_shared_elm_fun_col_es/*.F90 ${AD_CASE}/SourceMods/src.clm/
fi
echo "  Copied $(ls ${AD_CASE}/SourceMods/src.clm/*.F90 | wc -l) SourceMod files"
cd ${AD_CASE}
./case.build 2>&1 | tee build_nofun.log
EXEROOT=${RUNROOT}/${CASEID}_${SITE}_I1850CNRDCTCBC_ad_spinup/bld
if [ ! -f "${EXEROOT}/e3sm.exe" ]; then
    echo "ERROR: Build FAILED. Check ${AD_CASE}/build_nofun.log"
    exit 1
fi
echo "  exe built: ${EXEROOT}/e3sm.exe"

# ══════════════════════════════════════════════════════════════════════
# Step 3: Set BUILD_COMPLETE + EXEROOT on fn_spinup and transient
# ══════════════════════════════════════════════════════════════════════
echo ""
echo "=== Step 3: Set BUILD_COMPLETE on fn_spinup and transient ==="
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
# Step 3b: Inject fsoilordercon → Manaus oxisol CNP rates in FN+TR cases
#   Manaus surface file has SOIL_ORDER=4 (Entisols, wrong for Amazon oxisol).
#   CNP_parameters_manaus_oxisol.nc sets r_weather[4]=0.0001/mo (vs 0.001)
#   and r_mort_soilorder[4]=0.01 (vs 0.025) — matching Oxisols (idx 12).
#   AD spinup uses CN (no P), so fsoilordercon only needed for FN + transient.
# ══════════════════════════════════════════════════════════════════════
echo ""
echo "=== Step 3b: Inject fsoilordercon (Manaus oxisol P rates) into FN and TR ==="
for casedir in ${FN_CASE} ${TR_CASE}; do
  nl="${casedir}/user_nl_clm"
  if grep -q 'fsoilordercon' "${nl}"; then
    sed -i "s|fsoilordercon.*|fsoilordercon = '${CNP_SOILORDERFILE}'|" "${nl}"
    echo "  $(basename $casedir): fsoilordercon replaced"
  else
    echo " fsoilordercon = '${CNP_SOILORDERFILE}'" >> "${nl}"
    echo "  $(basename $casedir): fsoilordercon appended"
  fi
done

# ══════════════════════════════════════════════════════════════════════
# Step 4: Configure fn_spinup (600yr, FUN/FUNP OFF)
#   OLMT sets FUN=.false. by default — keep it that way.
#   Use 50-year output intervals to reduce I/O.
# ══════════════════════════════════════════════════════════════════════
echo ""
echo "=== Step 4: Configure fn_spinup (600yr, FUN/FUNP OFF) ==="
cd ${FN_CASE}
sed -i 's/hist_nhtfrq = .*/hist_nhtfrq = -438000, -438000/' user_nl_clm
echo "  fn_spinup: hist_nhtfrq set to -438000 (50-year output)"

# Verify FUN is OFF
if grep -q 'use_fun = .true.' user_nl_clm; then
  echo "ERROR: FUN should be OFF for no-FUN baseline fn_spinup" >&2
  exit 1
fi
echo "  fn_spinup: FUN/FUNP OFF confirmed"

# ══════════════════════════════════════════════════════════════════════
# Step 5: Configure transient (FUN/FUNP OFF, finidat → yr 601)
# ══════════════════════════════════════════════════════════════════════
echo ""
echo "=== Step 5: Configure transient (FUN/FUNP OFF, finidat → yr 601) ==="
cd ${TR_CASE}

# Verify FUN stays OFF in transient
if grep -q 'use_fun = .true.' user_nl_clm; then
  echo "ERROR: FUN should be OFF for no-FUN baseline transient" >&2
  exit 1
fi

# Fix finidat to point to year 601 restart (after 600yr fn_spinup)
FN_RESTART=${FN_RUNDIR}/run/${CASEID}_${SITE}_I1850CNPRDCTCBC.clm2.r.0601-01-01-00000.nc
sed -i "s|finidat = .*|finidat = '${FN_RESTART}'|" user_nl_clm
# Fix RUN_REFDATE
./xmlchange RUN_REFDATE=0601-01-01
./preview_namelists 2>&1 | tail -3
echo "  transient: FUN/FUNP OFF, finidat → year 601"
echo "  transient: RUN_REFDATE=0601-01-01"

# ══════════════════════════════════════════════════════════════════════
# Step 6: Patch PBS scripts (exclude broken nodes)
# ══════════════════════════════════════════════════════════════════════
PBSDIR=${OLMT}/scripts/${CASEID}
echo ""
echo "=== Step 6: Patching PBS scripts ==="
if [ -d "$PBSDIR" ]; then
  for f in ${PBSDIR}/*.pbs; do
    if ! grep -q "exclude" "$f"; then
      sed -i '/#SBATCH  --nodes=1/a #SBATCH  --exclude=or-condo-c105,or-condo-c67,or-condo-c04' "$f"
      echo "  $(basename $f): added --exclude"
    else
      echo "  $(basename $f): already patched"
    fi
  done
else
  echo "  WARNING: PBS script dir not found: ${PBSDIR}"
fi

# ══════════════════════════════════════════════════════════════════════
# Step 7: Submit pipeline
#   ad_spinup(200yr) → iniadjust → fn_spinup(600yr) → transient(1850-2101)
# ══════════════════════════════════════════════════════════════════════
cd ${OLMT}

submit_chain() {
    local label=$1
    local script=$2
    local dep=$3
    local out
    out=$(sbatch $dep "$script" 2>&1)
    local rc=$?
    if [ $rc -ne 0 ] || ! echo "$out" | grep -q 'Submitted batch job'; then
        echo "ERROR: Failed to submit ${label}: $out" >&2
        exit 1
    fi
    local jid=$(echo "$out" | awk '{print $4}')
    echo "  ${label}: job ${jid}  ${dep:-"(no dependency)"}" >&2
    echo $jid
}

echo ""
echo "=== Pipeline: ad_spinup(200yr) → iniadjust → fn_spinup(600yr) → transient(1850-2101) ==="
echo ""

JID=$(submit_chain "ad_spinup"   ${PBSDIR}/ad_spinup_group0.pbs   "")
JID=$(submit_chain "iniadjust"   ${PBSDIR}/iniadjust_group0.pbs   "--dependency=afterok:${JID}")
JID=$(submit_chain "fn_spinup"   ${PBSDIR}/fn_spinup_group0.pbs   "--dependency=afterok:${JID}")
JID=$(submit_chain "transient"   ${PBSDIR}/transient_group0.pbs   "--dependency=afterok:${JID}")

echo ""
echo "════════════════════════════════════════════════════════════"
echo "=== ALL 4 JOBS SUBMITTED ==="
echo "CASEID:       ${CASEID}"
echo "SourceMods:   control_fixed_funp_nfix (FUN/FUNP OFF throughout)"
echo "Param file:   ${CLM_PARAMFILE}  (s_fix=-0.1, leafcn=24, leafcp=268, slatop=0.012)"
echo "SoilOrder:    ${CNP_SOILORDERFILE}  (r_weather[4]=0.0001, r_mort[4]=0.01)"
echo "Pipeline:     ad_spinup(200yr) → iniadjust → fn_spinup(600yr, FUN OFF) → transient(FUN OFF)"
echo "Transient:    1850-2101 starting from fn_spinup yr 601"
echo "Monitor with: squeue -u \$USER"
echo "If any stage fails, all downstream jobs are auto-cancelled."
echo "════════════════════════════════════════════════════════════"
