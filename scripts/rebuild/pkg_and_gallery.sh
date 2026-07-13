#!/bin/bash
exec > /home/braghiere/pkg_and_gallery.out 2>&1
PY=/home/braghiere/miniconda3/bin/python
NB=/home/braghiere/ELM-FUN-BNFMIP/notebooks/BNFMIP_table2_gallery_REBUILD.ipynb
# 1) proper repackage (authoritative VMAP)
rm -rf /home/braghiere/BNF_tom/delivery_rebuild
$PY /home/braghiere/BNF_tom/package_table2_rebuild.py 2>&1 | grep -vE "FutureWarning|data_vars|set_options|coder.decode"
# 2) confirm a packaged file has the gallery's variable names
$PY - <<'PY'
import xarray as xr
f='/home/braghiere/BNF_tom/delivery_rebuild/BNF-Man/fun_transient_only_BNF-Man_sec55_2015-2100_table2.nc'
import os
if os.path.exists(f):
    d=xr.open_dataset(f,decode_times=False)
    need=['SNFIX','FNFIX','TNFIX','TOTECOC','SOILC','WOODC','VEGCAG','VEGCBG','VEGC_TO_LITTER']
    print('Man-fun-55 vars:',len(d.data_vars),'| gallery-name check:',{n:(n in d) for n in need})
else: print('Man-fun-55 MISSING')
PY
# 3) run gallery fresh
cd /home/braghiere/ELM-FUN-BNFMIP/notebooks
$PY -m jupyter nbconvert --clear-output --inplace "$NB" >/dev/null 2>&1
$PY -m jupyter nbconvert --to notebook --execute --inplace --ExecutePreprocessor.timeout=1200 "$NB" 2>&1 | tail -2
# 4) extract figures + errors
$PY - <<'PY'
import nbformat, base64, os, re, glob
nb=nbformat.read("/home/braghiere/ELM-FUN-BNFMIP/notebooks/BNFMIP_table2_gallery_REBUILD.ipynb",as_version=4)
od="/home/braghiere/BNF_tom/gallery_rebuild_figs"
for x in glob.glob(od+'/*.png'): os.remove(x)
os.makedirs(od,exist_ok=True)
label="fig"; n=0; errs=0
for c in nb.cells:
    if c.cell_type=='markdown':
        for ln in c.source.splitlines():
            if ln.strip().startswith('#'): label=re.sub(r'[^A-Za-z0-9]+','_',ln.strip('# ').strip())[:38]
    if c.cell_type=='code':
        for o in c.get('outputs',[]):
            if o.get('output_type')=='error': errs+=1; print("  ERR:",o.get('ename'),str(o.get('evalue'))[:80])
            if 'image/png' in o.get('data',{}):
                n+=1; open(f"{od}/{n:02d}_{label}.png",'wb').write(base64.b64decode(o['data']['image/png']))
print(f"FIGURES={n} ERRORS={errs}")
PY
echo "ALL_DONE"
