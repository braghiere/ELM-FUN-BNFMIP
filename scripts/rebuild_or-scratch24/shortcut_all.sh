#!/bin/bash
# Restart-shortcut fan-out: 6 FUN combos (Man+Bon x fun/noacc/acc).
# ONE continuous 1850-2100 transient per combo from the year-751 restart, SSP5-8.5 forcing.
# Slice sec5.3 (1850-2014) + sec5.5 (2015-2100) from output -> continuous at 2015 by construction.
LOG=/home/braghiere/shortcut_all.log; exec >>"$LOG" 2>&1
echo "################ SHORTCUT FAN-OUT START $(date) ################"
source ~/elm_env_cades_gcc12.sh; export TMPDIR=/lustre/or-scratch24/scratch/braghiere/tmp_build TMP=$TMPDIR TEMP=$TMPDIR
OLMT=/home/braghiere/BNF_tom/OLMT_BNF; CD=$OLMT/cime_case_dirs; RR=/lustre/or-scratch24/scratch/braghiere; IN=/home/braghiere/BNF_tom/inputdata
EXC="or-condo-c04,or-condo-c100,or-condo-c112,or-condo-c159,or-condo-c174,or-condo-c210,or-condo-c67,or-condo-c88,or-condo-c99"
CO2=fco2_datm_ssp585_1765-2100_c260519.nc   # protocol-correct SSP5-8.5

surf(){ case $1 in BNF-Man)echo $RR/manaus_ssp585_staged2/nofun_baseline/surfdata.nc;;
  BNF-Bon)echo /home/braghiere/BNF_tom/surfdata_bon_gelisol.nc;; esac;}
dom(){ case $1 in BNF-Man)echo $IN/domain_BNF-Man_1x1.nc;; BNF-Bon)echo $IN/domain_BNF-Bon_1x1.nc;; esac;}
param(){ case $1 in BNF-Man)echo /home/braghiere/BNF_tom/clm_params_fun3_sfix01_manaus_tuned.nc;;
  BNF-Bon)echo /home/braghiere/BNF_tom/clm_params_fun3_sfix01_bon_tuned.nc;; esac;}
met(){ case $1 in BNF-Man)echo $IN/BNFMIP_forcing_from_OCN/BNF_Man/CLM1PT_data;; BNF-Bon)echo $IN/BNFMIP_forcing_from_OCN/BNF_Bon/CLM1PT_data;; esac;}
tag3(){ case $1 in BNF-Man)echo man;; BNF-Bon)echo bon;; esac;}
# boreal Bon noACC/ACC -> temperate variant (phase2 default); FLAGGED for verification
smods(){ local exp=$1 site=$2; case $exp in fun_transient_only)echo fun_fpg1_nfix;;
  noacc_transient)[ $site = BNF-Man ]&&echo noACC_fixed_funp_nfix||echo noACC_temperate_funp_nfix;;
  acc_transient)[ $site = BNF-Man ]&&echo ACC_fixed_funp_nfix||echo ACC_temperate_funp_nfix;; esac;}

run_combo(){
  local site=$1 exp=$2 exp3=$3
  local SF=$(surf $site) DOM=$(dom $site) PM=$(param $site) M1PT=$(met $site) SM=$(smods $exp $site)
  local FINI=/home/braghiere/BNF_tom/restart_opt/$(tag3 $site)_optimized_restart_${exp3}_0751-01-01-00000.nc
  local CID=sc_${exp}_$(tag3 $site)_repro20260709
  echo "==== [$site/$exp] $(date +%H:%M) finidat=$(basename $FINI) ===="
  [ -f "$FINI" ] || { echo "  MISSING restart $FINI"; return; }
  rm -rf $CD/${CID}_${site}_I20TR* $RR/${CID}_${site}_I20TR* 2>/dev/null
  cd $OLMT
  python3 runcase.py --site $site --sitegroup BNF --machine cades --caseidprefix $CID \
    --model_root /home/braghiere/BNF_tom/E3SM_global_silent --ccsm_input $IN --runroot $RR --caseroot $CD --nofire \
    --compset I20TRCNPRDCTCBC --istrans --clm_paramfile $PM --clm1pt_dir $M1PT \
    --surffile $SF --domainfile $DOM --nopointdata --finidat $FINI --co2_file $CO2 --ndep_rcp85 \
    --mpilib openmpi --np 1 --pio_version 2 --ng 256 --tstep 0.5 --walltime 24 --project e3sm \
    --run_units nyears --run_n 251 --run_startyear 1850 --align_year 1851 \
    --hist_mfilt 12 --hist_nhtfrq 0 --no_build --no_submit --rmold > /home/braghiere/create_${CID}.log 2>&1
  local C=$(ls -d $CD/${CID}_${site}_I20TR* 2>/dev/null|head -1)
  [ -z "$C" ] && { echo "  CREATE FAILED (create_${CID}.log)"; return; }
  cd $C; mkdir -p SourceMods/src.clm
  cp $CD/source_codes/$SM/*.F90 SourceMods/src.clm/ 2>/dev/null
  cp $CD/source_codes/_shared_elm_fun_col_es/*.F90 SourceMods/src.clm/ 2>/dev/null
  sed -i '/^domainfile/d' user_nl_datm; echo "domainfile = \"$DOM\"" >> user_nl_datm
  ./xmlchange ATM_NX=1,ATM_NY=1,LND_NX=1,LND_NY=1,ROF_NX=1,ROF_NY=1 >/dev/null 2>&1
  ./case.build > build.log 2>&1
  [ -f "$(./xmlquery EXEROOT --value)/e3sm.exe" ] || { echo "  BUILD FAILED ($C/build.log)"; return; }
  local jid=$(./case.submit --batch-args="--exclude=$EXC" 2>&1|grep -oE "job id is [0-9]+"|grep -oE "[0-9]+$")
  echo "  LAUNCHED $site/$exp -> ${jid:-SUBMIT-FAIL}  case=$CID"
}

for c in "BNF-Bon fun_transient_only fun" "BNF-Bon noacc_transient noacc" "BNF-Bon acc_transient acc" \
         "BNF-Man fun_transient_only fun" "BNF-Man noacc_transient noacc" "BNF-Man acc_transient acc"; do
  set -- $c; run_combo "$1" "$2" "$3" &
  sleep 90   # stagger builds
done
wait
echo "SHORTCUT_FANOUT_DONE $(date)" > /home/braghiere/shortcut_all.DONE
echo "################ SHORTCUT FAN-OUT LAUNCHED $(date) ################"
