#!/usr/bin/env python3
"""Full Table-2 BNFMIP packager (all variables at MONTHLY resolution, single time axis).
Monthly satisfies Table-2 'monthly mean' fluxes and over-satisfies 'annual' pools.
Handles raw at monthly (12/file) or daily (365/file); resamples daily->monthly.
Usage:
  package_table2.py test        # one-case validation (Man 5.5 fun)
  package_table2.py all         # all resolvable cases
"""
import os, glob, sys, numpy as np, xarray as xr
OUTDIR='/home/braghiere/BNF_tom/delivery_table2'
S1='/lustre/or-scratch24/scratch/braghiere'
S24='/lustre/or-scratch24/scratch/braghiere'
coder=xr.coders.CFDatetimeCoder(use_cftime=True)

# Table2 name -> ELM candidate names (first present wins); special-cased: ET, TNFIX, VEGCBG, TOTROOTC
VMAP={
 'TSOI':['TSOI'],'TSOIBNF':['TSOI_10CM'],'ELAI':['ELAI'],'H2OSOI':['H2OSOI'],'TVEG':['QVEGT'],
 'GPP':['GPP'],'AR':['AR'],'HR':['HR'],'NPP':['NPP'],
 'NPP_NUPTAKE':['NPP_NUPTAKE'],'NPP_PUPTAKE':['NPP_PUPTAKE'],
 'NPP_NACTIVE':['NPP_NACTIVE'],'NPP_NFIX':['NPP_NFIX'],
 'NUPTAKE_NPP_FRACTION':['NUPTAKE_NPP_FRACTION'],'PUPTAKE_NPP_FRACTION':['PUPTAKE_NPP_FRACTION'],
 'COST_NFIX':['COST_NFIX'],'COST_NACTIVE':['COST_NACTIVE'],'COST_PACTIVE':['COST_PACTIVE'],
 'VEGC_TO_LITTER':['LITFALL'],'LITC_TO_SOIL':['LITTERC_TO_SOILC'],
 'SNFIX':['NFIX_TO_SMINN'],'FNFIX':['FFIX_TO_SMINN'],
 'NGAS':['DENIT'],'NLEACH':['SMIN_NO3_LEACHED','SMINN_LEACHED'],'NNETMIN':['NET_NMIN'],
 'NUP':['NUPTAKE','SMINN_TO_PLANT'],'FN2O':['F_N2O_DENIT'],
 'PLOSS':['SMINP_LEACHED'],'PNETMIN':['NET_PMIN'],'PUP':['PUPTAKE','SMINP_TO_PLANT'],
 'TOTVEGC':['TOTVEGC'],'TOTECOC':['TOTECOSYSC'],'VEGCAG':['TOTVEGC_ABG'],
 'TOTLITC':['TOTLITC'],'SOILC':['TOTSOMC'],'LEAFC':['LEAFC'],'WOODC':['WOODC','DEADSTEMC'],
 'CROOTC':['LIVECROOTC'],'FROOTC':['FROOTC'],'CWDC':['CWDC'],
 'TOTVEGN':['TOTVEGN'],'TOTECON':['TOTECOSYSN'],'SMINN':['SMINN'],'TOTLITN':['TOTLITN'],
 'SOILN':['TOTSOMN'],'LEAFN':['LEAFN'],'WOODN':['DEADSTEMN','WOODN'],'FROOTN':['FROOTN'],
 'CWDN':['CWDN'],'TOTSOMN':['TOTSOMN'],
 'TOTVEGP':['TOTVEGP'],'TOTECOP':['TOTECOSYSP'],'SMINP':['SMINP'],'TOTLITP':['TOTLITP'],
 'SOILP':['TOTSOMP'],'LEAFP':['LEAFP'],'WOODP':['DEADSTEMP','WOODP'],'FROOTP':['FROOTP'],
 'CWDP':['CWDP'],'TOTSOMP':['TOTSOMP'],
}
C_FLUX={'GPP','AR','HR','NPP','NPP_NUPTAKE','NPP_PUPTAKE','NPP_NACTIVE','NPP_NFIX','VEGC_TO_LITTER','LITC_TO_SOIL'}
N_FLUX={'SNFIX','FNFIX','TNFIX','NGAS','NLEACH','NNETMIN','NUP','FN2O'}
P_FLUX={'PLOSS','PNETMIN','PUP'}
W_FLUX={'TVEG','ET'}
POOLC={'TOTVEGC','TOTECOC','VEGCAG','VEGCBG','TOTLITC','SOILC','LEAFC','WOODC','TOTROOTC','CROOTC','FROOTC','CWDC'}
POOLN={'TOTVEGN','TOTECON','SMINN','TOTLITN','SOILN','LEAFN','WOODN','FROOTN','CWDN','TOTSOMN'}
POOLP={'TOTVEGP','TOTECOP','SMINP','TOTLITP','SOILP','LEAFP','WOODP','FROOTP','CWDP','TOTSOMP'}
FRAC={'NUPTAKE_NPP_FRACTION','PUPTAKE_NPP_FRACTION'}   # dimensionless, no scaling
COSTN={'COST_NFIX','COST_NACTIVE'}                     # gN/gC, no scaling
COSTP={'COST_PACTIVE'}                                 # gP/gC, no scaling

def pick(ds,cands):
    for c in cands:
        if c in ds.variables: return c
    return None

def monthly12(da,nt):
    """Return 12 monthly means (over leading month dim) as (12,...) array."""
    if nt>=300:  # daily
        return da.groupby('time.month').mean('time').values
    return da.values  # already 12 monthly

def process(rundirs,pfx,y0,y1,site,exp,sec):
    if isinstance(rundirs,str): rundirs=[rundirs]
    files=[]
    for rd in rundirs:
        files=sorted(glob.glob(f'{rd}/{pfx}.clm2.h0.*.nc'))
        if files: break
    if not files: return f'  {site}/{exp}/sec{sec}: NO FILES'
    with xr.open_dataset(files[0],decode_times=False) as d0:
        present={k:pick(d0,v) for k,v in VMAP.items()}
        et_parts=[p for p in ['QVEGT','QVEGE','QSOIL'] if p in d0.variables]
    cols={}          # varname -> list of (year, (12,...) array)
    for f in files:
        with xr.open_dataset(f,decode_times=coder) as ds:
            yv=ds['time'].dt.year.values; y=int(yv[len(yv)//2])
            if y<y0 or y>y1: continue
            nt=ds.dims['time']
            for k,elm in present.items():
                if elm is None: continue
                cols.setdefault(k,[]).append((y,monthly12(ds[elm],nt)))
            if et_parts:
                da=sum(ds[p] for p in et_parts)
                cols.setdefault('ET',[]).append((y,monthly12(da,nt)))
            if 'NFIX_TO_SMINN' in ds:
                parts=[ds[p] for p in ['NFIX_TO_SMINN','FFIX_TO_SMINN'] if p in ds]
                cols.setdefault('TNFIX',[]).append((y,monthly12(sum(parts),nt)))
            if present.get('TOTVEGC') and present.get('VEGCAG'):
                vbg=monthly12(ds[present['TOTVEGC']],nt)-monthly12(ds[present['VEGCAG']],nt)
                cols.setdefault('VEGCBG',[]).append((y,vbg))
            if present.get('FROOTC'):
                tr=monthly12(ds[present['FROOTC']],nt)+(monthly12(ds[present['CROOTC']],nt) if present.get('CROOTC') else 0)
                cols.setdefault('TOTROOTC',[]).append((y,tr))
    if not cols: return f'  {site}/{exp}/sec{sec}: no in-range data'
    years=sorted({y for lst in cols.values() for y,_ in lst})
    tcoord=np.array([y+(m-0.5)/12.0 for y in years for m in range(12)])
    out=xr.Dataset(coords={'time':tcoord})
    for k,lst in cols.items():
        d=dict(lst); stk=[d[y] for y in years if y in d]
        if not stk: continue
        a=np.concatenate([s.reshape(12,-1) for s in stk],axis=0)
        a=np.where(np.abs(a)>1e30,np.nan,a)            # mask model spval fill (diagnostics w/o _FillValue)
        if k in C_FLUX|N_FLUX|P_FLUX: a*=86.4          # g/m2/s -> kg/m2/day
        elif k in W_FLUX: a*=86400.0                    # mm/s -> kg/m2/day
        elif k in POOLC|POOLN|POOLP: a*=1e-3            # g/m2 -> kg/m2
        if a.shape[1]==1:
            out[k]=xr.DataArray(a[:,0],dims=['time'])
        else:
            out[k]=xr.DataArray(a,dims=['time','lev'])
        uu=('kgC/m2/day' if k in C_FLUX else 'kgN/m2/day' if k in N_FLUX else 'kgP/m2/day'
            if k in P_FLUX else 'kgH2O/m2/day' if k in W_FLUX else 'kgC/m2' if k in POOLC
            else 'kgN/m2' if k in POOLN else 'kgP/m2' if k in POOLP
            else 'K' if k in ('TSOI','TSOIBNF') else 'm2/m2' if k=='ELAI' else 'kgH2O/m2' if k=='H2OSOI'
            else '-' if k in FRAC else 'gN/gC' if k in COSTN else 'gP/gC' if k in COSTP else '')
        out[k].attrs['units']=uu
    out.attrs.update({'title':f'ELM-FUN BNFMIP Table-2 {site} {exp} sec{sec}','site':site,
      'experiment':exp,'section':f'5.{sec[-1]}','contact':'renatob@caltech.edu',
      'note':'monthly resolution (time=decimal yr); pools reported monthly (annualize by yearly mean)'})
    os.makedirs(f'{OUTDIR}/{site}',exist_ok=True)
    rng='1850-2014' if sec=='53' else '2015-2100'
    o=f'{OUTDIR}/{site}/{exp}_{site}_sec{sec}_{rng}_table2.nc'
    out.to_netcdf(o)
    nv=len([v for v in out.data_vars])
    return f'  {site}/{exp}/sec{sec}: {nv} vars, {len(years)} yr -> {os.path.basename(o)}'

TAG={'BNF-Man':'manaus','BNF-Ha1':'ha1','BNF-Bon':'bon'}
EXPS=['nofun_baseline','fun_transient_only','noacc_transient','acc_transient']

def resolve(site,exp,sec):
    tag=TAG[site]; stem=f'{exp}_{tag}'
    hist=[f'{S1}/{stem}_20260521_{site}_I20TRCNPRDCTCBC/run']
    if sec=='53': return hist, f'{stem}_20260521_{site}_I20TRCNPRDCTCBC',1850,2014
    if sec=='54': return hist, f'{stem}_20260529_fixed_{site}_I20TRCNPRDCTCBC',2015,2100
    # sec 55: ALL sites use the repurposed 20260529_fixed continuation run
    # (clean branch from the §5.3 2015 restart + transient SSP5-8.5 CO2/Ndep).
    # This holds §5.5 data after the repurpose; §5.4 was packaged before it.
    return hist, f'{stem}_20260529_fixed_{site}_I20TRCNPRDCTCBC',2015,2100

if __name__=='__main__':
    mode=sys.argv[1] if len(sys.argv)>1 else 'all'
    if mode=='test':
        r=[f'{S1}/fun_transient_only_manaus_20260521_BNF-Man_I20TRCNPRDCTCBC/run']
        print(process(r,'fun_transient_only_manaus_20260529_fixed_BNF-Man_I20TRCNPRDCTCBC',2015,2100,'BNF-Man','fun_transient_only','55'))
    else:
        # modes: 'all' (all sec), 'man54' (Man §5.4 only), 'sec55' (only §5.5, all sites)
        skip_man54 = (mode not in ('man54',))
        secs = ['55'] if mode=='sec55' else ['53','54','55']
        for site in ['BNF-Man','BNF-Ha1','BNF-Bon']:
            for exp in EXPS:
                for sec in secs:
                    if mode=='all' and skip_man54 and site=='BNF-Man' and sec=='54':
                        print(f'  BNF-Man/{exp}/sec54: SKIP (raw overwritten)'); continue
                    if mode=='man54' and not(site=='BNF-Man' and sec=='54'): continue
                    try:
                        rundirs,pfx,y0,y1=resolve(site,exp,sec)
                        print(process(rundirs,pfx,y0,y1,site,exp,sec),flush=True)
                    except Exception as e:
                        print(f'  {site}/{exp}/sec{sec}: ERROR {str(e)[:60]}',flush=True)
