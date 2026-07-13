#!/bin/bash
source ~/elm_env_cades_gcc12.sh; export TMPDIR=/lustre/or-scratch24/scratch/braghiere/tmp_build TMP=$TMPDIR TEMP=$TMPDIR
cd /home/braghiere/BNF_tom/OLMT_BNF
for e in fun noacc acc; do
  ef=$([ $e = fun ]&&echo fun_transient_only||([ $e = noacc ]&&echo noacc_transient||echo acc_transient))
  fini=$(ls /lustre/or-scratch24/scratch/braghiere/fn_${ef}_ha1_repro20260709_*/run/*.clm2.r.0751-01-01-00000.nc /lustre/or-scratch24/scratch/braghiere/fn2_${ef}_ha1_repro20260709_*/run/*.clm2.r.0751-01-01-00000.nc 2>/dev/null|head -1)
  cid=spinCNP_${e}_ha1
  rm -rf /home/braghiere/BNF_tom/OLMT_BNF/cime_case_dirs/${cid}_* /lustre/or-scratch24/scratch/braghiere/${cid}_* 2>/dev/null
  python3 runcase.py --site BNF-Ha1 --sitegroup BNF --machine cades --caseidprefix $cid --model_root /home/braghiere/BNF_tom/E3SM_global_silent --ccsm_input /home/braghiere/BNF_tom/inputdata --runroot /lustre/or-scratch24/scratch/braghiere --caseroot /home/braghiere/BNF_tom/OLMT_BNF/cime_case_dirs --nofire     --compset I1850CNPRDCTCBC --nopointdata --surffile /lustre/or-scratch24/scratch/braghiere/mpd_fun_ha1v2_repro20260709_BNF-Ha1_I20TRCNPRDCTCBC/run/surfdata.nc --domainfile /home/braghiere/BNF_tom/inputdata/domain_BNF-Ha1_1x1.nc --clm_paramfile /home/braghiere/BNF_tom/clm_params_fun3_sfix01.nc --clm1pt_dir /home/braghiere/BNF_tom/inputdata/BNFMIP_forcing_from_OCN/BNF_Har/CLM1PT_data     --finidat $fini --use_fun --use_funp --mpilib openmpi --np 1 --pio_version 2 --ng 256 --tstep 0.5 --walltime 24 --project e3sm     --run_units nyears --run_n 300 --hist_mfilt 1 --hist_nhtfrq -8760 --no_build --no_submit --rmold > /home/braghiere/create_${cid}.log 2>&1
  C=$(ls -d /home/braghiere/BNF_tom/OLMT_BNF/cime_case_dirs/${cid}_BNF-Ha1_I1850* 2>/dev/null|head -1)
  cd $C; mkdir -p SourceMods/src.clm
  cp /home/braghiere/BNF_tom/OLMT_BNF/cime_case_dirs/source_codes/$(case $e in fun)echo fun_fpg1_nfix;;noacc)echo noACC_temperate_funp_nfix;;acc)echo ACC_temperate_funp_nfix;;esac)/*.F90 SourceMods/src.clm/ 2>/dev/null
  cp /home/braghiere/BNF_tom/OLMT_BNF/cime_case_dirs/source_codes/_shared_elm_fun_col_es/*.F90 SourceMods/src.clm/ 2>/dev/null
  sed -i '/^domainfile/d' user_nl_datm 2>/dev/null; echo "domainfile = \"/home/braghiere/BNF_tom/inputdata/domain_BNF-Ha1_1x1.nc\"" >> user_nl_datm
  ./xmlchange ATM_NX=1,ATM_NY=1,LND_NX=1,LND_NY=1,ROF_NX=1,ROF_NY=1 >/dev/null 2>&1
  sed -i "s#stream_fldfilename_ndep = '/nfs/data/ccsi/proj-shared/E3SM/inputdata#stream_fldfilename_ndep = '/home/braghiere/BNF_tom/inputdata#" user_nl_clm 2>/dev/null
  ./case.build > build.log 2>&1
  ./preview_namelists >/dev/null 2>&1
  J=$(./case.submit --batch-args="--exclude=or-condo-c04,or-condo-c67,or-condo-c88,or-condo-c69,or-condo-c99,or-condo-c107,or-condo-c108,or-condo-c134,or-condo-c207,or-condo-c231,or-condo-c208" 2>&1|grep -oE "job id is [0-9]+"|grep -oE "[0-9]+$")
  echo "  $cid -> job ${J:-FAIL}"
  cd /home/braghiere/BNF_tom/OLMT_BNF
done
echo "HA1_FIX_DONE"
