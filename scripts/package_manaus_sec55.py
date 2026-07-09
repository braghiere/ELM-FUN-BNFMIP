#!/usr/bin/env python3
"""Package the repurposed SSP585 (§5.5) runs into sec55 annual delivery files.
All sites' §5.5 now live in the 20260521 run dirs, named '..._20260529_fixed_...'
(the §5.4 cases repurposed with transient CO2/Ndep — a clean continuation from the
§5.3 2015 restart, so continuous at 2015). MONTHLY h0 output -> annual mean 2015-2100."""
import os, glob, numpy as np, xarray as xr

RUN_BASE='/lustre/or-scratch24/scratch/braghiere'
OUTBASE='/home/braghiere/BNF_tom/delivery'
SITES={'BNF-Man':'manaus','BNF-Ha1':'ha1','BNF-Bon':'bon'}
EXPS=['nofun_baseline','fun_transient_only','noacc_transient','acc_transient']
PVARS=['GPP','NPP','AR','HR','NBP','NEE','TOTVEGC','TOTSOMC','TOTLITC','TOTECOSYSC','CWDC',
 'LEAFC','FROOTC','WOODC','NFIX_TO_SMINN','FFIX_TO_SMINN','NFIX','NET_NMIN','NUPTAKE',
 'SMINN','TOTVEGN','TOTECOSYSN','TOTSOMN','TOTLITN','CWDN','LEAFN','ELAI','TSOI_10CM','QVEGT','COST_NFIX']
FLUX={'GPP','NPP','AR','HR','NBP','NEE','NFIX_TO_SMINN','FFIX_TO_SMINN','NFIX','NET_NMIN','NUPTAKE','QVEGT'}
SPY=86400.0*365.0
coder=xr.coders.CFDatetimeCoder(use_cftime=True)

def run(site,tag,exp):
    rundir=f'{RUN_BASE}/{exp}_{tag}_20260521_BNF-{site.split("-")[1]}_I20TRCNPRDCTCBC/run'
    pfx=f'{exp}_{tag}_20260529_fixed_BNF-{site.split("-")[1]}_I20TRCNPRDCTCBC'
    files=sorted(glob.glob(f'{rundir}/{pfx}.clm2.h0.*.nc'))
    if not files:
        print(f'  {site}/{exp}: NO FILES ({pfx})'); return
    with xr.open_dataset(files[0],decode_times=coder) as d0:
        avail=[v for v in PVARS if v in d0]; attrs={v:d0[v].attrs.copy() for v in avail}
    by_year={}
    for f in files:
        with xr.open_dataset(f,decode_times=coder) as ds:
            yr=int(ds['time'].dt.year.values[0])
            if yr<2015 or yr>2100: continue
            by_year.setdefault(yr,[]).append(ds[avail].mean('time').compute())
    if not by_year: print(f'  {site}/{exp}: no 2015-2100 data'); return
    years=sorted(by_year)
    ds=xr.concat([xr.concat(by_year[y],dim='m').mean('m').expand_dims({'year':[y]}) for y in years],dim='year')
    for v in avail:
        ds[v].attrs=attrs[v]
        if v in FLUX:
            ds[v]=ds[v]*SPY; u=ds[v].attrs.get('units','')
            ds[v].attrs['units']=u.replace('/s','/yr').replace('s-1','yr-1') if ('/s' in u or 's-1' in u) else (u+'/yr')
    ds.attrs.update({'title':f'ELM-FUN BNFMIP - {site} - {exp}','site':site,
      'section':'5.5 SSP585 transient (2015-2100)','years':'2015-2100','contact':'renatob@caltech.edu',
      'note':'SSP585 transient CO2+Ndep; continuation of the 5.4 case (branch from 5.3 2015 restart) with transient forcing'})
    out=f'{OUTBASE}/{site}/{exp}_{site}_sec55_2015-2100.nc'
    ds.to_netcdf(out)
    g=float(ds['GPP'].isel(year=slice(-10,None)).mean().values)
    v=float(ds['TOTVEGC'].isel(year=slice(-10,None)).mean().values)
    print(f'  {site}/{exp}: {len(years)} yrs -> {os.path.basename(out)}  (end GPP={g:.0f} VegC={v:.0f} {"ALIVE" if g>30 else "DEAD"})')

if __name__=='__main__':
    import sys
    only=sys.argv[1] if len(sys.argv)>1 else None   # optional: a site code to restrict
    for site,tag in SITES.items():
        if only and site!=only: continue
        for exp in EXPS: run(site,tag,exp)
