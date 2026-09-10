#!/usr/bin/env python
"""Regenerate the CSV-derivable comparison figures for the s_fix decision (docs/SFIX_DECISION.md).
Runs from repo root. Reads the three annual_long CSVs (OLD / v2 / v3). Writes to analysis/figs/.
(The pathway-partitioning figure needs raw h0 output and is committed as a PNG.)"""
import csv,collections,os,numpy as np,warnings,matplotlib
warnings.filterwarnings('ignore'); matplotlib.use('Agg'); import matplotlib.pyplot as plt
R=os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
F={'OLD':f'{R}/data_csv_corrected/bnfmip_elmfun_table2_annual_long.csv',
   'v2':f'{R}/data_csv_corrected_v2/bnfmip_elmfun_table2_annual_long.csv',
   'v3':f'{R}/data_csv_sfixorig/bnfmip_elmfun_table2_annual_long.csv'}
OUT=f'{R}/analysis/figs'; os.makedirs(OUT,exist_ok=True); Y=365000.0
def load(f,secs=('5.3',)):
    T=collections.defaultdict(dict)
    for r in csv.DictReader(open(f)):
        if r['section'] in secs: T[(r['site'],r['experiment'],r['variable'])][int(r['year'])]=float(r['value'])
    return T
def win(T,s,v,e='FUN_Houlton',lo=2005,hi=2014,sc=Y):
    d=T.get((s,e,v),{}); x=[d[y] for y in d if lo<=y<=hi]; return np.mean(x)*sc if x else np.nan
sites=['Manaus','Harvard','Bonanza']
D={k:load(v) for k,v in F.items()}; Dt={k:load(v,('5.3','5.5')) for k,v in F.items()}

# FIG: s_fix cost physics
a,b,c=-3.62,0.27,25.15
def cost(T,s): return s*(np.exp(a+b*T*(1-0.5*T/c))-2)
fig,ax=plt.subplots(figsize=(7,4.5)); sfix=np.linspace(-12,-0.05,200)
for T,l in [(25,'25C optimal'),(15,'15C')]: ax.plot(-sfix,[cost(T,s) for s in sfix],label=f'cost @ {l}')
ax.axhspan(4,6,color='#009E73',alpha=.3,label='Menge26 obs 5(4-6)'); ax.axhspan(7.5,12.5,color='#E69F00',alpha=.25,label='FUN nominal 7.5-12.5')
for s,nm in [(0.1,'delivered -0.1'),(1,'-1'),(6,'CLM default -6')]: ax.axvline(s,color='grey',ls=':',lw=.8); ax.text(s,0.5,nm,rotation=90,fontsize=7,va='bottom')
ax.set_xscale('log'); ax.set_xlabel('|s_fix|'); ax.set_ylabel('fixation cost (gC/gN)'); ax.set_ylim(0,15)
ax.set_title('Fixation cost per N vs s_fix'); ax.legend(fontsize=7); plt.tight_layout(); plt.savefig(f'{OUT}/sfix_cost_physics.png',dpi=115,bbox_inches='tight'); plt.close()

# FIG: BNF verdict vs 2026 lit (total = symbiotic+free)
LIT={'Manaus':dict(sym=0.02,tot=(0.2,0.7),cl=(1.5,3.6)),'Harvard':dict(sym=0.05,tot=(0.1,0.6),cl=(0.3,2.7)),'Bonanza':dict(sym=0.0,tot=(0.15,0.2),cl=(0.2,2.0))}
fig,axs=plt.subplots(1,3,figsize=(15,4.6))
for i,s in enumerate(sites):
    ax=axs[i]; x=np.arange(3); sym=[win(D[k],s,'SNFIX') for k in F]; fre=[win(D[k],s,'FNFIX') for k in F]
    ax.bar(x,sym,.62,color='#0072B2',label='symbiotic (FUN)'); ax.bar(x,fre,.62,bottom=sym,color='#56B4E9',label='free-living (Cleveland ET)')
    L=LIT[s]; ax.axhspan(*L['tot'],color='#009E73',alpha=.3,label='measured TOTAL (2026)'); ax.axhline(L['sym'],color='#004D40',ls='--',lw=1.4,label='measured symbiotic'); ax.axhspan(*L['cl'],color='#D55E00',alpha=.12,label='Cleveland99 (superseded)')
    ax.set_xticks(x); ax.set_xticklabels(['OLD','v2\n-.1','v3\n-6']); ax.set_title(f'{s} total BNF'); ax.set_yscale('symlog',linthresh=0.02); ax.grid(alpha=.25,axis='y')
    if i==0: ax.legend(fontsize=6.3); ax.set_ylabel('gN/m2/yr (symlog)')
plt.suptitle('ELM total BNF vs 2026 synthesis: v3 in range, OLD/v2 in superseded-Cleveland zone',y=1.02); plt.tight_layout(); plt.savefig(f'{OUT}/bnf_verdict_2026.png',dpi=120,bbox_inches='tight'); plt.close()

# FIG: BNFMIP scheme temperature response (transient 5.3+5.5)
SCH=[('FUN_Houlton','Houlton','#0072B2'),('Bytnerowicz_noAcc','noACC','#D55E00'),('Bytnerowicz_Acc','ACC','#009E73')]
fig,ax=plt.subplots(1,3,figsize=(15,4.2))
for i,s in enumerate(sites):
    a2=ax[i]
    for e,lab,col in SCH:
        for k,ls in [('OLD','--'),('v3','-')]:
            d=Dt[k].get((s,e,'SNFIX'),{}); ys=sorted(d); a2.plot(ys,[d[y]*Y for y in ys],ls,color=col,lw=1.1,label=f'{lab} {k}' if i==0 else None)
    a2.axvline(2015,color='grey',ls=':',lw=.5); a2.set_title(f'{s} symbiotic BNF'); a2.grid(alpha=.25)
    if i==0: a2.legend(fontsize=6.5,ncol=2); a2.set_ylabel('gN/m2/yr')
plt.suptitle('BNFMIP temperature response: SNFIX by scheme, OLD(dashed) vs v3(solid)',y=1.02); plt.tight_layout(); plt.savefig(f'{OUT}/bnf_schemes_old_v3.png',dpi=115,bbox_inches='tight'); plt.close()
print('regenerated: sfix_cost_physics, bnf_verdict_2026, bnf_schemes_old_v3 (in analysis/figs/)')
