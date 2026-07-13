import glob,re,numpy as np,xarray as xr,warnings,matplotlib
warnings.filterwarnings('ignore'); matplotlib.use('Agg'); import matplotlib.pyplot as plt
fs=sorted(glob.glob('/lustre/or-scratch24/scratch/braghiere/spinCNP_fun_bon_BNF-Bon_I1850CNPRDCTCBC/run/*.clm2.h0.*.nc'),key=lambda f:int(re.search(r'h0\.(\d+)',f).group(1)))
fs=fs[::3]
yr=np.array([int(re.search(r'h0\.(\d+)',f).group(1)) for f in fs])
def S(v,sc=1.0):
    o=[]
    for f in fs:
        x=xr.open_dataset(f,decode_times=False); o.append(float(np.nanmean(x[v].values))*sc if v in x else np.nan); x.close()
    return np.array(o)
# BNF total kgN/ha/yr from gN/m2/s: *86400*365*10
bnf=(S('NFIX_TO_SMINN')+S('FFIX_TO_SMINN'))*86400*365*10
panels=[('TOTECOSYSC',1e-3,'kgC/m2','Total ecosystem C'),('TOTVEGC',1e-3,'kgC/m2','Vegetation C'),
        ('TOTSOMC',1e-3,'kgC/m2','Soil organic C'),('TOTLITC',1e-3,'kgC/m2','Litter C'),
        ('TOTECOSYSP',1e-3,'kgP/m2','Total ecosystem P'),('TOTVEGP',1e-3,'kgP/m2','Vegetation P'),
        ('SMINP',1e-3,'kgP/m2','Mineral soil P'),('TOTVEGN',1e-3,'kgN/m2','Vegetation N'),
        ('SMINN',1e-3,'kgN/m2','Mineral soil N'),('GPP',86400*365*1e-3,'kgC/m2/yr','GPP'),
        ('NPP',86400*365*1e-3,'kgC/m2/yr','NPP'),(None,None,None,'Total BNF')]
fig,axs=plt.subplots(3,4,figsize=(17,9)); axs=axs.ravel()
for i,(v,sc,u,t) in enumerate(panels):
    ax=axs[i]
    y = bnf if v is None else S(v,sc)
    ax.plot(yr,y,lw=1.4,color='#0072B2')
    # equilibrium band: mean +/- of last 50 yr
    m=yr>=yr.max()-50; eq=np.nanmean(y[m])
    ax.axhline(eq,color='#D55E00',ls='--',lw=.8)
    ax.set_title(t,fontsize=10); ax.set_xlabel('spin-up year',fontsize=8)
    ax.set_ylabel('kgN/ha/yr' if v is None else u,fontsize=8); ax.grid(alpha=.3); ax.tick_params(labelsize=7)
    # annotate last-50yr drift
    if len(y[m])>5:
        tr=np.polyfit(yr[m],y[m],1)[0]*100/eq if eq else np.nan
        ax.text(.03,.9,f'eq={eq:.3g}\ndrift={tr:+.3f}%/yr',transform=ax.transAxes,fontsize=7,va='top',
                bbox=dict(boxstyle='round',fc='white',alpha=.7))
plt.suptitle('Bonanza-fun CNP+FUNP spin-up (I1850) — pools equilibrating (dashed = last-50yr mean)',fontsize=13,y=1.0)
plt.tight_layout(); plt.savefig('/home/braghiere/BNF_tom/working_bonanza_spinup.png',dpi=110,bbox_inches='tight')
print('SAVED /home/braghiere/BNF_tom/working_bonanza_spinup.png ; years',yr.min(),'-',yr.max(),'n=',len(fs))
print('final BNF=%.2f kgN/ha/yr (lit boreal 1.5-2.0)'%bnf[-1])
