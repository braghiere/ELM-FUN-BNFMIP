#!/usr/bin/env python
"""Evaluate corrected(v2) fluxes & pools of C/N/P vs literature and vs old(buggy) delivered.
Reads the two annual_long CSVs. Figures + flagged table. No files overwritten."""
import csv,collections,numpy as np,warnings,matplotlib
warnings.filterwarnings('ignore'); matplotlib.use('Agg'); import matplotlib.pyplot as plt
OLD='/home/braghiere/ELM-FUN-BNFMIP/data_csv_corrected/bnfmip_elmfun_table2_annual_long.csv'
NEW='/home/braghiere/ELM-FUN-BNFMIP/data_csv_corrected_v2/bnfmip_elmfun_table2_annual_long.csv'
def load(f):
    D=collections.defaultdict(lambda: collections.defaultdict(list))  # (site,exp,var)-> {year:val}
    T=collections.defaultdict(dict)
    for r in csv.DictReader(open(f)):
        if r['section']!='5.3': continue
        T[(r['site'],r['experiment'],r['variable'])][int(r['year'])]=float(r['value'])
    return T
OLDD,NEWD=load(OLD),load(NEW)
FLUX365=365000.0  # kg/m2/day -> g/m2/yr
def pd_(D,site,var,exp='FUN_Houlton',lo=2005,hi=2014):
    d=D.get((site,exp,var),{}); v=[d[y] for y in d if lo<=y<=hi]; return np.mean(v) if v else np.nan
# literature present-day ranges (units noted). BNF = symbiotic+free total unless noted.
LIT={'Manaus':dict(GPP=(2500,3500,'gC/m2/yr'),NPP=(900,1400,'gC/m2/yr'),TOTVEGC=(12,22,'kgC/m2'),
        SOILC=(6,15,'kgC/m2'),BNF=(1.5,3.6,'gN/m2/yr'),TOTVEGN=(0.15,0.4,'kgN/m2'),SMINP=(0.1,5,'gP/m2')),
     'Harvard':dict(GPP=(1200,1600,'gC/m2/yr'),NPP=(500,800,'gC/m2/yr'),TOTVEGC=(9,14,'kgC/m2'),
        SOILC=(8,18,'kgC/m2'),BNF=(0.3,2.7,'gN/m2/yr'),TOTVEGN=(0.1,0.3,'kgN/m2'),SMINP=(0.1,5,'gP/m2')),
     'Bonanza':dict(GPP=(400,900,'gC/m2/yr'),NPP=(150,400,'gC/m2/yr'),TOTVEGC=(2,8,'kgC/m2'),
        SOILC=(15,40,'kgC/m2'),BNF=(0.2,2.0,'gN/m2/yr'),TOTVEGN=(0.02,0.2,'kgN/m2'),SMINP=(0.1,5,'gP/m2'))}
def val(D,site,which):
    if which=='GPP': return pd_(D,site,'GPP')*FLUX365
    if which=='NPP': return pd_(D,site,'NPP')*FLUX365
    if which=='TOTVEGC': return pd_(D,site,'TOTVEGC')      # kgC/m2
    if which=='SOILC': return pd_(D,site,'SOILC')
    if which=='BNF': return (pd_(D,site,'SNFIX')+pd_(D,site,'FNFIX'))*FLUX365  # gN/m2/yr
    if which=='TOTVEGN': return pd_(D,site,'TOTVEGN')
    if which=='SMINP': return pd_(D,site,'SMINP')*1000     # kg->g/m2
print("=== CORRECTED(v2) fluxes & pools vs LITERATURE  [FUN Houlton, present-day 2005-2014] ===")
print(f"{'site':9s}{'var':9s}{'OLD(buggy)':>11}{'NEW(fixed)':>11}{'lit range':>16}{'  verdict'}")
flags=[]
for site in ['Manaus','Harvard','Bonanza']:
    for which in ['GPP','NPP','TOTVEGC','SOILC','BNF','TOTVEGN','SMINP']:
        o=val(OLDD,site,which); n=val(NEWD,site,which); lo,hi,u=LIT[site][which]
        inr = lo<=n<=hi
        verd='OK' if inr else ('HIGH' if n>hi else 'LOW')
        if not inr: flags.append(f"{site} {which}: {n:.2f} {u} (lit {lo}-{hi})  {verd}")
        print(f"{site:9s}{which:9s}{o:11.2f}{n:11.2f}{f'{lo}-{hi}':>16}  {verd} [{u}]")
print("\n=== BNF detail (symbiotic SNFIX gN/m2/yr) all schemes, present-day + 2090s ===")
for site in ['Manaus','Harvard','Bonanza']:
    row=f"  {site:9s}"
    for exp in ['FUN_Houlton','Bytnerowicz_noAcc','Bytnerowicz_Acc']:
        s05=pd_(NEWD,site,'SNFIX',exp,2005,2014)*FLUX365
        s90=pd_(NEWD,site,'SNFIX',exp,2090,2099)*FLUX365
        row+=f"  {exp.split('_')[-1][:5]}:{s05:.2f}->{s90:.2f}"
    print(row)
print("\n### FLAGS (out-of-range):")
for f in flags: print("  ⚠ "+f)
if not flags: print("  none")

# ---- Figure A: present-day vs literature bars (old vs new) ----
fig,axs=plt.subplots(2,3,figsize=(15,7)); axs=axs.ravel()
BV=['GPP','NPP','TOTVEGC','SOILC','BNF','TOTVEGN']
for i,which in enumerate(BV):
    ax=axs[i]; x=np.arange(3); w=0.35; sites=['Manaus','Harvard','Bonanza']
    o=[val(OLDD,s,which) for s in sites]; n=[val(NEWD,s,which) for s in sites]
    for j,s in enumerate(sites):
        lo,hi,u=LIT[s][which]; ax.fill_between([x[j]-0.45,x[j]+0.45],[lo]*2,[hi]*2,color='0.85',zorder=0,label='literature' if j==0 else '')
    ax.bar(x-w/2,o,w,color='#D55E00',label='old (buggy)'); ax.bar(x+w/2,n,w,color='#0072B2',label='new (fixed)')
    ax.set_xticks(x); ax.set_xticklabels(sites,fontsize=8); ax.set_title(f"{which} [{LIT['Manaus'][which][2]}]",fontsize=10)
    if i==0: ax.legend(fontsize=7)
plt.suptitle('Corrected(v2) vs old vs literature — present-day, FUN Houlton',y=1.0); plt.tight_layout()
plt.savefig('/home/braghiere/pipeline/eval_v2_literature.png',dpi=110,bbox_inches='tight')
# ---- Figure B: trajectories 1850-2100 (old vs new) key vars, 3 sites ----
KEY=['GPP','NPP','TOTVEGC','SOILC','SNFIX','TOTVEGN']
fig,ax=plt.subplots(len(KEY),3,figsize=(15,2.0*len(KEY)))
for r,which in enumerate(KEY):
    for c,site in enumerate(['Manaus','Harvard','Bonanza']):
        a=ax[r][c]
        for D,col,lab in [(OLDD,'#D55E00','old'),(NEWD,'#0072B2','new')]:
            d=D.get((site,'FUN_Houlton',which),{}); ys=sorted(d)
            sc = FLUX365 if which in ('GPP','NPP','SNFIX') else 1.0
            a.plot(ys,[d[y]*sc for y in ys],color=col,lw=1,label=lab)
        if r==0: a.set_title(site,fontsize=10)
        if c==0: a.set_ylabel(which,fontsize=8)
        a.tick_params(labelsize=6); a.grid(alpha=.25)
        if r==0 and c==0: a.legend(fontsize=7)
plt.suptitle('Trajectories 1850-2100: old(orange) vs corrected-v2(blue)',y=1.001); plt.tight_layout()
plt.savefig('/home/braghiere/pipeline/eval_v2_trajectories.png',dpi=100,bbox_inches='tight')
print('\nSAVED eval_v2_literature.png + eval_v2_trajectories.png')
