#!/usr/bin/env python
"""After corrected reruns: compute new pathway partitioning + compare key fluxes old-vs-new.
Writes a text summary to /home/braghiere/pipeline/COMPARISON.txt. No files overwritten."""
import glob,re,csv,numpy as np,xarray as xr,warnings,os; warnings.filterwarnings('ignore')
RR='/lustre/or-scratch24/scratch/braghiere'; SPY=86400*365.0
SITES={'man':'Manaus','ha1':'Harvard'}
# BEFORE (buggy) pathway partitioning % of NUPTAKE, from pre-fix audit (agent 2):
BEFORE={'Manaus':dict(myc=3.5,nonmyc=68.4,fix=11.7,retrans=16.4),
        'Harvard':dict(myc=3.2,nonmyc=65.5,fix=17.0,retrans=14.2)}
out=[]
out.append("ELM-FUN corrected reruns — pathway partitioning (present-day 2005-2014, % of NUPTAKE)")
out.append("BEFORE = pre-fix (buggy); AFTER = corrected. Manaus & Harvard, FUN(Houlton).\n")
def part(cfg):
    d=glob.glob(f'{RR}/su_{cfg}_*/run')
    if not d: return None
    fs=[f for f in sorted(glob.glob(f'{d[0]}/*.clm2.h0.*.nc')) if 2005<=int(re.search(r'h0\.(\d+)',f).group(1))<=2014]
    if not fs: return None
    acc={k:[] for k in ['NAM','NECM','NNONMYC','NFIX_TO_SMINN','NRETRANS','NUPTAKE']}
    for f in fs:
        x=xr.open_dataset(f,decode_times=False)
        for k in acc:
            if k in x: a=x[k].values; a=a[...,0] if a.ndim>1 else a; acc[k].append(float(np.nanmean(a)))
        x.close()
    m={k:np.mean(v)*SPY for k,v in acc.items() if v}
    tot=m.get('NUPTAKE',np.nan)
    if not tot or np.isnan(tot): return None
    myc=(m.get('NAM',0)+m.get('NECM',0)); 
    return dict(myc=100*myc/tot, nonmyc=100*m.get('NNONMYC',0)/tot,
                fix=100*m.get('NFIX_TO_SMINN',0)/tot, retrans=100*m.get('NRETRANS',0)/tot)
for tag,site in SITES.items():
    a=part(f'fun_{tag}')
    b=BEFORE[site]
    out.append(f"{site} (fun):")
    if a:
        for k in ['myc','nonmyc','fix','retrans']:
            out.append(f"   {k:8s} BEFORE {b[k]:5.1f}%  ->  AFTER {a[k]:5.1f}%   (Δ {a[k]-b[k]:+.1f})")
    else:
        out.append("   AFTER: no corrected output found yet")
    out.append("")
# key-flux old vs new from CSVs
old_f='/home/braghiere/ELM-FUN-BNFMIP/data_csv_corrected/bnfmip_elmfun_table2_annual_long.csv'
new_f='/home/braghiere/ELM-FUN-BNFMIP/data_csv_corrected_v2/bnfmip_elmfun_table2_annual_long.csv'
def pd_(f,site,exp,var):
    if not os.path.exists(f): return np.nan
    v=[float(r['value']) for r in csv.DictReader(open(f)) if r['site']==site and r['experiment']==exp and r['variable']==var and r['section']=='5.3' and 2005<=int(r['year'])<=2014]
    return np.mean(v) if v else np.nan
out.append("Key fluxes present-day, OLD(delivered) vs NEW(corrected), FUN_Houlton (units as in CSV):")
for site in ['Manaus','Harvard']:
    out.append(f" {site}:")
    for var in ['GPP','NPP','SNFIX','NUP','NPP_NUPTAKE','NPP_PUPTAKE']:
        o=pd_(old_f,site,'FUN_Houlton',var); n=pd_(new_f,site,'FUN_Houlton',var)
        pc=100*(n-o)/o if o and not np.isnan(o) and not np.isnan(n) else float('nan')
        out.append(f"   {var:12s} old={o:.4g}  new={n:.4g}  ({pc:+.0f}%)")
    out.append("")
txt="\n".join(out)
open('/home/braghiere/pipeline/COMPARISON.txt','w').write(txt)
print(txt)
