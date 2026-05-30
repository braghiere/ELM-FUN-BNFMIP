# Item 6: Add Literature References for Additional Variables

## Changes Made to BNFMIP_site_evaluation.ipynb

### New Literature Dictionaries Added (cell #VSC-0a60b189)
All in units matching the corresponding plot_var_3sites calls:

| Dict | Units | Variables | Key Sources |
|------|-------|-----------|-------------|
| LIT_ELAI | m² m⁻² | ELAI | McWilliam+93, Myneni+07, Ollinger+05, MODIS |
| LIT_ET | kgH₂O m⁻² yr⁻¹ | ET (EFLX_LH_TOT/2501) | da Rocha+04, Fisher+09, Urbanski+07 |
| LIT_TVEG | kgH₂O m⁻² yr⁻¹ | QVEGT | Fisher+09, Wilson+01, FLUXNET |
| LIT_LEAFN | gN m⁻² (ground) | LEAFN | Reich+97, Norby+01, Niinemets+01 |
| LIT_LEAFP | gP m⁻² (ground) | LEAFP | Vitousek+10, Lambers+10, McGroddy+04 |

### Plot Calls Updated to Use New Refs
- Cell #VSC-5b86c4cb (Physical variables):
  - `plot_var_3sites('ELAI', ...)` → added `refs=LIT_ELAI`
  - `plot_var_3sites('QVEGT', ...)` → added `refs=LIT_TVEG`
  - ET derived plot → added `refs=LIT_ET`
- Cell #VSC-2d6d45cf (N pools):
  - `plot_var_3sites('LEAFN', ...)` → added `refs=LIT_LEAFN`
- Cell #VSC-901ce6e6 (P pools):
  - `plot_var_3sites('LEAFP', ...)` → added `refs=LIT_LEAFP`

### N Uptake Pathway Cell Added (new cell after #VSC-d2e2d515)
- Individual plots for NPP_NACTIVE, NPP_NFIX, NPP_NRETRANS, NPP_NNONMYC (gC m⁻² yr⁻¹)
- COST_NFIX, COST_NACTIVE plotted with flux=False (dimensionless gC/gN)
- Approximate gN derived as NPP_N*/COST_* where COST > 0

## Reference Values Summary
### LAI (m² m⁻²)
- Manaus: 4.5–6.5 (central 5.5)
- Harvard: 3.0–5.0 (central 4.0)
- Bonanza: 1.0–3.5 (central 2.0)

### ET (kgH₂O m⁻² yr⁻¹)
- Manaus: 900–1300 (central 1100)
- Harvard: 350–550 (central 450)
- Bonanza: 200–400 (central 300)

### Leaf N (gN m⁻² ground)
- Manaus: 3.0–8.0 (central 5.0)
- Harvard: 2.5–6.0 (central 4.0)
- Bonanza: 1.0–4.0 (central 2.5)

### Leaf P (gP m⁻² ground)
- Manaus: 0.15–0.50 (central 0.30)
- Harvard: 0.10–0.30 (central 0.18)
- Bonanza: 0.06–0.20 (central 0.12)
