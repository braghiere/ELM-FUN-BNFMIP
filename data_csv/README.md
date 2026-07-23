# ELM-FUN BNFMIP site results — CSV export (for R)

Machine-readable export of the delivered Table-2 site simulations, for loading in R and
combining with the other BNFMIP models. Same data as the `BNFMIP_table2_gallery` notebook.

## Files
- **`bnfmip_elmfun_table2_annual_long.csv`** — tidy long, **annual means**, all combos.
  Columns: `site, experiment, section, year, variable, value, units`. Best for trajectory
  figures and rbind-ing with other models.
- **`monthly/<site>_<experiment>_sec<NN>.csv`** — one file per combo, **monthly** resolution
  (wide: `time_decimal_year` + the 54 variables). Use for seasonal cycles / full detail.

## Dimensions
- **site**: Manaus (tropical), Harvard (temperate), Bonanza (boreal)
- **experiment**: NoFUN, FUN_Houlton, Bytnerowicz_noAcc, Bytnerowicz_Acc
- **section**: 5.3 (historical 1850–2014), 5.4 (fixed CO2/Ndep 2015–2100), 5.5 (SSP5-8.5 2015–2100)
- 54 Table-2 variables (C/N/P pools + fluxes). Units are in the `units` column / are standard:
  fluxes `kgC|N|P/m2/day`, pools `kg/m2`, TSOI `K`, ELAI `m2/m2`.
  Key: `SNFIX`=symbiotic N fixation, `FNFIX`=free-living, `TNFIX`=total; `GPP,NPP,AR,HR`;
  `TOTECOC,TOTVEGC,SOILC`; `TOTVEGN,SMINN`; `TOTVEGP,SMINP`.

## Load in R
```r
library(dplyr); library(readr)
d <- read_csv("bnfmip_elmfun_table2_annual_long.csv")
# e.g. total N fixation trajectory, Manaus, SSP5-8.5:
d %>% filter(site=="Manaus", section=="5.5", variable=="TNFIX")
# monthly for one combo:
m <- read_csv("monthly/Manaus_FUN_Houlton_sec55.csv")
```

## Caveats (as discussed — to be corrected in a later delivery)
1. **Harvard PFT** ran as broadleaf-deciduous *tropical*, not temperate. BNF temperature-response
   params are identical (signal intact), but Harvard absolute C is ~10–25% low.
2. **§5.5 continuity** — Manaus is a smooth continuation; Harvard/Bonanza §5.5 were separate
   startups → a 2015 discontinuity in fast N pools. Valid runs, not seamless with §5.3.
A corrected, re-spun-up version (both caveats fixed) is in progress and will follow.

## Provenance
Generated from `delivery_table2/*.nc` (the delivered set). Phantom 1-month boundary records
stripped; annual = mean of monthly within each calendar year. Contact: renatob@caltech.edu.
