#!/usr/bin/env python
"""Convert the delivered Table-2 .nc set into R-friendly CSVs for Tom.
Produces: (1) one tidy long annual CSV (all combos), (2) per-combo wide monthly CSVs."""
import os, glob, re, numpy as np, xarray as xr, warnings, csv
warnings.filterwarnings('ignore')
D='/home/braghiere/BNF_tom/delivery_table2'
OUT='/home/braghiere/ELM-FUN-BNFMIP/data_csv'
os.makedirs(f'{OUT}/monthly', exist_ok=True)
SITE={'BNF-Man':'Manaus','BNF-Ha1':'Harvard','BNF-Bon':'Bonanza'}
EXP={'nofun_baseline':'NoFUN','fun_transient_only':'FUN_Houlton',
     'noacc_transient':'Bytnerowicz_noAcc','acc_transient':'Bytnerowicz_Acc'}
long_rows=[]
files=sorted(glob.glob(f'{D}/*/*.nc'))
for f in files:
    bn=os.path.basename(f)
    m=re.match(r'(nofun_baseline|fun_transient_only|noacc_transient|acc_transient)_(BNF-\w+)_sec(\d\d)_',bn)
    if not m: continue
    exp,sid,sec=m.group(1),m.group(2),m.group(3)
    site=SITE.get(sid,sid); expn=EXP.get(exp,exp); section=f'5.{sec[-1]}'
    d=xr.open_dataset(f,decode_times=False)
    t=d['time'].values
    vars_=[v for v in d.data_vars if 'time' in d[v].dims]
    lo,hi=(1850,2014) if sec=='53' else (2015,2100)     # strip phantom 1-month boundary records
    keep=(np.floor(t)>=lo)&(np.floor(t)<=hi)
    t=t[keep]
    arrs={v:(d[v].values[:,0] if d[v].ndim>1 else d[v].values)[keep] for v in vars_}
    # (1) wide monthly csv
    wf=f'{OUT}/monthly/{site}_{expn}_sec{sec}.csv'
    with open(wf,'w',newline='') as fh:
        w=csv.writer(fh); w.writerow(['time_decimal_year']+vars_)
        for i in range(len(t)):
            w.writerow([f'{t[i]:.4f}']+[f'{arrs[v][i]:.6g}' for v in vars_])
    # (2) accumulate annual-mean long rows
    yr=np.floor(t).astype(int)
    for v in vars_:
        a=arrs[v]; units=d[v].attrs.get('units','')
        for y in np.unique(yr):
            long_rows.append([site,expn,section,int(y),v,f'{np.nanmean(a[yr==y]):.6g}',units])
    d.close()
# write the tidy long annual master
with open(f'{OUT}/bnfmip_elmfun_table2_annual_long.csv','w',newline='') as fh:
    w=csv.writer(fh); w.writerow(['site','experiment','section','year','variable','value','units'])
    w.writerows(long_rows)
print(f'wrote {len(files)} monthly wide CSVs + 1 annual long CSV ({len(long_rows)} rows)')
print('OUT:',OUT)
