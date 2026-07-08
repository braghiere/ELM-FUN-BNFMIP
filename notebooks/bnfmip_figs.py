#!/usr/bin/env python3
"""BNFMIP ELM-FUN results figures. Colorblind-safe (Okabe-Ito), one y-axis per panel.
Reads the delivery files: annual (delivery/) + monthly Table-2 (delivery_table2/)."""
import os, glob, numpy as np, xarray as xr
import matplotlib as mpl; mpl.use('Agg')
import matplotlib.pyplot as plt

ANN='/home/braghiere/BNF_tom/delivery'
T2='/home/braghiere/BNF_tom/delivery_table2'
OUT='/home/braghiere/ELM-FUN-BNFMIP/notebooks/figs'; os.makedirs(OUT,exist_ok=True)
coder=xr.coders.CFDatetimeCoder(use_cftime=True)

SITES=[('BNF-Man','Manaus (tropical)'),('BNF-Ha1','Harvard (temperate)'),('BNF-Bon','Bonanza (boreal)')]
EXPS=[('nofun_baseline','NoFUN'),('fun_transient_only','FUN (Houlton)'),
      ('noacc_transient','Bytn. no-acclim'),('acc_transient','Bytn. acclim')]
# Okabe-Ito (CVD-safe), fixed order per experiment
CE={'nofun_baseline':'#999999','fun_transient_only':'#0072B2',
    'noacc_transient':'#E69F00','acc_transient':'#D55E00'}
CS={'BNF-Man':'#D55E00','BNF-Ha1':'#009E73','BNF-Bon':'#56B4E9'}  # warm->cold
SEC={'53':('1850-2014','sec53'),'54':('2015-2100','sec54'),'55':('2015-2100','sec55')}

plt.rcParams.update({'figure.dpi':110,'axes.grid':True,'grid.alpha':0.25,'grid.linewidth':0.6,
 'axes.spines.top':False,'axes.spines.right':False,'font.size':10,'axes.titlesize':11})

def ann(site,exp,sec):
    rng,tag=SEC[sec]
    f=f'{ANN}/{site}/{exp}_{site}_{tag[:3]}{sec}_{rng}.nc'
    return xr.open_dataset(f,decode_times=coder) if os.path.exists(f) else None

def em(ds,v,n=10):  # last-decade annual mean
    return float(ds[v].isel(year=slice(-n,None)).mean().values) if (ds is not None and v in ds) else np.nan

# ---- Fig 1: BNF by site x experiment (gradient) ----
def fig_bnf_gradient():
    fig,axs=plt.subplots(1,3,figsize=(11,3.6),sharey=False)
    for ax,(sid,sname) in zip(axs,SITES):
        vals=[]; labs=[]; cols=[]
        for exp,elab in EXPS:
            ds=ann(sid,exp,'53'); vals.append(em(ds,'NFIX_TO_SMINN')); labs.append(elab); cols.append(CE[exp])
            if ds is not None: ds.close()
        x=np.arange(len(vals))
        ax.bar(x,vals,color=cols,width=0.7)
        for xi,v in zip(x,vals):
            if not np.isnan(v): ax.text(xi,v,f'{v:.2f}',ha='center',va='bottom',fontsize=8)
        ax.set_xticks(x); ax.set_xticklabels([l.replace(' ','\n') for l in labs],fontsize=7.5)
        ax.set_title(sname); ax.set_ylim(0,max([v for v in vals if not np.isnan(v)]+[0.1])*1.25)
    axs[0].set_ylabel('BNF  (gN m$^{-2}$ yr$^{-1}$)')
    fig.suptitle('Biological N fixation, historical (1990–2014 mean)  —  tropical ≫ temperate ≫ boreal',y=1.02)
    fig.tight_layout(); fig.savefig(f'{OUT}/fig1_bnf_gradient.png',bbox_inches='tight'); plt.close(fig)

# ---- Fig 2: GPP & NPP across sections, FUN vs NoFUN ----
def fig_gpp_npp():
    fig,axs=plt.subplots(2,3,figsize=(11,6),sharex=True)
    secs=['53','54','55']; xlab=['5.3\nhist','5.4\nwarm','5.5\nSSP585']
    for j,(sid,sname) in enumerate(SITES):
        for i,var in enumerate(['GPP','NPP']):
            ax=axs[i,j]; x=np.arange(3); w=0.2
            for k,(exp,elab) in enumerate(EXPS):
                y=[]
                for s in secs:
                    ds=ann(sid,exp,s); y.append(em(ds,var));
                    if ds is not None: ds.close()
                ax.bar(x+(k-1.5)*w,y,width=w,color=CE[exp],label=elab if (i==0 and j==2) else None)
            if i==0: ax.set_title(sname)
            if j==0: ax.set_ylabel(f'{var}  (gC m$^{{-2}}$ yr$^{{-1}}$)')
            ax.set_xticks(x); ax.set_xticklabels(xlab,fontsize=8)
    axs[0,2].legend(fontsize=7.5,loc='upper left',frameon=False)
    fig.suptitle('GPP (top) & NPP (bottom): FUN N-cost lowers NPP; SSP585 raises GPP',y=1.0)
    fig.tight_layout(); fig.savefig(f'{OUT}/fig2_gpp_npp.png',bbox_inches='tight'); plt.close(fig)

# ---- Fig 3: Temperature response of BNF (the MIP core) ----
def fig_tresponse():
    fig,axs=plt.subplots(1,3,figsize=(11,3.8))
    for ax,(sid,sname) in zip(axs,SITES):
        for exp,elab in [('fun_transient_only','FUN (Houlton)'),('noacc_transient','Bytn. no-acclim'),('acc_transient','Bytn. acclim')]:
            f=f'{T2}/{sid}/{exp}_{sid}_sec55_2015-2100_table2.nc'
            if not os.path.exists(f): continue
            ds=xr.open_dataset(f)
            if 'TSOIBNF' in ds and 'SNFIX' in ds:
                t=ds['TSOIBNF'].values-273.15
                s=ds['SNFIX'].values*1e6   # kgN/m2/day -> mgN/m2/day
                ax.scatter(t,s,s=6,alpha=0.35,color=CE[exp],label=elab,edgecolors='none')
            ds.close()
        ax.set_title(sname); ax.set_xlabel('soil T driving BNF (°C)')
        if sid=='BNF-Man': ax.legend(fontsize=7.5,frameon=False,markerscale=2)
    axs[0].set_ylabel('symbiotic BNF (mgN m$^{-2}$ day$^{-1}$)')
    fig.suptitle('Temperature response of BNF (monthly, §5.5 2015–2100) — Houlton vs Bytnerowicz',y=1.02)
    fig.tight_layout(); fig.savefig(f'{OUT}/fig3_temperature_response.png',bbox_inches='tight'); plt.close(fig)

# ---- Fig 4: GPP time series 1850-2100 (hist + SSP585) per site ----
def fig_timeseries():
    fig,axs=plt.subplots(1,3,figsize=(11,3.6),sharex=True)
    for ax,(sid,sname) in zip(axs,SITES):
        for exp,elab in [('nofun_baseline','NoFUN'),('fun_transient_only','FUN')]:
            xs=[]; ys=[]
            for s in ['53','55']:
                ds=ann(sid,exp,s)
                if ds is not None and 'GPP' in ds:
                    xs.append(ds['year'].values); ys.append(ds['GPP'].values); ds.close()
            if xs:
                X=np.concatenate(xs); Y=np.concatenate(ys); o=np.argsort(X)
                ax.plot(X[o],Y[o],lw=1.3,color=CE[exp],label=elab)
        ax.axvline(2015,color='k',lw=0.6,ls=':',alpha=0.5)
        ax.set_title(sname); ax.set_xlabel('year')
        if sid=='BNF-Man': ax.legend(fontsize=8,frameon=False)
    axs[0].set_ylabel('GPP  (gC m$^{-2}$ yr$^{-1}$)')
    fig.suptitle('GPP 1850–2100 (historical + SSP585; dotted = 2015)',y=1.02)
    fig.tight_layout(); fig.savefig(f'{OUT}/fig4_timeseries.png',bbox_inches='tight'); plt.close(fig)

if __name__=='__main__':
    fig_bnf_gradient(); print('fig1 ok')
    fig_gpp_npp();      print('fig2 ok')
    fig_tresponse();    print('fig3 ok')
    fig_timeseries();   print('fig4 ok')
    print('figures ->',OUT)
