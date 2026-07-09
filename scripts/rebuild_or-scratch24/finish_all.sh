#!/bin/bash
LOG=/home/braghiere/finish_all.log; exec >>"$LOG" 2>&1
echo "############ FINISH ALL $(date) ############"
source ~/elm_env_cades_gcc12.sh; export TMPDIR=/lustre/or-scratch24/scratch/braghiere/tmp_build TMP=$TMPDIR TEMP=$TMPDIR
OLMT=/home/braghiere/BNF_tom/OLMT_BNF; CD=$OLMT/cime_case_dirs; RR=/lustre/or-scratch24/scratch/braghiere; IN=/home/braghiere/BNF_tom/inputdata
EXC="or-condo-c04,or-condo-c67,or-condo-c88,or-condo-c69,or-condo-c99,or-condo-c100,or-condo-c112,or-condo-c159,or-condo-c174,or-condo-c210"
CO2=fco2_datm_ssp585_1765-2100_c260519.nc; MR=/home/braghiere/BNF_tom/E3SM_global_silent
tag(){ case $1 in BNF-Man)echo manaus;;BNF-Ha1)echo ha1;;BNF-Bon)echo bon;;esac;}
surf(){ case $1 in BNF-Man)echo $RR/manaus_ssp585_staged2/nofun_baseline/surfdata.nc;;BNF-Ha1)echo $IN/surfdata_BNF-Ha1_PFT7.nc;;BNF-Bon)echo /home/braghiere/BNF_tom/surfdata_bon_gelisol.nc;;esac;}
dom(){ case $1 in BNF-Man)echo $IN/domain_BNF-Man_1x1.nc;;BNF-Ha1)echo $IN/domain_BNF-Har_1x1.nc;;BNF-Bon)echo $IN/domain_BNF-Bon_1x1.nc;;esac;}
param(){ case $1 in BNF-Man)echo /home/braghiere/BNF_tom/clm_params_fun3_sfix01_manaus_tuned.nc;;BNF-Ha1)echo /home/braghiere/BNF_tom/clm_params_fun3_sfix01.nc;;BNF-Bon)echo /home/braghiere/BNF_tom/clm_params_fun3_sfix01_bon_tuned.nc;;esac;}
met(){ echo $IN/BNFMIP_forcing_from_OCN/BNF_$(case $1 in BNF-Man)echo Man;;BNF-Ha1)echo Har;;BNF-Bon)echo Bon;;esac)/CLM1PT_data;}
smods(){ local e=$1 s=$2;case $e in nofun_baseline)echo control_fixed_funp_nfix;;fun_transient_only)echo fun_fpg1_nfix;;noacc_transient)[ $s = BNF-Man ]&&echo noACC_fixed_funp_nfix||echo noACC_temperate_funp_nfix;;acc_transient)[ $s = BNF-Man ]&&echo ACC_fixed_funp_nfix||echo ACC_temperate_funp_nfix;;esac;}
fix(){ local C=$1 D=$2 SM=$3; cd $C; mkdir -p SourceMods/src.clm
  cp $CD/source_codes/$SM/*.F90 SourceMods/src.clm/ 2>/dev/null; cp $CD/source_codes/_shared_elm_fun_col_es/*.F90 SourceMods/src.clm/ 2>/dev/null
  sed -i '/^domainfile/d' user_nl_datm; echo "domainfile = \"$D\"" >> user_nl_datm
  ./xmlchange ATM_NX=1,ATM_NY=1,LND_NX=1,LND_NY=1,ROF_NX=1,ROF_NY=1 >/dev/null 2>&1; }
sub(){ local C=$1 dep=$2; cd $C; local ba="--exclude=$EXC"; [ -n "$dep" ]&&ba="$ba --dependency=afterok:$dep"
  ./case.submit --batch-args="$ba" 2>&1|grep -oE "job id is [0-9]+"|grep -oE "[0-9]+$"; }

mk_trans(){ local site=$1 exp=$2 fini=$3 cid=$4
  cd $OLMT; python3 runcase.py --site $site --sitegroup BNF --machine cades --caseidprefix $cid \
    --model_root $MR --ccsm_input $IN --runroot $RR --caseroot $CD --nofire --compset I20TRCNPRDCTCBC --istrans \
    --clm_paramfile $(param $site) --clm1pt_dir $(met $site) --surffile $(surf $site) --domainfile $(dom $site) --nopointdata \
    --finidat $fini --co2_file $CO2 --ndep_rcp85 --mpilib openmpi --np 1 --pio_version 2 --ng 256 --tstep 0.5 --walltime 24 --project e3sm \
    --run_units nyears --run_n 251 --run_startyear 1850 --align_year 1851 --hist_mfilt 12 --hist_nhtfrq 0 --no_build --no_submit --rmold > /home/braghiere/create_${cid}.log 2>&1
  local C=$(ls -d $CD/${cid}_${site}_I20TR* 2>/dev/null|head -1); [ -z "$C" ]&&return 1
  (cd $C && ./xmlchange REST_OPTION=nyears,REST_N=5 >/dev/null 2>&1); fix $C $(dom $site) $(smods $exp $site)
  cd $C; ./case.build > build.log 2>&1; [ -f "$(./xmlquery EXEROOT --value)/e3sm.exe" ]||{ echo "  TRANS BUILD FAIL $C";return 1;}; echo $C; }
mk_fn(){ local site=$1 exp=$2 adr=$3 cid=$4
  cd $OLMT; python3 runcase.py --site $site --sitegroup BNF --machine cades --caseidprefix $cid \
    --model_root $MR --ccsm_input $IN --runroot $RR --caseroot $CD --nofire --compset I1850CNPRDCTCBC \
    --clm_paramfile $(param $site) --clm1pt_dir $(met $site) --surffile $(surf $site) --domainfile $(dom $site) --nopointdata \
    --finidat $adr --co2_file fco2_datm_rcp4.5_1765-2500_c130312.nc --mpilib openmpi --np 1 --pio_version 2 --ng 256 --tstep 0.5 --walltime 24 --project e3sm \
    --run_units nyears --run_n 750 --run_startyear 1 --align_year 2 --hist_mfilt 1 --hist_nhtfrq -8760 --no_build --no_submit --rmold > /home/braghiere/create_${cid}.log 2>&1
  local C=$(ls -d $CD/${cid}_${site}_I1850* 2>/dev/null|head -1); [ -z "$C" ]&&return 1
  grep -q spinup_mortality_factor $C/user_nl_clm||echo " spinup_mortality_factor = 10">>$C/user_nl_clm
  fix $C $(dom $site) $(smods $exp $site); cd $C; ./case.build > build.log 2>&1
  [ -f "$(./xmlquery EXEROOT --value)/e3sm.exe" ]||{ echo "  FN BUILD FAIL $C";return 1;}; echo $C; }

echo "==== transient-now (FN r.0751 exists) ===="
for c in "BNF-Man nofun_baseline manaus" "BNF-Ha1 fun_transient_only ha1" "BNF-Ha1 noacc_transient ha1"; do
  set -- $c; fini=$(ls $RR/fn_${2}_${3}_repro20260709_${1}_I1850CNPRDCTCBC/run/*.clm2.r.0751-01-01-00000.nc|head -1)
  cid=ft_${2}_${3}_repro20260709; C=$(mk_trans $1 $2 $fini $cid)
  [ -n "$C" ]&&{ j=$(sub $C); echo "  TRANS-NOW $3/$2 -> ${j:-FAIL}"; }
done
echo "==== FN->transient chains (SLURM dep) ===="
for c in "BNF-Ha1 nofun_baseline ha1 I1850CNRDCTCBC" "BNF-Ha1 acc_transient ha1 I1850CNPRDCTCBC" "BNF-Bon nofun_baseline bon I1850CNRDCTCBC"; do
  set -- $c; site=$1 exp=$2 tg=$3 adcs=$4
  adr=$(ls $RR/${exp}_${tg}_repro20260708_${site}_${adcs}_ad_spinup/run/*.clm2.r.0201-01-01-00000.nc|head -1)
  fncid=fn2_${exp}_${tg}_repro20260709; FC=$(mk_fn $site $exp $adr $fncid)
  [ -z "$FC" ]&&{ echo "  FN-CHAIN $tg/$exp: FN create/build FAIL"; continue; }
  fnj=$(sub $FC); echo "  FN2 $tg/$exp -> ${fnj:-FAIL}"
  fini=$RR/${fncid}_${site}_I1850CNPRDCTCBC/run/${fncid}_${site}_I1850CNPRDCTCBC.clm2.r.0751-01-01-00000.nc
  tcid=ft_${exp}_${tg}_repro20260709; TC=$(mk_trans $site $exp $fini $tcid)
  [ -n "$TC" ]&&{ tj=$(sub $TC $fnj); echo "  TRANS(dep $fnj) $tg/$exp -> ${tj:-FAIL}"; }
done
echo "FINISH_ALL_DONE $(date)" > /home/braghiere/finish_all.DONE
