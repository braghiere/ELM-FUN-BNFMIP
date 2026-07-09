#!/bin/bash
LOG=/home/braghiere/proof_bonfun_sec53.log; exec >"$LOG" 2>&1
echo "==== PROOF: Bon fun §5.3 transient from year-751 restart $(date) ===="
source ~/elm_env_cades_gcc12.sh; export TMPDIR=/lustre/or-scratch24/scratch/braghiere/tmp_build TMP=$TMPDIR TEMP=$TMPDIR
OLMT=/home/braghiere/BNF_tom/OLMT_BNF; CD=$OLMT/cime_case_dirs; RR=/lustre/or-scratch24/scratch/braghiere; IN=/home/braghiere/BNF_tom/inputdata
EXC="or-condo-c04,or-condo-c100,or-condo-c112,or-condo-c159,or-condo-c174,or-condo-c210,or-condo-c67,or-condo-c88,or-condo-c99"
SF=/home/braghiere/BNF_tom/surfdata_bon_gelisol.nc; DOM=$IN/domain_BNF-Bon_1x1.nc
FINI=/home/braghiere/BNF_tom/restart_opt/bon_optimized_restart_fun_0751-01-01-00000.nc
CID=sec53_shortcut_bonfun_repro20260709
rm -rf $CD/${CID}_BNF-Bon_I20TR* $RR/${CID}_BNF-Bon_I20TR* 2>/dev/null
cd $OLMT
python3 runcase.py --site BNF-Bon --sitegroup BNF --machine cades --caseidprefix $CID \
  --model_root /home/braghiere/BNF_tom/E3SM_global_silent --ccsm_input $IN --runroot $RR --caseroot $CD --nofire \
  --compset I20TRCNPRDCTCBC --istrans \
  --clm_paramfile /home/braghiere/BNF_tom/clm_params_fun3_sfix01_bon_tuned.nc \
  --clm1pt_dir $IN/BNFMIP_forcing_from_OCN/BNF_Bon/CLM1PT_data --surffile $SF --domainfile $DOM --nopointdata \
  --finidat $FINI --co2_file fco2_datm_rcp4.5_1765-2500_c130312.nc \
  --mpilib openmpi --np 1 --pio_version 2 --ng 256 --tstep 0.5 --walltime 24 --project e3sm \
  --run_units nyears --run_n 165 --run_startyear 1850 --align_year 1851 \
  --hist_mfilt 12 --hist_nhtfrq 0 --no_build --no_submit --rmold > /home/braghiere/create_${CID}.log 2>&1
C=$(ls -d $CD/${CID}_BNF-Bon_I20TR* 2>/dev/null|head -1)
[ -z "$C" ] && { echo "CREATE FAILED:"; tail -25 /home/braghiere/create_${CID}.log; echo "PROOF_DONE fail-create $(date)">/home/braghiere/proof_bonfun_sec53.DONE; exit 1; }
echo "created: $C"
cd $C; mkdir -p SourceMods/src.clm
cp $CD/source_codes/fun_fpg1_nfix/*.F90 SourceMods/src.clm/ 2>/dev/null
cp $CD/source_codes/_shared_elm_fun_col_es/*.F90 SourceMods/src.clm/ 2>/dev/null
sed -i '/^domainfile/d' user_nl_datm; echo "domainfile = \"$DOM\"" >> user_nl_datm
./xmlchange ATM_NX=1,ATM_NY=1,LND_NX=1,LND_NY=1,ROF_NX=1,ROF_NY=1 >/dev/null 2>&1
echo "--- key namelist checks ---"
grep -iE "finidat|ndep|check_finidat" user_nl_clm | head -5
./xmlquery COMPSET,RUN_STARTDATE,STOP_N,DATM_CLMNCEP_YR_ALIGN,CLM_CO2_TYPE --value 2>/dev/null
echo "--- building ---"
./case.build > build.log 2>&1
if [ ! -f "$(./xmlquery EXEROOT --value)/e3sm.exe" ]; then echo "BUILD FAILED:"; tail -30 build.log; echo "PROOF_DONE fail-build $(date)">/home/braghiere/proof_bonfun_sec53.DONE; exit 1; fi
jid=$(./case.submit --batch-args="--exclude=$EXC" 2>&1|grep -oE "job id is [0-9]+"|grep -oE "[0-9]+$")
echo "LAUNCHED §5.3 proof -> ${jid:-SUBMIT-FAIL}"
echo "PROOF_DONE launched:${jid} case:$C $(date)" > /home/braghiere/proof_bonfun_sec53.DONE
