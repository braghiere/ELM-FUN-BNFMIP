#!/usr/bin/env python3
"""Repackage the REBUILD (repro20260709) runs into Table-2 format using the
authoritative repo packager's VMAP/conversions/derived-vars (package_table2.process),
only repointing input to the rebuild run dirs and output to delivery_rebuild/."""
import os, glob, sys
sys.path.insert(0,'/home/braghiere/ELM-FUN-BNFMIP/scripts')
import package_table2 as P
P.OUTDIR='/home/braghiere/BNF_tom/delivery_rebuild'
RR='/lustre/or-scratch24/scratch/braghiere'

# (site,exp) -> rebuild case prefix for the CONTINUOUS 1850-2100 run (serves sec53+sec55)
PREF={
 ('BNF-Bon','fun_transient_only'):'sc_fun_transient_only_bon',
 ('BNF-Bon','noacc_transient'):'sc_noacc_transient_bon',
 ('BNF-Bon','acc_transient'):'sc_acc_transient_bon',
 ('BNF-Bon','nofun_baseline'):'ft_nofun_baseline_bon',
 ('BNF-Man','fun_transient_only'):'mpd_fun_man',
 ('BNF-Man','noacc_transient'):'mpd_noacc_transient_man',
 ('BNF-Man','acc_transient'):'mpd_acc_transient_man',
 ('BNF-Ha1','fun_transient_only'):'mpd_fun_ha1v2',
 ('BNF-Ha1','noacc_transient'):'mpd_noacc_transient_ha1',
 ('BNF-Ha1','acc_transient'):'mpd_acc_transient_ha1',
}
# (site,exp) -> §5.4 fixed-CO2/Ndep case prefix (Bonanza only so far)
SEC54={
 ('BNF-Bon','fun_transient_only'):'sec54_fun_bon',
 ('BNF-Bon','noacc_transient'):'sec54_noacc_bon',
 ('BNF-Bon','acc_transient'):'sec54_acc_bon',
 ('BNF-Bon','nofun_baseline'):'sec54_nofun_bon',
}

def find(prefix):
    d=glob.glob(f'{RR}/{prefix}_repro20260709_*/run') or glob.glob(f'{RR}/{prefix}_*/run')
    if not d: return None,None
    rd=d[0]; return rd, os.path.basename(os.path.dirname(rd))

print('==== §5.3 + §5.5 (continuous rebuild runs) ====')
for (site,exp),prefix in PREF.items():
    rd,case=find(prefix)
    if not rd: print(f'  {site}/{exp}: NO RUNDIR'); continue
    print(P.process([rd],case,1850,2014,site,exp,'53'),flush=True)
    print(P.process([rd],case,2015,2100,site,exp,'55'),flush=True)
print('==== §5.4 (fixed CO2/Ndep) where present ====')
for (site,exp),prefix in SEC54.items():
    rd,case=find(prefix)
    if not rd: print(f'  {site}/{exp}/sec54: not yet'); continue
    print(P.process([rd],case,2015,2100,site,exp,'54'),flush=True)
print('PACKAGE_DONE')
