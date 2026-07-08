#!/usr/bin/env python3
"""Package the 4 repurposed Manaus SSP585 (§5.5) runs into sec55 delivery files.
These runs live in the 20260521 run dirs, named '..._20260529_fixed_...', with
MONTHLY h0 output. Group months by calendar year -> annual mean, 2015-2100."""
import os, glob, numpy as np, xarray as xr

RUN_BASE='/lustre/or-scratch/cades-ccsi/scratch/braghiere'
OUT='/home/braghiere/BNF_tom/delivery/BNF-Man'
EXPS=['nofun_baseline','fun_transient_only','noacc_transient','acc_transient']
PVARS=['GPP','NPP','AR','HR','NBP','NEE','TOTVEGC','TOTSOMC','TOTLITC','TOTECOSYSC','CWDC',
 'LEAFC','FROOTC','WOODC','NFIX_TO_SMINN','FFIX_TO_SMINN','NFIX','NET_NMIN','NUPTAKE',
 'SMINN','TOTVEGN','TOTECOSYSN','TOTSOMN','TOTLITN','CWDN','LEAFN','ELAI','TSOI_10CM','QVEGT','COST_NFIX']
FLUX={'GPP','NPP','AR','HR','NBP','NEE','NFIX_TO_SMINN','FFIX_TO_SMINN','NFIX','NET_NMIN','NUPTAKE','QVEGT'}
SPY=86400.0*365.0
coder=xr.coders.CFDatetimeCoder(use_cftime=True)

def run(exp):
    rundir=f'{RUN_BASE}/{exp}_manaus_20260521_BNF-Man_I20TRCNPRDCTCBC/run'
    pfx=f'{exp}_manaus_20260529_fixed_BNF-Man_I20TRCNPRDCTCBC'
    files=sorted(glob.glob(f'{rundir}/{pfx}.clm2.h0.*.nc'))
    if not files:
        print(f'  {exp}: NO FILES'); return
    with xr.open_dataset(files[0],decode_times=coder) as d0:
        avail=[v for v in PVARS if v in d0]
        attrs={v:d0[v].attrs.copy() for v in avail}
    by_year={}
    for f in files:
        with xr.open_dataset(f,decode_times=coder) as ds:
            yr=int(ds['time'].dt.year.values[0])
            if yr<2015 or yr>2100: continue
            m=ds[avail].mean('time').compute()
            by_year.setdefault(yr,[]).append(m)
    if not by_year:
        print(f'  {exp}: no 2015-2100 data'); return
    years=sorted(by_year)
    slices=[xr.concat(by_year[y],dim='m').mean('m').expand_dims({'year':[y]}) for y in years]
    ds=xr.concat(slices,dim='year')
    for v in avail:
        ds[v].attrs=attrs[v]
        if v in FLUX:
            ds[v]=ds[v]*SPY
            u=ds[v].attrs.get('units','')
            ds[v].attrs['units']=u.replace('/s','/yr').replace('s-1','yr-1') if '/s' in u or 's-1' in u else (u+'/yr')
    ds.attrs.update({'title':f'ELM-FUN BNFMIP - BNF-Man - {exp}','site':'BNF-Man',
      'section':'§5.5 SSP585 transient (2015-2100)','years':'2015-2100',
      'contact':'renatob@caltech.edu','project':'BNFMIP (Bytnerowicz et al. 2024)',
      'note':'SSP585 transient CO2+Ndep; run via 20260529 case repurposed with transient forcing (ssp585 case build was defective)'})
    out=f'{OUT}/{exp}_BNF-Man_sec55_2015-2100.nc'
    ds.to_netcdf(out)
    g=float(ds['GPP'].isel(year=slice(-10,None)).mean().values)
    v=float(ds['TOTVEGC'].isel(year=slice(-10,None)).mean().values)
    print(f'  {exp}: {len(years)} yrs -> {os.path.basename(out)}  (end GPP={g:.0f} VegC={v:.0f} {"ALIVE" if g>30 else "DEAD"})')

if __name__=='__main__':
    for e in EXPS: run(e)
