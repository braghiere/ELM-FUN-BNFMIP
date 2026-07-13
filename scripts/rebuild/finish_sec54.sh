#!/bin/bash
LOG=/home/braghiere/finish_sec54.log; exec >"$LOG" 2>&1
echo "###### §5.4 (fixed CO2/Ndep @2015, 2015-2100) $(date) ######"
source ~/elm_env_cades_gcc12.sh; export TMPDIR=/lustre/or-scratch24/scratch/braghiere/tmp_build TMP=$TMPDIR TEMP=$TMPDIR
OLMT=/home/braghiere/BNF_tom/OLMT_BNF; CD=$OLMT/cime_case_dirs; RR=/lustre/or-scratch24/scratch/braghiere; IN=/home/braghiere/BNF_tom/inputdata; MR=/home/braghiere/BNF_tom/E3SM_global_silent
EXC="or-condo-c04,or-condo-c67,or-condo-c88,or-condo-c69,or-condo-c99,or-condo-c107,or-condo-c108,or-condo-c134,or-condo-c207,or-condo-c231"
CO2_2015=401.5
sm(){ case $1 in nofun)echo control_fixed_funp_nfix;;fun)echo fun_fpg1_nfix;;noacc)[ $2 = BNF-Man ]&&echo noACC_fixed_funp_nfix||echo noACC_temperate_funp_nfix;;acc)[ $2 = BNF-Man ]&&echo ACC_fixed_funp_nfix||echo ACC_temperate_funp_nfix;;esac;}
uf(){ [ "$1" = nofun ] && echo "" || echo "--use_fun --use_funp"; }

# ---- §5.4 for a combo that HAS r.2015 ----
mk54(){ # site exp pft param met surf dom finidat cid
  local site=$1 exp=$2 pft=$3 param=$4 met=$5 surf=$6 dom=$7 fini=$8 cid=$9
  [ ! -f "$fini" ] && { echo "  $cid: r.2015 finidat MISSING ($fini)"; return; }
  rm -rf $CD/${cid}_* $RR/${cid}_* 2>/dev/null; cd $OLMT
  python3 runcase.py --site $site --sitegroup BNF --machine cades --caseidprefix $cid --model_root $MR --ccsm_input $IN --runroot $RR --caseroot $CD --nofire \
    --compset I20TRCNPRDCTCBC --istrans --nopointdata --surffile $surf --domainfile $dom --clm_paramfile $param --clm1pt_dir $met \
    --finidat $fini --co2_file fco2_datm_ssp585_1765-2100_c260519.nc --ndep_rcp85 $(uf $exp) \
    --mpilib openmpi --np 1 --pio_version 2 --ng 256 --tstep 0.5 --walltime 24 --project e3sm \
    --run_units nyears --run_n 86 --run_startyear 2015 --align_year 1851 --hist_mfilt 12 --hist_nhtfrq 0 --no_build --no_submit --rmold > /home/braghiere/create_${cid}.log 2>&1
  local C=$(ls -d $CD/${cid}_${site}_I20TR* 2>/dev/null|head -1); [ -z "$C" ] && { echo "  $cid CREATE FAIL"; tail -5 /home/braghiere/create_${cid}.log; return; }
  cd $C; mkdir -p SourceMods/src.clm; cp $CD/source_codes/$(sm $exp $site)/*.F90 SourceMods/src.clm/ 2>/dev/null; cp $CD/source_codes/_shared_elm_fun_col_es/*.F90 SourceMods/src.clm/ 2>/dev/null
  sed -i '/^domainfile/d' user_nl_datm; echo "domainfile = \"$dom\"" >> user_nl_datm
  # §5.4 = FIXED CO2 + FIXED Ndep at 2015; met transient SSP585 (keep continuous DATM alignment)
  ./xmlchange ATM_NX=1,ATM_NY=1,LND_NX=1,LND_NY=1,ROF_NX=1,ROF_NY=1 >/dev/null 2>&1
  ./xmlchange DATM_CO2_TSERIES=none,CCSM_CO2_PPMV=$CO2_2015 >/dev/null 2>&1
  ./xmlchange DATM_CLMNCEP_YR_ALIGN=1851,DATM_CLMNCEP_YR_START=1851,DATM_CLMNCEP_YR_END=2100 >/dev/null 2>&1
  ./xmlchange RUN_STARTDATE=2015-01-01,STOP_N=86 >/dev/null 2>&1
  grep -q stream_year_first_ndep user_nl_clm || printf " stream_year_first_ndep = 2015\n stream_year_last_ndep = 2015\n" >> user_nl_clm
  sed -i "s#stream_fldfilename_ndep = '/nfs/data/ccsi/proj-shared/E3SM/inputdata#stream_fldfilename_ndep = '$IN#" user_nl_clm
  ./case.build > build.log 2>&1
  [ -f "$(./xmlquery EXEROOT --value)/e3sm.exe" ] || { echo "  $cid BUILD FAIL"; tail -6 build.log; return; }
  ./preview_namelists >/dev/null 2>&1
  local j=$(./case.submit --batch-args="--exclude=$EXC" 2>&1|grep -oE "job id is [0-9]+"|grep -oE "[0-9]+$")
  echo "  §5.4 $cid -> ${j:-FAIL}  (CO2 fixed=$CO2_2015, Ndep fixed 2015)"
}
echo "=== PART A: Bonanza §5.4 (4 combos, r.2015 available) ==="
BP=/home/braghiere/BNF_tom/clm_params_fun3_sfix01_bon_tuned.nc; BM=$IN/BNFMIP_forcing_from_OCN/BNF_Bon/CLM1PT_data; BS=/home/braghiere/BNF_tom/surfdata_bon_gelisol.nc; BD=$IN/domain_BNF-Bon_1x1.nc
for e in fun noacc acc; do
  src=$(ls -d $RR/sc_${e}_transient*_bon_repro20260709_*/run 2>/dev/null|head -1); r=$(ls $src/*.clm2.r.2015-01-01-00000.nc 2>/dev/null|head -1)
  mk54 BNF-Bon $e 2 $BP $BM $BS $BD "$r" sec54_${e}_bon_repro20260709
done
rn=$(ls $RR/ft_nofun_baseline_bon_repro20260709_*/run/*.clm2.r.2015-01-01-00000.nc 2>/dev/null|head -1)
mk54 BNF-Bon nofun 2 $BP $BM $BS $BD "$rn" sec54_nofun_bon_repro20260709
echo "SEC54_BON_DONE $(date)" > /home/braghiere/finish_sec54.DONE
