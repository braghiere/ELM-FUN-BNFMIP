#!/usr/bin/env python
"""Dask-free packaging of the rebuild continuous runs into the gallery's Table-2 format.
Slices each continuous 1850-2100 run into sec53 (1850-2014) and sec55 (2015-2100).
Also packages sec54 (fixed CO2/Ndep) from sec54_* cases where present."""
import glob, re, os, sys
import numpy as np, xarray as xr
RR='/lustre/or-scratch24/scratch/braghiere'
OUT='/home/braghiere/BNF_tom/delivery_rebuild'

T2=['GPP','NPP','AR','HR','NEE','TLAI','TSOI_10CM','QVEGT','TWS','TBOT',
    'TOTVEGC','TOTECOSYSC','TOTSOMC','TOTLITC','CWDC','LEAFC','FROOTC','DEADSTEMC',
    'NFIX_TO_SMINN','FFIX_TO_SMINN','NET_NMIN','SMINN','TOTVEGN','TOTECOSYSN','TOTSOMN','LEAFN',
    'SMINP','TOTVEGP','TOTSOMP','LEAFP','SMIN_NO3','SMIN_NH4']

# rebuild case-prefix -> (sid, exp) in gallery naming
MAP={
 'sc_fun_transient_only_bon':('BNF-Bon','fun_transient_only'),
 'sc_noacc_transient_bon':('BNF-Bon','noacc_transient'),
 'sc_acc_transient_bon':('BNF-Bon','acc_transient'),
 'ft_nofun_baseline_bon':('BNF-Bon','nofun_baseline'),
 'mpd_fun_man':('BNF-Man','fun_transient_only'),
 'mpd_noacc_transient_man':('BNF-Man','noacc_transient'),
 'mpd_acc_transient_man':('BNF-Man','acc_transient'),
 'mpd_fun_ha1v2':('BNF-Ha1','fun_transient_only'),
 'mpd_noacc_transient_ha1':('BNF-Ha1','noacc_transient'),
 'mpd_acc_transient_ha1':('BNF-Ha1','acc_transient'),
 # nofun for Man/Ha1 and all sec54 handled separately if present
}

def to_decyr(times):
    out=[]
    for t in times:
        y=int(t.year)
        doy=t.timetuple().tm_yday if hasattr(t,'timetuple') else int(getattr(t,'dayofyr',1))
        out.append(y+(doy-0.5)/365.0)   # noleap; floor(decyr)=calendar year
    return np.array(out,dtype='float64')

def open_concat(files):
    dss=[]
    for f in files:
        try:
            d=xr.open_dataset(f,decode_times=True)     # decode -> cftime dates
            keep=[v for v in T2 if v in d]
            if keep: dss.append(d[keep])
        except Exception as e:
            print('   skip',os.path.basename(f),e)
    if not dss: return None
    ds=xr.concat(dss,dim='time')
    decyr=to_decyr(ds['time'].values)                   # -> decimal-year float
    ds=ds.assign_coords(time=('time',decyr))
    ds['time'].attrs={}                                 # strip CF units (match delivered format)
    return ds

def package(prefix, sid, exp):
    rd=glob.glob(f'{RR}/{prefix}_repro20260709_*/run')
    if not rd: rd=glob.glob(f'{RR}/{prefix}_*/run')
    if not rd: print(f'  {sid} {exp}: NO run dir'); return 0
    files=sorted(glob.glob(f'{rd[0]}/*.clm2.h0.*.nc'), key=lambda f:re.search(r'h0\.(\d{4})',f).group(1))
    if not files: print(f'  {sid} {exp}: no h0'); return 0
    ds=open_concat(files)
    if ds is None: print(f'  {sid} {exp}: concat failed'); return 0
    yr=np.floor(ds['time'].values).astype(int)
    os.makedirs(f'{OUT}/{sid}',exist_ok=True); n=0
    for sec,lo,hi,rng in [('sec53',1850,2014,'1850-2014'),('sec55',2015,2100,'2015-2100')]:
        m=(yr>=lo)&(yr<=hi)
        if m.sum()==0: continue
        sub=ds.isel(time=np.where(m)[0])
        sub.attrs['source_case']=prefix+' (rebuild repro20260709)'
        of=f'{OUT}/{sid}/{exp}_{sid}_{sec}_{rng}_table2.nc'
        sub.to_netcdf(of); n+=1
    ds.close(); print(f'  {sid} {exp}: packaged {n} sections ({len(files)} yrs)'); return n

def package_sec54(sid, exp):
    # sec54_* cases (fixed CO2/Ndep) — Bon only for now
    ekey={'fun_transient_only':'fun','noacc_transient':'noacc','acc_transient':'acc','nofun_baseline':'nofun'}[exp]
    site={'BNF-Bon':'bon','BNF-Man':'man','BNF-Ha1':'ha1'}[sid]
    rd=glob.glob(f'{RR}/sec54_{ekey}_{site}_repro20260709_*/run')
    if not rd: return 0
    files=sorted(glob.glob(f'{rd[0]}/*.clm2.h0.*.nc'), key=lambda f:re.search(r'h0\.(\d{4})',f).group(1))
    if not files: return 0
    ds=open_concat(files)
    if ds is None: return 0
    os.makedirs(f'{OUT}/{sid}',exist_ok=True)
    ds.attrs['source_case']=f'sec54_{ekey}_{site} (rebuild, fixed CO2/Ndep)'
    of=f'{OUT}/{sid}/{exp}_{sid}_sec54_2015-2100_table2.nc'
    ds.to_netcdf(of); ds.close(); print(f'  {sid} {exp}: packaged sec54'); return 1

print('==== packaging rebuild §5.3+§5.5 ====')
tot=0
for pref,(sid,exp) in MAP.items(): tot+=package(pref,sid,exp)
print('==== packaging §5.4 where present ====')
for sid in ['BNF-Bon','BNF-Man','BNF-Ha1']:
    for exp in ['nofun_baseline','fun_transient_only','noacc_transient','acc_transient']:
        tot+=package_sec54(sid,exp)
print(f'\nTOTAL sections packaged: {tot}')
# report completeness
print('\n==== delivery_rebuild inventory ====')
for sid in ['BNF-Man','BNF-Ha1','BNF-Bon']:
    fs=sorted(glob.glob(f'{OUT}/{sid}/*.nc'))
    print(f'  {sid}: {len(fs)} files')
    for f in fs: print('     ',os.path.basename(f))
print('PACKAGE_DONE')
