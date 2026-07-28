#!/usr/bin/env python
"""Comprehensive corrected-vs-gen1 comparison across ALL Table-2 outputs, 3 sites (fun).
Reports: present-day (2005-2014) values + %change; pre-industrial U-shape dip% (pools);
and a trajectory grid figure. Answers 'did it fix it / does it look right'."""
import glob,re,numpy as np,xarray as xr,warnings,matplotlib
warnings.filterwarnings('ignore'); matplotlib.use('Agg'); import matplotlib.pyplot as plt
RR='/lustre/or-scratch24/scratch/braghiere'; SPY=86400*365.0
SITES=[('Manaus','su_fun_man','mpd_fun_man'),('Harvard','su_fun_ha1','mpd_fun_ha1v2'),('Bonanza','su_fun_bon','sc_fun_transient_only_bon')]
FLUX={'GPP','NPP','AR','HR','NEE','NFIX_TO_SMINN','FFIX_TO_SMINN','NET_NMIN','NET_PMIN'}
POOLC={'TOTVEGC','TOTECOSYSC','TOTSOMC','TOTLITC','LEAFC','FROOTC','CWDC','DEADSTEMC'}
VARS=['GPP','NPP','AR','HR','TOTVEGC','TOTECOSYSC','TOTSOMC','TOTLITC','LEAFC','FROOTC','CWDC','DEADSTEMC',
      'NFIX_TO_SMINN','FFIX_TO_SMINN','NET_NMIN','SMINN','TOTVEGN','TOTSOMN','LEAFN',
      'SOLUTIONP','SMINP','TOTVEGP','TOTSOMP','LEAFP','TLAI','TSOI_10CM','QVEGT']
def load(pref):
    rd=glob.glob(f'{RR}/{pref}_repro20260709_*/run') or glob.glob(f'{RR}/{pref}_*/run')
    if not rd: return None,None
    fs=sorted(glob.glob(f'{rd[0]}/*.clm2.h0.*.nc'),key=lambda f:int(re.search(r'h0\.(\d+)',f).group(1)))
    ys=[]; D={v:[] for v in VARS}
    for f in fs[::3]:
        y=int(re.search(r'h0\.(\d+)',f).group(1))
        if y<1850 or y>2100: continue
        d=xr.open_dataset(f,decode_times=False); ys.append(y)
        for v in VARS:
            x=np.nan
            if v in d:
                a=d[v].values; a=a[...,0] if a.ndim>1 else a; x=float(np.nanmean(a))
            D[v].append(x)
        d.close()
    ys=np.array(ys); return ys,{v:np.array(D[v]) for v in VARS}
def conv(v,a):
    if v in FLUX: return a*SPY*(10 if v in ('NFIX_TO_SMINN','FFIX_TO_SMINN') else 1)  # BNF kgN/ha/yr else g/m2/yr
    if v in POOLC or v in ('TOTSOMP',): return a*1e-3  # kg/m2
    return a
DATA={s:(load(c),load(g)) for s,c,g in SITES}
# ---- table ----
print("=== PRESENT-DAY (2005-2014) corrected vs gen-1, + pre-industrial dip% (pools) ===")
for site,cp,gp in SITES:
    (yc,C),(yg,G)=DATA[site]
    if yc is None or yg is None: print(f"{site}: missing"); continue
    print(f"\n--- {site} ---")
    print(f"  {'var':13s}{'gen-1':>10}{'corrected':>11}{'%chg':>7}   {'dip%:g1->corr':>16}")
    for v in VARS:
        pdc=np.nanmean(conv(v,C[v])[(yc>=2005)&(yc<=2014)]); pdg=np.nanmean(conv(v,G[v])[(yg>=2005)&(yg<=2014)])
        pc=100*(pdc-pdg)/pdg if pdg else np.nan
        dipstr=""
        if v in POOLC:
            gg=conv(v,G[v]); cc=conv(v,C[v])
            def dip(y,a):
                m=(y>=1850)&(y<=1970);
                return 100*(a[y==1850][0]-np.nanmin(a[m]))/a[y==1850][0] if (y==1850).any() and m.sum() else np.nan
            dipstr=f"{dip(yg,gg):5.0f}% -> {dip(yc,cc):3.0f}%"
        print(f"  {v:13s}{pdg:10.3g}{pdc:11.3g}{pc:+6.0f}%   {dipstr:>16}")
# ---- figure ----
KEY=['GPP','NPP','HR','TOTVEGC','TOTECOSYSC','TOTSOMC','TOTLITC','NFIX_TO_SMINN','SMINN','TOTVEGN','SOLUTIONP','TLAI']
fig,axs=plt.subplots(len(KEY),3,figsize=(15,2.1*len(KEY)));
for r,v in enumerate(KEY):
    for cix,(site,cp,gp) in enumerate(SITES):
        ax=axs[r][cix]; (yc,C),(yg,G)=DATA[site]
        ax.plot(yg,conv(v,G[v]),color='#D55E00',lw=1,label='gen-1')
        ax.plot(yc,conv(v,C[v]),color='#0072B2',lw=1,label='corrected')
        ax.axvline(2015,color='k',ls=':',lw=.5)
        if r==0: ax.set_title(site,fontsize=11)
        if cix==0: ax.set_ylabel(v,fontsize=8)
        ax.tick_params(labelsize=6); ax.grid(alpha=.25)
        if r==0 and cix==0: ax.legend(fontsize=7)
plt.suptitle('Corrected (blue) vs gen-1 (orange): all key Table-2 outputs, 1850-2100',fontsize=13,y=1.001)
plt.tight_layout(); plt.savefig('/home/braghiere/BNF_tom/comprehensive_compare.png',dpi=100,bbox_inches='tight')
print('\nSAVED /home/braghiere/BNF_tom/comprehensive_compare.png')
print('CCMP_DONE')
