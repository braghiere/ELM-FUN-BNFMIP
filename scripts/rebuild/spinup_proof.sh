#!/bin/bash
LOG=/home/braghiere/spinup_proof.log; exec >"$LOG" 2>&1
echo "###### CNP+FUNP spin-up PROOF (Bon-fun) $(date) ######"
source ~/elm_env_cades_gcc12.sh; export TMPDIR=/lustre/or-scratch24/scratch/braghiere/tmp_build TMP=$TMPDIR TEMP=$TMPDIR
OLMT=/home/braghiere/BNF_tom/OLMT_BNF; CD=$OLMT/cime_case_dirs; RR=/lustre/or-scratch24/scratch/braghiere
IN=/home/braghiere/BNF_tom/inputdata; MR=/home/braghiere/BNF_tom/E3SM_global_silent
EXC="or-condo-c04,or-condo-c67,or-condo-c88,or-condo-c69,or-condo-c99,or-condo-c107,or-condo-c108,or-condo-c134,or-condo-c207,or-condo-c231,or-condo-c208"
BP=/home/braghiere/BNF_tom/clm_params_fun3_sfix01_bon_tuned.nc
BM=$IN/BNFMIP_forcing_from_OCN/BNF_Bon/CLM1PT_data
BS=/home/braghiere/BNF_tom/surfdata_bon_gelisol.nc; BD=$IN/domain_BNF-Bon_1x1.nc
FIN=/home/braghiere/BNF_tom/restart_opt/bon_optimized_restart_fun_0751-01-01-00000.nc
CID=spinCNP_fun_bon
rm -rf $CD/${CID}_* $RR/${CID}_* 2>/dev/null; cd $OLMT
# regular I1850 CNP spin-up, FUN+FUNP on, from the 751-yr CN restart; 300 yr; annual output for convergence check
python3 runcase.py --site BNF-Bon --sitegroup BNF --machine cades --caseidprefix $CID --model_root $MR --ccsm_input $IN --runroot $RR --caseroot $CD --nofire \
  --compset I1850CNPRDCTCBC --nopointdata --surffile $BS --domainfile $BD --clm_paramfile $BP --clm1pt_dir $BM \
  --finidat $FIN --use_fun --use_funp \
  --mpilib openmpi --np 1 --pio_version 2 --ng 256 --tstep 0.5 --walltime 24 --project e3sm \
  --run_units nyears --run_n 300 --hist_mfilt 1 --hist_nhtfrq -8760 --no_build --no_submit --rmold > /home/braghiere/create_${CID}.log 2>&1
C=$(ls -d $CD/${CID}_BNF-Bon_I1850* 2>/dev/null|head -1); [ -z "$C" ] && { echo "CREATE FAIL"; tail -8 /home/braghiere/create_${CID}.log; exit 1; }
cd $C; mkdir -p SourceMods/src.clm
cp $CD/source_codes/fun_fpg1_nfix/*.F90 SourceMods/src.clm/ 2>/dev/null
cp $CD/source_codes/_shared_elm_fun_col_es/*.F90 SourceMods/src.clm/ 2>/dev/null
sed -i '/^domainfile/d' user_nl_datm 2>/dev/null; echo "domainfile = \"$BD\"" >> user_nl_datm
./xmlchange ATM_NX=1,ATM_NY=1,LND_NX=1,LND_NY=1,ROF_NX=1,ROF_NY=1 >/dev/null 2>&1
sed -i "s#stream_fldfilename_ndep = '/nfs/data/ccsi/proj-shared/E3SM/inputdata#stream_fldfilename_ndep = '$IN#" user_nl_clm 2>/dev/null
echo "=== confirm config ==="; grep -iE "use_fun|use_funp" user_nl_clm; ./xmlquery COMPSET --value 2>/dev/null|grep -oE "CNP?RDCTCBC"
./case.build > build.log 2>&1
[ -f "$(./xmlquery EXEROOT --value)/e3sm.exe" ] || { echo "BUILD FAIL"; tail -8 build.log; exit 1; }
./preview_namelists >/dev/null 2>&1
J=$(./case.submit --batch-args="--exclude=$EXC" 2>&1|grep -oE "job id is [0-9]+"|grep -oE "[0-9]+$")
echo "SPINUP PROOF submitted: job ${J:-FAIL}  case=$C"
echo "SPINUP_PROOF_LAUNCHED $(date)" > /home/braghiere/spinup_proof.DONE
