#!/bin/bash
LOG=/home/braghiere/rerun_bon.log; exec >>"$LOG" 2>&1
echo "==== Bon re-run (gelisol surfdata, PFT2, SOIL_ORDER=3) $(date) ===="
source ~/elm_env_cades_gcc12.sh; export TMPDIR=/lustre/or-scratch24/scratch/braghiere/tmp_build TMP=$TMPDIR TEMP=$TMPDIR
OLMT=/home/braghiere/BNF_tom/OLMT_BNF; CD=$OLMT/cime_case_dirs; RR=/lustre/or-scratch24/scratch/braghiere; IN=/home/braghiere/BNF_tom/inputdata
EXC="or-condo-c04,or-condo-c100,or-condo-c112,or-condo-c159,or-condo-c174,or-condo-c210,or-condo-c67,or-condo-c88,or-condo-c99"
SF=/home/braghiere/BNF_tom/surfdata_bon_gelisol.nc; DOM=$IN/domain_BNF-Bon_1x1.nc
PARAM=/home/braghiere/BNF_tom/clm_params_fun3_sfix01_bon_tuned.nc
# boreal Bon: mirror phase2 mapping (temperate noACC/ACC) — AD spinup is CN-only so variant is immaterial here; verify before transient
smods(){ case $1 in nofun_baseline)echo control_fixed_funp_nfix;;fun_transient_only)echo fun_fpg1_nfix;;noacc_transient)echo noACC_temperate_funp_nfix;;acc_transient)echo ACC_temperate_funp_nfix;;esac;}
for exp in nofun_baseline fun_transient_only noacc_transient acc_transient; do
  CID=${exp}_bon_repro20260708
  echo "--- $exp $(date +%H:%M) ---"
  rm -rf $CD/${CID}_BNF-Bon_I1850*_ad_spinup $RR/${CID}_BNF-Bon_I1850*_ad_spinup 2>/dev/null
  cd $OLMT
  timeout 400 python3 runcase.py --site BNF-Bon --sitegroup BNF --machine cades --caseidprefix $CID \
    --model_root /home/braghiere/BNF_tom/E3SM_global_silent --ccsm_input $IN --runroot $RR --caseroot $CD --nofire \
    --clm_paramfile $PARAM \
    --clm1pt_dir $IN/BNFMIP_forcing_from_OCN/BNF_Bon/CLM1PT_data --surffile $SF --domainfile $DOM --nopointdata \
    --co2_file fco2_datm_rcp4.5_1765-2500_c130312.nc --mpilib openmpi --np 1 --pio_version 2 --ng 256 --tstep 0.5 \
    --walltime 24 --project e3sm --ad_spinup --nyears_ad_spinup 200 --align_year 2 --hist_mfilt 1 --hist_nhtfrq -2190000 \
    --no_build --no_submit --rmold > /home/braghiere/create_${CID}.log 2>&1
  AD=$(ls -d $CD/${CID}_BNF-Bon_I1850*_ad_spinup 2>/dev/null|head -1)
  [ -z "$AD" ] && { echo "  CREATE FAILED (see create_${CID}.log)"; continue; }
  cd $AD; mkdir -p SourceMods/src.clm; cp $CD/source_codes/$(smods $exp)/*.F90 SourceMods/src.clm/ 2>/dev/null
  cp $CD/source_codes/_shared_elm_fun_col_es/*.F90 SourceMods/src.clm/ 2>/dev/null
  sed -i '/^domainfile/d' user_nl_datm; echo "domainfile = \"$DOM\"" >> user_nl_datm
  ./xmlchange ATM_NX=1,ATM_NY=1,LND_NX=1,LND_NY=1,ROF_NX=1,ROF_NY=1 >/dev/null 2>&1
  ./case.build > build.log 2>&1
  [ -f "$(./xmlquery EXEROOT --value)/e3sm.exe" ] || { echo "  BUILD FAILED (see $AD/build.log)"; continue; }
  jid=$(./case.submit --batch-args="--exclude=$EXC" 2>&1|grep -oE "job id is [0-9]+"|grep -oE "[0-9]+$")
  echo "  LAUNCHED -> ${jid:-FAIL}"
done
echo "BON_RERUN_DONE $(date)" > /home/braghiere/rerun_bon.DONE
