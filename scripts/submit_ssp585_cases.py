#!/usr/bin/env python3
"""
submit_ssp585_cases.py
Create and submit 12 SSP585 §5.5 BNFMIP transient cases (date tag 20260523).

All year-751 spinup restarts are confirmed present on scratch.
Corrected vs notebook FINIDAT_CASES:
  - Ha1/Bon noacc & acc → 20260521 fn_spinup cases (were None in notebook)
  - Manaus acc → acc_transient_manaus_20260521 (was missing old case)
"""

import os
import subprocess
import sys

# ── Configuration ──────────────────────────────────────────────────────────────
SCRATCH    = '/lustre/or-scratch/cades-ccsi/scratch/braghiere'
E3SM_ROOT  = '/home/braghiere/BNF_tom/E3SM_global_silent'
OLMT_DIR   = '/home/braghiere/BNF_tom/OLMT_BNF'
CCSM_INPUT = '/lustre/or-scratch/cades-ccsi/proj-shared/project_acme/e3sm_inputdata'
ELM_ENV    = '/home/braghiere/elm_env_cades_gcc12.sh'

SSP585_CO2_FNAME = 'fco2_datm_ssp585_1765-2100_c260519.nc'
SSP585_CO2_PATH  = '/home/braghiere/BNF_tom/inputdata'
STAGE            = 'I20TRCNPRDCTCBC'
DATE_SSP         = '20260523'
FINIDAT_YEAR     = 751

SITES = {
    'BNF-Man': {
        'tag'        : 'manaus',
        'metdata'    : '/home/braghiere/BNF_tom/inputdata/BNFMIP_forcing_from_OCN/BNF_Man/CLM1PT_data',
        'clm_params' : '/home/braghiere/BNF_tom/clm_params_fun3_sfix01_manaus_tuned.nc',
    },
    'BNF-Ha1': {
        'tag'        : 'ha1',
        'metdata'    : '/home/braghiere/BNF_tom/inputdata/BNFMIP_forcing_from_OCN/BNF_Har/CLM1PT_data',
        'clm_params' : '/home/braghiere/BNF_tom/clm_params_fun3_sfix01.nc',
    },
    'BNF-Bon': {
        'tag'        : 'bon',
        'metdata'    : '/home/braghiere/BNF_tom/inputdata/BNFMIP_forcing_from_OCN/BNF_Bon/CLM1PT_data',
        'clm_params' : '/home/braghiere/BNF_tom/clm_params_fun3_sfix01.nc',
    },
}

EXP_ORDER = ['nofun_baseline', 'fun_transient_only', 'noacc_transient', 'acc_transient']

MANAUS_FSOILORDER = {
    'nofun_baseline'    : '/home/braghiere/BNF_tom/CNP_parameters_manaus_oxisol.nc',
    'fun_transient_only': '/home/braghiere/BNF_tom/CNP_parameters_manaus_oxisol_v2.nc',
    'noacc_transient'   : '/home/braghiere/BNF_tom/CNP_parameters_manaus_oxisol_v2.nc',
    'acc_transient'     : '/home/braghiere/BNF_tom/CNP_parameters_manaus_oxisol_v2.nc',
}

EXEROOTS = {
    'BNF-Man': {
        'nofun_baseline'    : f'{SCRATCH}/nofun_baseline_manaus_20260325_BNF-Man_I1850CNRDCTCBC_ad_spinup/bld',
        'fun_transient_only': f'{SCRATCH}/fun_transient_only_manaus_20260323_BNF-Man_I1850CNRDCTCBC_ad_spinup/bld',
        'noacc_transient'   : f'{SCRATCH}/noacc_transient_manaus_20260323_BNF-Man_I1850CNRDCTCBC_ad_spinup/bld',
        'acc_transient'     : f'{SCRATCH}/acc_transient_manaus_20260323_BNF-Man_I1850CNRDCTCBC_ad_spinup/bld',
    },
    'BNF-Ha1': {
        'nofun_baseline'    : f'{SCRATCH}/nofun_baseline_ha1_20260325_BNF-Ha1_I1850CNRDCTCBC_ad_spinup/bld',
        'fun_transient_only': f'{SCRATCH}/fun_transient_only_ha1_20260325_BNF-Ha1_I1850CNRDCTCBC_ad_spinup/bld',
        'noacc_transient'   : f'{SCRATCH}/noacc_transient_ha1_20260325_BNF-Ha1_I1850CNRDCTCBC_ad_spinup/bld',
        'acc_transient'     : f'{SCRATCH}/acc_transient_ha1_20260325_BNF-Ha1_I1850CNRDCTCBC_ad_spinup/bld',
    },
    'BNF-Bon': {
        'nofun_baseline'    : f'{SCRATCH}/nofun_baseline_bon_20260325_BNF-Bon_I1850CNRDCTCBC_ad_spinup/bld',
        'fun_transient_only': f'{SCRATCH}/fun_transient_only_bon_20260325_BNF-Bon_I1850CNRDCTCBC_ad_spinup/bld',
        'noacc_transient'   : f'{SCRATCH}/noacc_transient_bon_20260325_BNF-Bon_I1850CNRDCTCBC_ad_spinup/bld',
        'acc_transient'     : f'{SCRATCH}/acc_transient_bon_20260325_BNF-Bon_I1850CNRDCTCBC_ad_spinup/bld',
    },
}

# Corrected vs notebook: Ha1/Bon noacc & acc updated to 20260521 cases; Manaus acc fixed
FINIDAT_CASES = {
    'BNF-Man': {
        'nofun_baseline'    : 'nofun_baseline_manaus_20260320_BNF-Man_I1850CNPRDCTCBC',
        'fun_transient_only': 'fun_transient_only_manaus_20260404_BNF-Man_I1850CNPRDCTCBC',
        'noacc_transient'   : 'noacc_spinupfix_manaus_20260324_BNF-Man_I1850CNPRDCTCBC',
        'acc_transient'     : 'acc_transient_manaus_20260521_BNF-Man_I1850CNPRDCTCBC',
    },
    'BNF-Ha1': {
        'nofun_baseline'    : 'nofun_baseline_ha1_20260325_BNF-Ha1_I1850CNPRDCTCBC',
        'fun_transient_only': 'fun_transient_only_ha1_20260404_BNF-Ha1_I1850CNPRDCTCBC',
        'noacc_transient'   : 'noacc_transient_ha1_20260521_BNF-Ha1_I1850CNPRDCTCBC',
        'acc_transient'     : 'acc_transient_ha1_20260521_BNF-Ha1_I1850CNPRDCTCBC',
    },
    'BNF-Bon': {
        'nofun_baseline'    : 'nofun_baseline_bon_20260325_BNF-Bon_I1850CNPRDCTCBC',
        'fun_transient_only': 'fun_transient_only_bon_20260404_BNF-Bon_I1850CNPRDCTCBC',
        'noacc_transient'   : 'noacc_transient_bon_20260521_BNF-Bon_I1850CNPRDCTCBC',
        'acc_transient'     : 'acc_transient_bon_20260521_BNF-Bon_I1850CNPRDCTCBC',
    },
}


# ── Helpers ────────────────────────────────────────────────────────────────────
def run(cmd, check=True, label=''):
    full = f'source {ELM_ENV} && {cmd}'
    res = subprocess.run(full, shell=True, executable='/bin/bash',
                         capture_output=True, text=True)
    if check and res.returncode != 0:
        print(f'  FAILED{" [" + label + "]" if label else ""}:')
        print(f'  STDOUT: {res.stdout[-800:]}')
        print(f'  STDERR: {res.stderr[-800:]}')
        raise RuntimeError(f'Command failed rc={res.returncode}')
    return res


def casename(exp, site_id):
    return f'{exp}_ssp585_{SITES[site_id]["tag"]}_{DATE_SSP}_{site_id}_{STAGE}'


def build_olmt_cmd(exp, site_id):
    tag      = SITES[site_id]['tag']
    caseid   = f'{exp}_ssp585_{tag}_{DATE_SSP}'
    exeroot  = EXEROOTS[site_id][exp]
    params   = SITES[site_id]['clm_params']
    metdata  = SITES[site_id]['metdata']
    use_funp = '--use_fun --use_funp' if exp != 'nofun_baseline' else ''
    return (
        f'cd {OLMT_DIR} && '
        f'python3 site_fullrun.py '
        f'--site {site_id} '
        f'--caseidprefix {caseid} '
        f'--sitegroup BNF '
        f'--machine cades '
        f'--model_root {E3SM_ROOT} '
        f'--pio_version 1 '
        f'--mpilib openmpi '
        f'--ccsm_input {CCSM_INPUT} '
        f'--metdata_dir {metdata} '
        f'--nopointdata '
        f'--noad --nofnsp '
        f'--exeroot {exeroot} '
        f'--co2_file {SSP585_CO2_FNAME} '
        f'--ndep_rcp85 '
        f'--nyears_final_spinup 750 '
        f'--hist_nhtfrq_trans -24 '
        f'--hist_mfilt_trans 365 '
        f'--walltime 12 '
        f'--no_submit '
        f'--clm_paramfile {params} '
        f'{use_funp}'
    ).strip()


def write_ssp585_stream_xml(case_cime_dir):
    xml = f"""<?xml version="1.0"?>
<file id="stream" version="1.0">
<dataSource>
   GENERIC
</dataSource>
<domainInfo>
  <variableNames>
     time    time
        lonc    lon
        latc    lat
        area    area
        mask    mask
  </variableNames>
  <filePath>
     {SSP585_CO2_PATH}
  </filePath>
  <fileNames>
      {SSP585_CO2_FNAME}
  </fileNames>
</domainInfo>
<fieldInfo>
   <variableNames>
     CO2        co2diag
   </variableNames>
   <filePath>
     {SSP585_CO2_PATH}
   </filePath>
   <fileNames>
      {SSP585_CO2_FNAME}
   </fileNames>
   <offset>
      0
   </offset>
</fieldInfo>
</file>
"""
    out = f'{case_cime_dir}/user_datm.streams.txt.co2tseries.20tr'
    with open(out, 'w') as fh:
        fh.write(xml)
    print(f'    CO2 stream → {os.path.basename(out)}')


def fix_user_nl_clm(case_cime_dir, site_id, exp):
    finidat_case = FINIDAT_CASES[site_id][exp]
    finidat_file = (
        f'{SCRATCH}/{finidat_case}/run/'
        f'{finidat_case}.clm2.r.{FINIDAT_YEAR:04d}-01-01-00000.nc'
    )
    if not os.path.exists(finidat_file):
        raise FileNotFoundError(f'Restart not found: {finidat_file}')

    nl_path = f'{case_cime_dir}/user_nl_clm'
    with open(nl_path) as fh:
        lines = fh.readlines()

    new_lines = []
    for line in lines:
        if line.strip().startswith('finidat'):
            new_lines.append(f" finidat = '{finidat_file}'\n")
        elif line.strip().startswith('paramfile'):
            new_lines.append(f" paramfile = '{SITES[site_id]['clm_params']}'\n")
        elif line.strip().startswith('fsoilordercon') and site_id == 'BNF-Man':
            new_lines.append(f" fsoilordercon = '{MANAUS_FSOILORDER[exp]}'\n")
        else:
            new_lines.append(line)

    if not any('finidat' in l for l in new_lines):
        new_lines.append(f" finidat = '{finidat_file}'\n")

    with open(nl_path, 'w') as fh:
        fh.writelines(new_lines)
    print(f'    user_nl_clm → finidat={os.path.basename(finidat_file)}')


# ── Main ───────────────────────────────────────────────────────────────────────
def main():
    failed = []
    submitted = []

    for site_id in ['BNF-Man', 'BNF-Ha1', 'BNF-Bon']:
        for exp in EXP_ORDER:
            case     = casename(exp, site_id)
            case_dir = f'{OLMT_DIR}/cime_case_dirs/{case}'

            print(f'\n{"="*65}')
            print(f'Case: {case}')

            try:
                # Step 1: Create case via OLMT (--no_submit)
                # Check for .case.run (CIME ≥ 5.x) or case.run (older) to determine if setup is done
                case_run = (f'{case_dir}/.case.run' if os.path.exists(f'{case_dir}/.case.run')
                            else f'{case_dir}/case.run' if os.path.exists(f'{case_dir}/case.run')
                            else None)
                if case_run:
                    print(f'  [skip] Case already set up: {os.path.basename(case_run)} exists')
                else:
                    print(f'  [1/4] Running site_fullrun.py (--no_submit)...')
                    run(build_olmt_cmd(exp, site_id), label='site_fullrun')
                    if not os.path.exists(case_dir):
                        raise RuntimeError(f'Case dir not created after OLMT: {case_dir}')
                    case_run = (f'{case_dir}/.case.run' if os.path.exists(f'{case_dir}/.case.run')
                                else f'{case_dir}/case.run')
                    print(f'  Created: {case_dir}')

                # Step 2: Fix user_nl_clm
                print(f'  [2/4] Fixing user_nl_clm...')
                fix_user_nl_clm(case_dir, site_id, exp)

                # Step 3: Write SSP585 CO2 stream
                print(f'  [3/4] Writing SSP585 CO2 stream XML...')
                write_ssp585_stream_xml(case_dir)

                # Step 4: Submit
                print(f'  [4/4] Submitting...')
                res = run(f'cd {case_dir} && ./case.submit', check=False, label='case.submit')
                if res.returncode == 0:
                    job_line = res.stdout.strip().split('\n')[-1]
                    print(f'  Submitted → {job_line}')
                    submitted.append((case, job_line))
                else:
                    print(f'  SUBMIT FAILED:')
                    print(f'    stdout: {res.stdout[-400:]}')
                    print(f'    stderr: {res.stderr[-400:]}')
                    failed.append((case, 'submit_failed'))

            except Exception as e:
                print(f'  ERROR: {e}')
                failed.append((case, str(e)))

    print(f'\n{"="*65}')
    print(f'SUMMARY: {len(submitted)}/12 submitted, {len(failed)} failed')
    if submitted:
        print('\nSubmitted:')
        for c, j in submitted:
            print(f'  {c}  →  {j}')
    if failed:
        print('\nFailed:')
        for c, e in failed:
            print(f'  {c}  →  {e}')


if __name__ == '__main__':
    main()
