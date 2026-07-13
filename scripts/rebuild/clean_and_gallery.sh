#!/bin/bash
exec > /home/braghiere/clean_and_gallery.out 2>&1
PY=/home/braghiere/miniconda3/bin/python
NB=/home/braghiere/ELM-FUN-BNFMIP/notebooks/BNFMIP_table2_gallery_REBUILD.ipynb
# 1) strip phantom out-of-range boundary records from every packaged file
$PY - <<'PY'
import glob, re, numpy as np, xarray as xr, os
for f in glob.glob('/home/braghiere/BNF_tom/delivery_rebuild/*/*.nc'):
    sec=re.search(r'sec(\d\d)',f).group(1)
    lo,hi=(1850,2014) if sec=='53' else (2015,2100)
    d=xr.open_dataset(f,decode_times=False)
    yr=np.floor(d['time'].values).astype(int)
    keep=(yr>=lo)&(yr<=hi)
    if keep.sum()<len(yr):
        d.isel(time=np.where(keep)[0]).to_netcdf(f+'.tmp'); d.close()
        os.replace(f+'.tmp',f)
        print(f'  cleaned {os.path.basename(f)}: {len(yr)-keep.sum()} phantom rec dropped -> {keep.sum()} left')
    else: d.close()
print('CLEAN_DONE')
PY
# 2) re-run gallery
cd /home/braghiere/ELM-FUN-BNFMIP/notebooks
$PY -m jupyter nbconvert --clear-output --inplace "$NB" >/dev/null 2>&1
$PY -m jupyter nbconvert --to notebook --execute --inplace --ExecutePreprocessor.timeout=1200 "$NB" 2>&1 | tail -2
# 3) extract figures
$PY - <<'PY'
import nbformat, base64, os, re, glob
nb=nbformat.read("/home/braghiere/ELM-FUN-BNFMIP/notebooks/BNFMIP_table2_gallery_REBUILD.ipynb",as_version=4)
od="/home/braghiere/BNF_tom/gallery_rebuild_figs"
for x in glob.glob(od+'/*.png'): os.remove(x)
label="fig"; n=0; errs=0
for c in nb.cells:
    if c.cell_type=='markdown':
        for ln in c.source.splitlines():
            if ln.strip().startswith('#'): label=re.sub(r'[^A-Za-z0-9]+','_',ln.strip('# ').strip())[:34]
    if c.cell_type=='code':
        for o in c.get('outputs',[]):
            if o.get('output_type')=='error': errs+=1; print("ERR:",o.get('ename'),str(o.get('evalue'))[:80])
            if 'image/png' in o.get('data',{}):
                n+=1; open(f"{od}/{n:02d}_{label}.png",'wb').write(base64.b64decode(o['data']['image/png']))
print(f"FIGURES={n} ERRORS={errs}")
PY
echo "CLEAN_GALLERY_DONE"
