#!/bin/bash
LOG=/home/braghiere/spinup_fanout.log; exec >"$LOG" 2>&1
echo "###### CNP+FUNP spin-up FAN-OUT (8 combos; Bon-fun already done) $(date) ######"
source ~/elm_env_cades_gcc12.sh; export TMPDIR=/lustre/or-scratch24/scratch/braghiere/tmp_build TMP=$TMPDIR TEMP=$TMPDIR
OLMT=/home/braghiere/BNF_tom/OLMT_BNF; CD=$OLMT/cime_case_dirs; RR=/lustre/or-scratch24/scratch/braghiere
IN=/home/braghiere/BNF_tom/inputdata; MR=/home/braghiere/BNF_tom/E3SM_global_silent
EXC="or-condo-c04,or-condo-c67,or-condo-c88,or-condo-c69,or-condo-c99,or-condo-c107,or-condo-c108,or-condo-c134,or-condo-c207,or-condo-c231,or-condo-c208"
src(){ case $1 in fun)echo fun_fpg1_nfix;; noacc)[ "$2" = BNF-Man ]&&echo noACC_fixed_funp_nfix||echo noACC_temperate_funp_nfix;; acc)[ "$2" = BNF-Man ]&&echo ACC_fixed_funp_nfix||echo ACC_temperate_funp_nfix;; esac; }
mkspin(){ # site exp pft param met surf dom finidat cid
  local site=$1 exp=$2 pft=$3 param=$4 met=$5 surf=$6 dom=$7 fini=$8 cid=$9
  [ ! -f "$fini" ] && { echo "  $cid: FINIDAT MISSING ($fini)"; return; }
  [ ! -f "$surf" ] && { echo "  $cid: SURF MISSING ($surf)"; return; }
  rm -rf $CD/${cid}_* $RR/${cid}_* 2>/dev/null; cd $OLMT
  python3 runcase.py --site $site --sitegroup BNF --machine cades --caseidprefix $cid --model_root $MR --ccsm_input $IN --runroot $RR --caseroot $CD --nofire \
    --compset I1850CNPRDCTCBC --nopointdata --surffile $surf --domainfile $dom --clm_paramfile $param --clm1pt_dir $met \
    --finidat $fini --use_fun --use_funp --mpilib openmpi --np 1 --pio_version 2 --ng 256 --tstep 0.5 --walltime 24 --project e3sm \
    --run_units nyears --run_n 300 --hist_mfilt 1 --hist_nhtfrq -8760 --no_build --no_submit --rmold > /home/braghiere/create_${cid}.log 2>&1
  local C=$(ls -d $CD/${cid}_${site}_I1850* 2>/dev/null|head -1); [ -z "$C" ] && { echo "  $cid CREATE FAIL"; tail -4 /home/braghiere/create_${cid}.log; return; }
  cd $C; mkdir -p SourceMods/src.clm
  cp $CD/source_codes/$(src $exp $site)/*.F90 SourceMods/src.clm/ 2>/dev/null
  cp $CD/source_codes/_shared_elm_fun_col_es/*.F90 SourceMods/src.clm/ 2>/dev/null
  sed -i '/^domainfile/d' user_nl_datm 2>/dev/null; echo "domainfile = \"$dom\"" >> user_nl_datm
  ./xmlchange ATM_NX=1,ATM_NY=1,LND_NX=1,LND_NY=1,ROF_NX=1,ROF_NY=1 >/dev/null 2>&1
  sed -i "s#stream_fldfilename_ndep = '/nfs/data/ccsi/proj-shared/E3SM/inputdata#stream_fldfilename_ndep = '$IN#" user_nl_clm 2>/dev/null
  ./case.build > build.log 2>&1
  [ -f "$(./xmlquery EXEROOT --value)/e3sm.exe" ] || { echo "  $cid BUILD FAIL"; tail -5 build.log; return; }
  ./preview_namelists >/dev/null 2>&1
  local J=$(./case.submit --batch-args="--exclude=$EXC" 2>&1|grep -oE "job id is [0-9]+"|grep -oE "[0-9]+$")
  echo "  spinup $cid -> job ${J:-FAIL}"
}
RO=/home/braghiere/BNF_tom/restart_opt
BS=/home/braghiere/BNF_tom/surfdata_bon_gelisol.nc; BP=/home/braghiere/BNF_tom/clm_params_fun3_sfix01_bon_tuned.nc; BM=$IN/BNFMIP_forcing_from_OCN/BNF_Bon/CLM1PT_data; BD=$IN/domain_BNF-Bon_1x1.nc
MS=$(ls $RR/mpd_fun_man_repro20260709_*/run/surfdata.nc|head -1); MP=/home/braghiere/BNF_tom/clm_params_fun3_sfix01_manaus_tuned.nc; MM=$IN/BNFMIP_forcing_from_OCN/BNF_Man/CLM1PT_data; MD=$IN/domain_BNF-Man_1x1.nc
HS=$(ls $RR/mpd_fun_ha1v2_repro20260709_*/run/surfdata.nc|head -1); HP=/home/braghiere/BNF_tom/clm_params_fun3_sfix01.nc; HM=$IN/BNFMIP_forcing_from_OCN/BNF_Ha1/CLM1PT_data; HD=$IN/domain_BNF-Ha1_1x1.nc
for e in noacc acc; do mkspin BNF-Bon $e 2 $BP $BM $BS $BD $RO/bon_optimized_restart_${e}_0751-01-01-00000.nc spinCNP_${e}_bon; done
for e in fun noacc acc; do mkspin BNF-Man $e 4 $MP $MM $MS $MD $RO/man_optimized_restart_${e}_0751-01-01-00000.nc spinCNP_${e}_man; done
for e in fun noacc acc; do
  ef=$([ $e = fun ]&&echo fun_transient_only||([ $e = noacc ]&&echo noacc_transient||echo acc_transient))
  fini=$(ls $RR/fn_${ef}_ha1_repro20260709_*/run/*.clm2.r.0751-01-01-00000.nc $RR/fn2_${ef}_ha1_repro20260709_*/run/*.clm2.r.0751-01-01-00000.nc 2>/dev/null|head -1)
  mkspin BNF-Ha1 $e 7 $HP $HM $HS $HD "$fini" spinCNP_${e}_ha1
done
echo "FANOUT_DONE $(date)" > /home/braghiere/spinup_fanout.DONE
