import csv,collections,numpy as np,warnings,matplotlib
warnings.filterwarnings('ignore'); matplotlib.use('Agg'); import matplotlib.pyplot as plt
F={'OLD(buggy)':'/home/braghiere/ELM-FUN-BNFMIP/data_csv_corrected/bnfmip_elmfun_table2_annual_long.csv',
   'v2(fix,sfix-.1)':'/home/braghiere/ELM-FUN-BNFMIP/data_csv_corrected_v2/bnfmip_elmfun_table2_annual_long.csv',
   'v3(fix,sfix-6)':'/home/braghiere/ELM-FUN-BNFMIP/data_csv_sfixorig/bnfmip_elmfun_table2_annual_long.csv'}
def load(f):
    T=collections.defaultdict(dict)
    try:
        for r in csv.DictReader(open(f)):
            if r['section']=='5.3': T[(r['site'],r['variable'])][int(r['year'])]=float(r['value'])
    except: pass
    return T
D={k:load(v) for k,v in F.items()}
def pd_(T,site,var,lo=2005,hi=2014):
    d=T.get((site,var),{}); v=[d[y] for y in d if lo<=y<=hi]; return np.mean(v) if v else np.nan
Y=365000.0
LITBNF={'Manaus':(1.5,3.6),'Harvard':(0.3,2.7),'Bonanza':(0.2,2.0)}
out=["3-WAY COMPARISON (present-day 2005-2014, FUN Houlton) — BNF is the key variable",""]
out.append(f"{'site':9s}{'metric':16s}"+"".join(f"{k:>18}" for k in F)+"   lit")
for site in ['Manaus','Harvard','Bonanza']:
    lo,hi=LITBNF[site]
    for lab,var,sc in [('BNF total','_BNF_',Y),('symbiotic SNFIX','SNFIX',Y),('NPP_NUPTAKE','NPP_NUPTAKE',1),
                       ('GPP','GPP',Y),('NPP','NPP',Y),('TOTVEGC','TOTVEGC',1),('SOILC','SOILC',1)]:
        vals=[]
        for k in F:
            if var=='_BNF_': v=(pd_(D[k],site,'SNFIX')+pd_(D[k],site,'FNFIX'))*sc
            else: v=pd_(D[k],site,var)*sc
            vals.append(v)
        litstr=f"{lo}-{hi}" if lab=='BNF total' else ""
        out.append(f"{site:9s}{lab:16s}"+"".join(f"{v:18.3g}" for v in vals)+f"   {litstr}")
    out.append("")
txt="\n".join(out); open('/home/braghiere/pipeline_v3/COMPARISON_V3.txt','w').write(txt); print(txt)
# BNF figure
fig,axs=plt.subplots(1,3,figsize=(14,4))
for i,site in enumerate(['Manaus','Harvard','Bonanza']):
    ax=axs[i]; ks=list(F); x=np.arange(len(ks))
    bnf=[(pd_(D[k],site,'SNFIX')+pd_(D[k],site,'FNFIX'))*Y for k in ks]
    lo,hi=LITBNF[site]; ax.axhspan(lo,hi,color='0.85',label='literature')
    ax.bar(x,bnf,color=['#D55E00','#0072B2','#009E73'])
    ax.set_xticks(x); ax.set_xticklabels(['OLD','v2\n(sfix-.1)','v3\n(sfix-6)'],fontsize=8)
    ax.set_title(f"{site} BNF (gN/m2/yr)",fontsize=10); ax.grid(alpha=.25,axis='y')
    if i==0: ax.legend(fontsize=8)
plt.suptitle('BNF: OLD(buggy) vs v2(fixed,tuned s_fix) vs v3(fixed,original s_fix) vs literature',y=1.02)
plt.tight_layout(); plt.savefig('/home/braghiere/pipeline_v3/compare_v3_BNF.png',dpi=120,bbox_inches='tight')
print("SAVED compare_v3_BNF.png")
