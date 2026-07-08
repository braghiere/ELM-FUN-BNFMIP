#!/usr/bin/env python3
"""
fix_co2stream_resubmit.py
Fix the CO2 datm stream for all 12 SSP585 20260523 cases:
  - domainInfo → standard RCP4.5 file (has lonc/latc/area/mask)
  - fieldInfo  → our SSP585 CO2 file (actual CO2 data)
Then resubmit all 12 cases.
"""

import os
import subprocess

CASEROOT  = '/home/braghiere/BNF_tom/OLMT_BNF/cime_case_dirs'
ELM_ENV   = '/home/braghiere/elm_env_cades_gcc12.sh'
STAGE     = 'I20TRCNPRDCTCBC'
DATE_SSP  = '20260523'

# Domain file: standard RCP4.5 (has lonc, latc, area, mask, frac)
CO2_DOMAIN_PATH = '/lustre/or-scratch/cades-ccsi/proj-shared/project_acme/e3sm_inputdata/atm/datm7/CO2'
CO2_DOMAIN_FNAME = 'fco2_datm_rcp4.5_1765-2500_c130312.nc'

# Data file: SSP585 CO2 concentrations
CO2_DATA_PATH  = '/home/braghiere/BNF_tom/inputdata'
CO2_DATA_FNAME = 'fco2_datm_ssp585_1765-2100_c260519.nc'

SITES = {
    'BNF-Man': 'manaus',
    'BNF-Ha1': 'ha1',
    'BNF-Bon': 'bon',
}
EXPS = ['nofun_baseline', 'fun_transient_only', 'noacc_transient', 'acc_transient']

CO2_STREAM_XML = f"""<?xml version="1.0"?>
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
     {CO2_DOMAIN_PATH}
  </filePath>
  <fileNames>
      {CO2_DOMAIN_FNAME}
  </fileNames>
</domainInfo>
<fieldInfo>
   <variableNames>
     CO2        co2diag
   </variableNames>
   <filePath>
     {CO2_DATA_PATH}
   </filePath>
   <fileNames>
      {CO2_DATA_FNAME}
   </fileNames>
   <offset>
      0
   </offset>
</fieldInfo>
</file>
"""


def run(cmd, check=True, label=''):
    full = f'source {ELM_ENV} && {cmd}'
    res = subprocess.run(full, shell=True, executable='/bin/bash',
                         capture_output=True, text=True)
    if check and res.returncode != 0:
        print(f'  FAILED [{label}]:')
        print(f'  STDOUT: {res.stdout[-600:]}')
        print(f'  STDERR: {res.stderr[-600:]}')
        raise RuntimeError(f'Command failed rc={res.returncode}')
    return res


def main():
    failed    = []
    submitted = []

    for site_id in ['BNF-Man', 'BNF-Ha1', 'BNF-Bon']:
        for exp in EXPS:
            tag      = SITES[site_id]
            case_ssp = f'{exp}_ssp585_{tag}_{DATE_SSP}_{site_id}_{STAGE}'
            case_dir = f'{CASEROOT}/{case_ssp}'

            print(f'\n{"="*65}')
            print(f'Case: {case_ssp}')

            if not os.path.isdir(case_dir):
                print(f'  ERROR: case dir missing: {case_dir}')
                failed.append((case_ssp, 'no case dir'))
                continue

            try:
                # Fix CO2 stream
                stream_path = f'{case_dir}/user_datm.streams.txt.co2tseries.20tr'
                with open(stream_path, 'w') as fh:
                    fh.write(CO2_STREAM_XML)
                print(f'  CO2 stream fixed: domainInfo={CO2_DOMAIN_FNAME}, fieldInfo={CO2_DATA_FNAME}')

                # Resubmit
                print(f'  Submitting...')
                res = run(f'cd {case_dir} && ./case.submit', check=False,
                          label='case.submit')
                if res.returncode == 0:
                    lines = [l for l in res.stdout.strip().split('\n') if l.strip()]
                    job_line = lines[-1] if lines else '(no output)'
                    print(f'  Submitted → {job_line}')
                    submitted.append((case_ssp, job_line))
                else:
                    print(f'  SUBMIT FAILED:')
                    print(f'    stdout: {res.stdout[-500:]}')
                    print(f'    stderr: {res.stderr[-500:]}')
                    failed.append((case_ssp, 'submit_failed'))

            except Exception as e:
                print(f'  ERROR: {e}')
                failed.append((case_ssp, str(e)))

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
