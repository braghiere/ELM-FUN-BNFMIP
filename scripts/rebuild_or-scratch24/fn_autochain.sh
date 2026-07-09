#!/bin/bash
# From-scratch autochainer: advance all 12 combos AD(done)->FN(750yr)->transient(1850-2100 SSP585).
# Idempotent polling daemon: launches a phase only if predecessor restart exists AND phase not
# already started (no restart, no queued job). Survives session; self-terminates after ~48h.
LOG=/home/braghiere/fn_autochain.log; exec >>"$LOG" 2>&1
echo "################ FN AUTOCHAIN START $(date) ################"
source ~/elm_env_cades_gcc12.sh; export TMPDIR=/lustre/or-scratch24/scratch/braghiere/tmp_build TMP=$TMPDIR TEMP=$TMPDIR
OLMT=/home/braghiere/BNF_tom/OLMT_BNF; CD=$OLMT/cime_case_dirs; RR=/lustre/or-scratch24/scratch/braghiere; IN=/home/braghiere/BNF_tom/inputdata
EXC="or-condo-c04,or-condo-c100,or-condo-c112,or-condo-c159,or-condo-c174,or-condo-c210,or-condo-c67,or-condo-c88,or-condo-c99"
CO2=fco2_datm_ssp585_1765-2100_c260519.nc
tag(){ case $1 in BNF-Man)echo manaus;;BNF-Ha1)echo ha1;;BNF-Bon)echo bon;;esac;}
surf(){ case $1 in BNF-Man)echo $RR/manaus_ssp585_staged2/nofun_baseline/surfdata.nc;;
  BNF-Ha1)echo $IN/surfdata_BNF-Ha1_PFT7.nc;; BNF-Bon)echo /home/braghiere/BNF_tom/surfdata_bon_gelisol.nc;; esac;}
dom(){ case $1 in BNF-Man)echo $IN/domain_BNF-Man_1x1.nc;;BNF-Ha1)echo $IN/domain_BNF-Har_1x1.nc;;BNF-Bon)echo $IN/domain_BNF-Bon_1x1.nc;;esac;}
param(){ case $1 in BNF-Man)echo /home/braghiere/BNF_tom/clm_params_fun3_sfix01_manaus_tuned.nc;;
  BNF-Ha1)echo /home/braghiere/BNF_tom/clm_params_fun3_sfix01.nc;; BNF-Bon)echo /home/braghiere/BNF_tom/clm_params_fun3_sfix01_bon_tuned.nc;;esac;}
met(){ echo $IN/BNFMIP_forcing_from_OCN/BNF_$(case $1 in BNF-Man)echo Man;;BNF-Ha1)echo Har;;BNF-Bon)echo Bon;;esac)/CLM1PT_data;}
adcs(){ [ "$1" = nofun_baseline ] && echo I1850CNRDCTCBC || echo I1850CNPRDCTCBC;}
smods(){ local exp=$1 site=$2;case $exp in nofun_baseline)echo control_fixed_funp_nfix;;fun_transient_only)echo fun_fpg1_nfix;;
  noacc_transient)[ $site = BNF-Man ]&&echo noACC_fixed_funp_nfix||echo noACC_temperate_funp_nfix;;
  acc_transient)[ $site = BNF-Man ]&&echo ACC_fixed_funp_nfix||echo ACC_temperate_funp_nfix;;esac;}
qbusy(){ squeue -u braghiere -h -o "%j" 2>/dev/null | grep -q "$1";}   # job name substring in queue?

launch(){  # $1 case-dir $2 domain $3 smods-dir  -> apply fixes, build, submit
  local C=$1 DOM=$2 SM=$3
  cd $C; mkdir -p SourceMods/src.clm
  cp $CD/source_codes/$SM/*.F90 SourceMods/src.clm/ 2>/dev/null
  cp $CD/source_codes/_shared_elm_fun_col_es/*.F90 SourceMods/src.clm/ 2>/dev/null
  sed -i '/^domainfile/d' user_nl_datm; echo "domainfile = \"$DOM\"" >> user_nl_datm
  ./xmlchange ATM_NX=1,ATM_NY=1,LND_NX=1,LND_NY=1,ROF_NX=1,ROF_NY=1 >/dev/null 2>&1
  ./case.build > build.log 2>&1
  [ -f "$(./xmlquery EXEROOT --value)/e3sm.exe" ] || { echo "    BUILD FAILED $C/build.log"; return 1;}
  local jid=$(./case.submit --batch-args="--exclude=$EXC" 2>&1|grep -oE "job id is [0-9]+"|grep -oE "[0-9]+$")
  echo "    LAUNCHED -> ${jid:-SUBMIT-FAIL}"; return 0
}

for iter in $(seq 1 288); do
  echo "==== iter $iter $(date +%m-%d_%H:%M) ===="
  alldone=1
  for site in BNF-Man BNF-Ha1 BNF-Bon; do for exp in nofun_baseline fun_transient_only noacc_transient acc_transient; do
    tg=$(tag $site); SF=$(surf $site); DOM=$(dom $site); PM=$(param $site); M1PT=$(met $site); SM=$(smods $exp $site)
    ADrun=$RR/${exp}_${tg}_repro20260708_${site}_$(adcs $exp)_ad_spinup/run
    ADrst=$(ls $ADrun/*.clm2.r.0201-01-01-00000.nc 2>/dev/null|head -1)
    FNcid=fn_${exp}_${tg}_repro20260709; FNc=$(ls -d $CD/${FNcid}_${site}_I1850* 2>/dev/null|head -1)
    FNrst=$(ls $RR/${FNcid}_${site}_I1850*/run/*.clm2.r.0751-01-01-00000.nc 2>/dev/null|head -1)
    TRcid=fs_${exp}_${tg}_repro20260709; TRc=$(ls -d $CD/${TRcid}_${site}_I20TR* 2>/dev/null|head -1)
    TRrst=$(ls $RR/${TRcid}_${site}_I20TR*/run/*.clm2.r.2101-01-01-00000.nc 2>/dev/null|head -1)
    # ---- stage decisions ----
    if [ -n "$TRrst" ]; then continue; fi   # combo fully done
    alldone=0
    if [ -z "$ADrst" ]; then continue; fi    # AD not done yet, wait
    # FN stage
    if [ -z "$FNrst" ]; then
      if qbusy "$FNcid"; then continue; fi
      if [ -z "$FNc" ]; then
        echo "  [$site/$exp] launch FN (finidat AD r.0201)"
        cd $OLMT
        python3 runcase.py --site $site --sitegroup BNF --machine cades --caseidprefix $FNcid \
          --model_root /home/braghiere/BNF_tom/E3SM_global_silent --ccsm_input $IN --runroot $RR --caseroot $CD --nofire \
          --compset I1850CNPRDCTCBC --clm_paramfile $PM --clm1pt_dir $M1PT --surffile $SF --domainfile $DOM --nopointdata \
          --finidat $ADrst --co2_file fco2_datm_rcp4.5_1765-2500_c130312.nc \
          --mpilib openmpi --np 1 --pio_version 2 --ng 256 --tstep 0.5 --walltime 24 --project e3sm \
          --run_units nyears --run_n 750 --run_startyear 1 --align_year 2 \
          --hist_mfilt 1 --hist_nhtfrq -8760 --no_build --no_submit --rmold > /home/braghiere/create_${FNcid}.log 2>&1
        FNc=$(ls -d $CD/${FNcid}_${site}_I1850* 2>/dev/null|head -1)
        [ -z "$FNc" ] && { echo "    FN CREATE FAILED"; continue; }
        grep -q spinup_mortality_factor $FNc/user_nl_clm || echo " spinup_mortality_factor = 10" >> $FNc/user_nl_clm
        launch "$FNc" "$DOM" "$SM"
      fi
      continue
    fi
    # transient stage (continuous 1850-2100 SSP585) from FN r.0751
    if [ -z "$TRrst" ]; then
      if qbusy "$TRcid"; then continue; fi
      if [ -z "$TRc" ]; then
        echo "  [$site/$exp] launch transient (finidat FN r.0751)"
        cd $OLMT
        python3 runcase.py --site $site --sitegroup BNF --machine cades --caseidprefix $TRcid \
          --model_root /home/braghiere/BNF_tom/E3SM_global_silent --ccsm_input $IN --runroot $RR --caseroot $CD --nofire \
          --compset I20TRCNPRDCTCBC --istrans --clm_paramfile $PM --clm1pt_dir $M1PT --surffile $SF --domainfile $DOM --nopointdata \
          --finidat $FNrst --co2_file $CO2 --ndep_rcp85 \
          --mpilib openmpi --np 1 --pio_version 2 --ng 256 --tstep 0.5 --walltime 24 --project e3sm \
          --run_units nyears --run_n 251 --run_startyear 1850 --align_year 1851 \
          --hist_mfilt 12 --hist_nhtfrq 0 --no_build --no_submit --rmold > /home/braghiere/create_${TRcid}.log 2>&1
        TRc=$(ls -d $CD/${TRcid}_${site}_I20TR* 2>/dev/null|head -1)
        [ -z "$TRc" ] && { echo "    TRANS CREATE FAILED"; continue; }
        launch "$TRc" "$DOM" "$SM"
      fi
    fi
  done; done
  [ $alldone -eq 1 ] && { echo "ALL 12 COMBOS DONE $(date)"; break; }
  sleep 600
done
echo "FN_AUTOCHAIN_EXIT $(date)" > /home/braghiere/fn_autochain.DONE
echo "################ FN AUTOCHAIN EXIT $(date) ################"
