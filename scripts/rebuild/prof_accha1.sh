#!/bin/bash
exec > /home/braghiere/prof_accha1.out 2>&1
source ~/elm_env_cades_gcc12.sh; export TMPDIR=/lustre/or-scratch24/scratch/braghiere/tmp_build TMP=$TMPDIR TEMP=$TMPDIR
OLMT=/home/braghiere/BNF_tom/OLMT_BNF; CD=$OLMT/cime_case_dirs; RR=/lustre/or-scratch24/scratch/braghiere; IN=/home/braghiere/BNF_tom/inputdata; MR=/home/braghiere/BNF_tom/E3SM_global_silent
EXC="or-condo-c04,or-condo-c67,or-condo-c88,or-condo-c69,or-condo-c99,or-condo-c107,or-condo-c108,or-condo-c134,or-condo-c207,or-condo-c231,or-condo-c208,or-condo-c46,or-condo-c198"
HS=$(ls $RR/mpd_fun_ha1v2_repro20260709_*/run/surfdata.nc|head -1); HP=/home/braghiere/BNF_tom/clm_params_fun3_sfix01.nc
HM=$IN/BNFMIP_forcing_from_OCN/BNF_Har/CLM1PT_data; HD=$IN/domain_BNF-Ha1_1x1.nc
FIN=$(ls $RR/fn_fun_transient_only_ha1_repro20260709_*/run/*.clm2.r.0751-01-01-00000.nc|head -1)
# two 10-yr profiled runs on the SAME node type (excl bad), acc vs noacc, from identical finidat
for tag in acc noacc; do
  srcd=$([ $tag = acc ]&&echo ACC_temperate_funp_nfix||echo noACC_temperate_funp_nfix)
  cid=prof_${tag}_ha1; rm -rf $CD/${cid}_* $RR/${cid}_* 2>/dev/null; cd $OLMT
  python3 runcase.py --site BNF-Ha1 --sitegroup BNF --machine cades --caseidprefix $cid --model_root $MR --ccsm_input $IN --runroot $RR --caseroot $CD --nofire \
    --compset I1850CNPRDCTCBC --nopointdata --surffile $HS --domainfile $HD --clm_paramfile $HP --clm1pt_dir $HM \
    --finidat $FIN --use_fun --use_funp --mpilib openmpi --np 1 --pio_version 2 --ng 256 --tstep 0.5 --walltime 2 --project e3sm \
    --run_units nyears --run_n 10 --hist_mfilt 1 --hist_nhtfrq -8760 --no_build --no_submit --rmold > /home/braghiere/create_${cid}.log 2>&1
  C=$(ls -d $CD/${cid}_BNF-Ha1_I1850* 2>/dev/null|head -1); cd $C; mkdir -p SourceMods/src.clm
  cp $CD/source_codes/$srcd/*.F90 SourceMods/src.clm/ 2>/dev/null; cp $CD/source_codes/_shared_elm_fun_col_es/*.F90 SourceMods/src.clm/ 2>/dev/null
  sed -i '/^domainfile/d' user_nl_datm; echo "domainfile = \"$HD\"" >> user_nl_datm
  ./xmlchange ATM_NX=1,ATM_NY=1,LND_NX=1,LND_NY=1,ROF_NX=1,ROF_NY=1 >/dev/null 2>&1
  sed -i "s#stream_fldfilename_ndep = '/nfs/data/ccsi/proj-shared/E3SM/inputdata#stream_fldfilename_ndep = '$IN#" user_nl_clm 2>/dev/null
  ./case.build > build.log 2>&1
  ./preview_namelists >/dev/null 2>&1
  j=$(./case.submit --batch-args="--exclude=$EXC" 2>&1|grep -oE "job id is [0-9]+"|grep -oE "[0-9]+$")
  echo "  prof_${tag}_ha1 (10yr) -> job ${j:-FAIL}"
done
echo "PROF_LAUNCH_DONE"
