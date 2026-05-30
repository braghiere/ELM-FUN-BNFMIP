#!/usr/bin/env python3
"""
BNF sanity check: NFIX vs FFIX for control / noACC / ACC at Manaus
Usage: python3 check_bnf_sanity.py
"""
import xarray as xr
import glob
import numpy as np

RUNROOT = "/lustre/or-scratch/cades-ccsi/scratch/braghiere"
s2yr    = 86400 * 365 * 1000   # kgN/m2/s  →  gN/m2/yr
gpp2d   = 86400                  # kgC/m2/s  →  gC/m2/d

variants = {
    "control (Houlton)":          "manaus_test_20260226_BNF-Man_I20TRCNPRDCTCBC",
    "noACC (Bytnerowicz)":        "noacc_manaus_20260226_BNF-Man_I20TRCNPRDCTCBC",
    "ACC  (Bytnerowicz+acclim)":  "acc_manaus_20260226_BNF-Man_I20TRCNPRDCTCBC",
}

print(f"\n{'Variant':<35} {'NFIX':>14} {'FFIX':>14} {'NFIX/FFIX':>11} {'GPP':>12} {'NPP':>12}")
print(f"{'':.<35} {'gN/m2/yr':>14} {'gN/m2/yr':>14} {'ratio':>11} {'gC/m2/d':>12} {'gC/m2/d':>12}")
print("─" * 100)

for label, casename in variants.items():
    files = sorted(glob.glob(f"{RUNROOT}/{casename}/run/*.elm.h0.*.nc"))
    if not files:
        print(f"{label:<35}  ← NO OUTPUT YET")
        continue

    ds = xr.open_mfdataset(files, combine='by_coords')

    def mean(v): return float(ds[v].mean()) if v in ds else np.nan

    nfix  = mean('NFIX_TO_SMINN') * s2yr
    ffix  = mean('FFIX_TO_SMINN') * s2yr
    gpp   = mean('GPP')  * gpp2d
    npp   = mean('NPP')  * gpp2d
    ratio = (nfix / ffix) if (not np.isnan(ffix) and ffix > 0) else np.nan

    status = ""
    if not np.isnan(ratio):
        if ratio < 0.001:
            status = "⚠️  SAME PROBLEM (NFIX ~ zero)"
        elif ratio > 0.5:
            status = "✅  Looks reasonable"
        else:
            status = "⚠️  Low but non-zero"

    print(f"{label:<35} {nfix:>14.4f} {ffix:>14.4f} {ratio:>11.4f} {gpp:>12.3f} {npp:>12.3f}  {status}")

print()
print("Reference — Will Wieder CLM Houlton, tropical Manaus:")
print("  FFIX: ~0.6 gN/m2/yr  |  NFIX (Houlton): ~2.0 gN/m2/yr  |  NPP: ~3 gC/m2/d")
print("Previous ELM-FUN issue: NFIX ~4.5e-13 → ratio << 0.001")
