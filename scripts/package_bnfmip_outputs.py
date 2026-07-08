#!/usr/bin/env python3
"""
package_bnfmip_outputs.py
Compute annual means from monthly/daily ELM h0 output and organize
into BNFMIP delivery files, one per site × experiment × protocol section.

Output structure:
  {OUTDIR}/BNF-Man/
    nofun_baseline_BNF-Man_sec53_1850-2014.nc
    nofun_baseline_BNF-Man_sec54_2015-2100.nc
    nofun_baseline_BNF-Man_sec55_2015-2100.nc   (when SSP585 cases finish)
    ...
  {OUTDIR}/BNF-Ha1/ ...
  {OUTDIR}/BNF-Bon/ ...

Protocol sections:
  §5.3 → historical transient (1850-2014), CO2/Ndep from 20260521 runs
  §5.4 → fixed CO2+Ndep at 2014 (2015-2100), from 20260529_fixed continuation
  §5.5 → SSP585 transient (2015-2100), from 20260523 runs

Usage:
  python3 package_bnfmip_outputs.py [--section 53|54|55|all]
"""

import os
import glob
import argparse
import numpy as np
import xarray as xr

# ── Paths ──────────────────────────────────────────────────────────────────────
SCRATCH   = '/lustre/or-scratch/cades-ccsi/scratch/braghiere'
SCRATCH24 = '/lustre/or-scratch24/scratch/braghiere'
OUTDIR    = '/home/braghiere/BNF_tom/delivery'

SITES    = ['BNF-Man', 'BNF-Ha1', 'BNF-Bon']
SITE_TAG = {'BNF-Man': 'manaus', 'BNF-Ha1': 'ha1', 'BNF-Bon': 'bon'}
EXP_ORDER = ['nofun_baseline', 'fun_transient_only', 'noacc_transient', 'acc_transient']

# §5.3 and §5.4 outputs live in the same 20260521 case run dirs
DATE_HIST  = '20260521'     # §5.3 file prefix
DATE_FIXED = '20260529_fixed'  # §5.4 file prefix (continuation in 20260521 rundir)
DATE_SSP   = '20260523'     # §5.5 (separate run dirs)
STAGE      = 'I20TRCNPRDCTCBC'

# Protocol output variables (BNFMIP Table 2 + key diagnostics)
PROTOCOL_VARS = [
    # Carbon fluxes (gC/m²/s → convert to gC/m²/yr × 86400×365)
    'GPP', 'NPP', 'AR', 'HR', 'NBP', 'NEE',
    # Carbon pools (gC/m²)
    'TOTVEGC', 'TOTSOMC', 'TOTLITC', 'TOTECOSYSC', 'CWDC',
    'LEAFC', 'FROOTC', 'WOODC',
    # Nitrogen fluxes (gN/m²/s → convert to gN/m²/yr)
    'NFIX_TO_SMINN', 'FFIX_TO_SMINN', 'NFIX', 'NET_NMIN', 'NUPTAKE',
    # Nitrogen pools (gN/m²)
    'SMINN', 'TOTVEGN', 'TOTECOSYSN', 'TOTSOMN', 'TOTLITN', 'CWDN', 'LEAFN',
    # Eco-physiological
    'ELAI', 'TSOI_10CM', 'QVEGT',
    # FUN-specific diagnostics
    'COST_NFIX',
]

# Conversion factors for flux variables to annual totals
# Variables in /s → multiply by 86400*365 to get per year
FLUX_VARS = {
    'GPP', 'NPP', 'AR', 'HR', 'NBP', 'NEE',
    'NFIX_TO_SMINN', 'FFIX_TO_SMINN', 'NFIX', 'NET_NMIN', 'NUPTAKE', 'QVEGT',
}
SEC_PER_YR = 86400.0 * 365.0


def casename_hist(exp, site_id):
    tag = SITE_TAG[site_id]
    return f'{exp}_{tag}_{DATE_HIST}_{site_id}_{STAGE}'


def casename_ssp(exp, site_id):
    tag = SITE_TAG[site_id]
    return f'{exp}_ssp585_{tag}_{DATE_SSP}_{site_id}_{STAGE}'


def get_h0_files(run_dir, prefix):
    """Return sorted list of h0 files matching given case prefix."""
    pattern = os.path.join(run_dir, f'{prefix}.clm2.h0.*.nc')
    return sorted(glob.glob(pattern))


def load_annual_means(files, year_start, year_end):
    """
    Load h0 files one at a time (each contains 365 daily steps = 1 year).
    Average each file independently, collect annual-mean datasets.
    Returns xarray Dataset with a 'year' dimension.
    Flux variables are converted to per-year totals.
    """
    if not files:
        return None

    # Detect available protocol vars from the first file
    with xr.open_dataset(files[0], decode_times=True, use_cftime=True) as ds0:
        avail = [v for v in PROTOCOL_VARS if v in ds0]
        missing = set(PROTOCOL_VARS) - set(avail)
        if missing:
            print(f'    NOTE: variables not in files: {sorted(missing)}')
        attrs_map = {v: ds0[v].attrs.copy() for v in avail}

    annual_slices = []
    n = 0
    for f in files:
        with xr.open_dataset(f, decode_times=True, use_cftime=True) as ds:
            # Determine year of this file from time coordinate
            t = ds['time']
            year = int(t.dt.year.values[len(t) // 2])  # use midpoint year
            if year < year_start or year > year_end:
                continue
            # Average all time steps in this file (= annual mean)
            ds_mean = ds[avail].mean('time')
            ds_mean = ds_mean.expand_dims({'year': [year]})
            annual_slices.append(ds_mean.compute())
            n += 1
        if n % 20 == 0:
            print(f'    ... {n} years processed')

    if not annual_slices:
        return None

    print(f'    Loaded {n} annual means')
    ds_annual = xr.concat(annual_slices, dim='year')

    # Restore attributes and convert flux variables
    for v in avail:
        ds_annual[v].attrs = attrs_map[v]
        if v in FLUX_VARS:
            ds_annual[v] = ds_annual[v] * SEC_PER_YR
            old_units = ds_annual[v].attrs.get('units', '')
            new_units = old_units.replace('/s', '/yr').replace('s-1', 'yr-1')
            if new_units == old_units and '/s' not in old_units:
                new_units = old_units + '/yr'
            ds_annual[v].attrs['units'] = new_units

    return ds_annual


def add_global_attrs(ds, exp, site_id, section, year_start, year_end):
    section_labels = {
        '53': 'Historical transient (1850-2014)',
        '54': 'Fixed CO2+Ndep at 2014 (2015-2100)',
        '55': 'SSP585 transient (2015-2100)',
    }
    exp_labels = {
        'nofun_baseline'    : 'Protocol §3.1 Houlton (no FUN)',
        'fun_transient_only': 'Protocol §3.1 Houlton (ELM-FUN)',
        'noacc_transient'   : 'Protocol §3.2 Bytnerowicz no-acclimation',
        'acc_transient'     : 'Protocol §3.3 Bytnerowicz thermal acclimation',
    }
    ds.attrs.update({
        'title'       : f'ELM-FUN BNFMIP - {site_id} - {exp}',
        'model'       : 'ELM-FUN (E3SM Land Model with FUN N-fixation)',
        'site'        : site_id,
        'experiment'  : exp_labels.get(exp, exp),
        'section'     : f'§5.{section[-1]}  {section_labels.get(section, "")}',
        'years'       : f'{year_start}-{year_end}',
        'contact'     : 'renatob@caltech.edu',
        'project'     : 'BNFMIP (Bytnerowicz et al. 2024)',
        'history'     : 'Annual means of ELM h0 daily output; flux vars in units/yr',
        'note_sec53'  : 'CO2 from historical CMIP6; Ndep from ISIMIP3b GFDL-ESM4',
        'note_sec54'  : 'CO2 and Ndep locked at 2014 levels (397.76 ppmv)',
        'note_sec55'  : 'CO2 and Ndep from SSP585 scenario (ISIMIP3b GFDL-ESM4)',
    })
    return ds


def process_section53(exp, site_id, outdir):
    """§5.3 Historical 1850-2014: files with DATE_HIST prefix in HIST run dir."""
    case_hist = casename_hist(exp, site_id)
    run_dir   = f'{SCRATCH}/{case_hist}/run'
    files     = get_h0_files(run_dir, case_hist)
    if not files:
        print(f'    NO FILES: {run_dir}/{case_hist}.clm2.h0.*.nc')
        return

    print(f'  §5.3 {exp} @ {site_id}: {len(files)} files')
    ds = load_annual_means(files, 1850, 2014)
    if ds is None:
        return

    ds = add_global_attrs(ds, exp, site_id, '53', 1850, 2014)
    outfile = os.path.join(outdir, f'{exp}_{site_id}_sec53_1850-2014.nc')
    ds.to_netcdf(outfile)
    print(f'    Saved → {outfile}')


def process_section54(exp, site_id, outdir):
    """§5.4 Fixed CO2/Ndep 2015-2100: files with DATE_FIXED prefix in HIST run dir."""
    case_hist  = casename_hist(exp, site_id)
    run_dir    = f'{SCRATCH}/{case_hist}/run'
    case_fixed = f'{exp}_{SITE_TAG[site_id]}_{DATE_FIXED}_{site_id}_{STAGE}'
    files      = get_h0_files(run_dir, case_fixed)
    if not files:
        print(f'    NO FILES: {run_dir}/{case_fixed}.clm2.h0.*.nc')
        return

    print(f'  §5.4 {exp} @ {site_id}: {len(files)} files')
    ds = load_annual_means(files, 2015, 2100)
    if ds is None:
        return

    ds = add_global_attrs(ds, exp, site_id, '54', 2015, 2100)
    outfile = os.path.join(outdir, f'{exp}_{site_id}_sec54_2015-2100.nc')
    ds.to_netcdf(outfile)
    print(f'    Saved → {outfile}')


def process_section55(exp, site_id, outdir):
    """§5.5 SSP585 2015-2100: files from 20260523 case run dirs.

    A case may have output on BOTH or-scratch and or-scratch24 (e.g. stale
    pre-rerun files on one, the complete run on the other). Pick whichever
    filesystem holds MORE h0 files rather than assuming the first non-empty one.
    """
    case_ssp = casename_ssp(exp, site_id)
    candidates = []
    for base in (SCRATCH, SCRATCH24):
        rd = f'{base}/{case_ssp}/run'
        fl = get_h0_files(rd, case_ssp)
        if fl:
            candidates.append((len(fl), rd, fl))
    if not candidates:
        print(f'    NO FILES (not yet run?): {SCRATCH}|{SCRATCH24}/{case_ssp}/run')
        return
    candidates.sort(reverse=True)   # most files first
    _, run_dir, files = candidates[0]
    if len(candidates) > 1:
        print(f'    NOTE: using {run_dir} ({len(files)} files); '
              f'other location had {candidates[1][0]} files')

    print(f'  §5.5 {exp} @ {site_id}: {len(files)} files')
    ds = load_annual_means(files, 2015, 2100)
    if ds is None:
        return

    ds = add_global_attrs(ds, exp, site_id, '55', 2015, 2100)
    outfile = os.path.join(outdir, f'{exp}_{site_id}_sec55_2015-2100.nc')
    ds.to_netcdf(outfile)
    print(f'    Saved → {outfile}')


def main():
    parser = argparse.ArgumentParser(description='Package BNFMIP annual means')
    parser.add_argument('--section', default='all',
                        choices=['53', '54', '55', 'all'],
                        help='Which protocol section to process')
    parser.add_argument('--site', default=None,
                        help='Only process this site (e.g. BNF-Ha1)')
    parser.add_argument('--exp', default=None,
                        help='Only process this experiment (e.g. fun_transient_only)')
    args = parser.parse_args()

    sites = [args.site] if args.site else SITES
    exps  = [args.exp]  if args.exp  else EXP_ORDER

    os.makedirs(OUTDIR, exist_ok=True)
    for site_id in sites:
        site_outdir = os.path.join(OUTDIR, site_id)
        os.makedirs(site_outdir, exist_ok=True)

        for exp in exps:
            if args.section in ('53', 'all'):
                try:
                    process_section53(exp, site_id, site_outdir)
                except Exception as e:
                    print(f'  ERROR §5.3 {exp} {site_id}: {e}')

            if args.section in ('54', 'all'):
                try:
                    process_section54(exp, site_id, site_outdir)
                except Exception as e:
                    print(f'  ERROR §5.4 {exp} {site_id}: {e}')

            if args.section in ('55', 'all'):
                try:
                    process_section55(exp, site_id, site_outdir)
                except Exception as e:
                    print(f'  ERROR §5.5 {exp} {site_id}: {e}')

    print(f'\nAll done. Output directory: {OUTDIR}')
    print('Files:')
    for root, dirs, fnames in os.walk(OUTDIR):
        for fname in sorted(fnames):
            fpath = os.path.join(root, fname)
            size_mb = os.path.getsize(fpath) / 1024 / 1024
            print(f'  {fpath}  ({size_mb:.1f} MB)')


if __name__ == '__main__':
    main()
