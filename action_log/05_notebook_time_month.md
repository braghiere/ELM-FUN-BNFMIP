# Item 5: Fix Notebook Seasonal Cycle Cell — time.month KeyError

## Error
Cell #VSC-8e8aaacb (lines 764–806) in BNFMIP_site_evaluation.ipynb
```
AttributeError: 'IndexVariable' object has no attribute 'month'
```
caused by: `clim = sub.groupby('time.month').mean('time')`

## Root Cause
xarray v2026.2.0 changed the `groupby` API. String-based accessors like
`'time.month'` no longer work when the time coordinate is an `IndexVariable`.
The `.dt` accessor must be called explicitly.

## Fix Applied
Changed:
```python
clim = sub.groupby('time.month').mean('time')
```
to:
```python
clim = sub.groupby(sub['time'].dt.month).mean('time')
```

The `.dt.month` accessor returns integer months (1–12), which xarray groups by
correctly. `clim.values` still returns the 12-element array in the same shape.

## File Modified
`/home/braghiere/BNF_tom/BNFMIP_site_evaluation.ipynb` — cell #VSC-8e8aaacb
