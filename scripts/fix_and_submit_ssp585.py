#!/usr/bin/env python3
"""
fix_and_submit_ssp585.py
Fix CLM1PT streams for all 12 SSP585 20260523 cases (copy from working 20260521,
update domain path), then submit all 12.
"""

import os
import subprocess
import sys

SCRATCH   = '/lustre/or-scratch/cades-ccsi/scratch/braghiere'
CASEROOT  = '/home/braghiere/BNF_tom/OLMT_BNF/cime_case_dirs'
ELM_ENV   = '/home/braghiere/elm_env_cades_gcc12.sh'
STAGE     = 'I20TRCNPRDCTCBC'
DATE_HIST = '20260521'
DATE_SSP  = '20260523'

SITES = {
    'BNF-Man': 'manaus',
    'BNF-Ha1': 'ha1',
    'BNF-Bon': 'bon',
}
EXPS = ['nofun_baseline', 'fun_transient_only', 'noacc_transient', 'acc_transient']


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


def fix_clm1pt_stream(site_id, exp):
    tag       = SITES[site_id]
    case_hist = f'{exp}_{tag}_{DATE_HIST}_{site_id}_{STAGE}'
    case_ssp  = f'{exp}_ssp585_{tag}_{DATE_SSP}_{site_id}_{STAGE}'

    src = f'{CASEROOT}/{case_hist}/user_datm.streams.txt.CLM1PT.CLM_USRDAT'
    dst = f'{CASEROOT}/{case_ssp}/user_datm.streams.txt.CLM1PT.CLM_USRDAT'

    if not os.path.exists(src):
        raise FileNotFoundError(f'Source stream not found: {src}')

    with open(src) as fh:
        content = fh.read()

    # Replace domain filePath: hist run dir → ssp run dir
    old_run = f'{SCRATCH}/{case_hist}/run'
    new_run = f'{SCRATCH}/{case_ssp}/run'
    if old_run not in content:
        raise ValueError(f'Expected run path not found in source stream:\n  {old_run}')
    content = content.replace(old_run, new_run)

    with open(dst, 'w') as fh:
        fh.write(content)
    print(f'  CLM1PT fixed → {os.path.basename(dst)}')


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
                # Fix CLM1PT stream
                print(f'  [1/2] Fixing CLM1PT stream...')
                fix_clm1pt_stream(site_id, exp)

                # Submit
                print(f'  [2/2] Submitting...')
                res = run(f'cd {case_dir} && ./case.submit', check=False,
                          label='case.submit')
                if res.returncode == 0:
                    # Extract job ID from last non-blank output line
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
