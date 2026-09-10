import glob,re,csv,collections,numpy as np,xarray as xr,warnings; warnings.filterwarnings('ignore')
RR='/lustre/or-scratch24/scratch/braghiere'; SPY=86400*365.0
def newpart(cfg):  # corrected rerun output
    d=glob.glob(f'{RR}/su_{cfg}_*/run')
    fs=[f for f in sorted(glob.glob(f'{d[0]}/*.clm2.h0.*.nc')) if 2005<=int(re.search(r"h0\.(\d+)",f).group(1))<=2014]
    acc=collections.defaultdict(list)
    for f in fs:
        x=xr.open_dataset(f,decode_times=False)
        for k in ['NAM','NECM','NNONMYC','NFIX_TO_SMINN','NRETRANS','NUPTAKE','GPP','NPP','TOTVEGC','TOTSOMC']:
            if k in x: a=x[k].values; a=a[...,0] if a.ndim>1 else a; acc[k].append(float(np.nanmean(a)))
        x.close()
    return {k:np.mean(v) for k,v in acc.items()}
old={}
for r in csv.DictReader(open('/home/braghiere/ELM-FUN-BNFMIP/data_csv_corrected/bnfmip_elmfun_table2_annual_long.csv')):
    if r['site']=='Bonanza' and r['experiment']=='FUN_Houlton' and r['section']=='5.3' and 2005<=int(r['year'])<=2014:
        old.setdefault(r['variable'],[]).append(float(r['value']))
old={k:np.mean(v) for k,v in old.items()}
n=newpart('fun_bon')
print("Bonanza FUN_Houlton present-day: OLD(buggy) vs CORRECTED-code rerun")
tot=n.get('NUPTAKE',np.nan)*SPY
print(f"  mycorrhizal %NUPTAKE  new={100*(n.get('NAM',0)+n.get('NECM',0))/n['NUPTAKE']:.2f}%")
print(f"  non-myc     %NUPTAKE  new={100*n.get('NNONMYC',0)/n['NUPTAKE']:.2f}%")
for k,csvv,sc in [('GPP','GPP',365000),('NPP','NPP',365000),('SNFIX(fix)','NFIX_TO_SMINN',SPY),('TOTVEGC','TOTVEGC',1),('SOILC','TOTSOMC',1)]:
    o=old.get(csvv,np.nan)*(365000 if csvv in('GPP','NPP') else (365000 if csvv=='NFIX_TO_SMINN' else 1))
    if csvv=='NFIX_TO_SMINN': nv=n.get('NFIX_TO_SMINN',np.nan)*SPY
    elif csvv in('GPP','NPP'): nv=n.get(csvv,np.nan)*365000
    else: nv=n.get('TOTSOMC' if k=='SOILC' else csvv,np.nan)
    d=100*(nv-o)/o if o else np.nan
    print(f"  {k:12s} old={o:.4g}  corrected={nv:.4g}  ({d:+.2f}%)")
