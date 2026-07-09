#!/bin/bash
LOG=/home/braghiere/monitor_finish.log; exec >"$LOG" 2>&1
RR=/lustre/or-scratch24/scratch/braghiere
# Phase 1: wait until at least one sc_ job is RUNNING, verify it clears the lonc init
echo "=== [$(date +%H:%M)] Phase1: waiting for a shortcut job to start + clear CO2 init ==="
for i in $(seq 1 120); do
  rj=$(squeue -u braghiere -h -t RUNNING -o "%i %j" 2>/dev/null | grep -E "sc_.*transient" | head -1 | awk '{print $1}')
  if [ -n "$rj" ]; then
    sleep 60
    lg=$(ls -t $RR/sc_*/run/e3sm.log.$rj* 2>/dev/null | head -1)
    if [ -n "$lg" ]; then
      if grep -q "inq varid: lonc" "$lg" 2>/dev/null; then echo "  STILL failing on lonc ($rj) — CO2 fix insufficient"; 
      else echo "  job $rj RUNNING and PAST co2 init ✅ (log $(stat -c%s "$lg")b, no lonc error)"; fi
      break
    fi
  fi
  sleep 60
done
# Phase 2: monitor all sc_/ft_ transients to 2100
echo "=== [$(date +%H:%M)] Phase2: tracking transients to 2100 ==="
for i in $(seq 1 96); do
  done2100=$(ls $RR/{sc_,ft_}*_repro20260709_*/run/*.clm2.r.2101-01-01-00000.nc 2>/dev/null | wc -l)
  ntrans=$(ls -d $RR/{sc_,ft_}*_repro20260709_*_I20TR* 2>/dev/null | wc -l)
  echo "  [$(date +%H:%M)] transients reached 2100: $done2100 / $ntrans"
  [ "$done2100" -ge 9 ] && { echo "  >=9 transients complete (shortcut6 + transient-now3)"; break; }
  sleep 600
done
# Phase 3: continuity check on completed §5.3->§5.5 (2015 step)
echo "=== [$(date +%H:%M)] Phase3: 2015 continuity check ==="
timeout 300 python3 - <<'PY' 2>/dev/null
import glob,xarray as xr,numpy as np
RR='/lustre/or-scratch24/scratch/braghiere'; coder=xr.coders.CFDatetimeCoder(use_cftime=True)
for d in sorted(glob.glob(f'{RR}/sc_*_repro20260709_*/run')+glob.glob(f'{RR}/ft_*_repro20260709_*/run')):
    hs=sorted(glob.glob(f'{d}/*.clm2.h0.*.nc'))
    if len(hs)<200: continue
    try:
        ds=xr.open_mfdataset(hs,decode_times=coder,combine='by_coords'); yr=ds['time'].dt.year.values
        def mm(v,y):
            x=ds[v]; x=x.isel(lev=0) if 'lev' in x.dims else x; return float(np.nanmean(x.values[yr==y]))
        s14,s15=mm('SMINN',2014),mm('SMINN',2015); g15=mm('GPP',2015)*86400*365
        step=100*(s15-s14)/abs(s14) if s14 else 0
        nm=d.split('/')[-2].replace('_repro20260709','').replace('_I20TRCNPRDCTCBC','')
        print(f"  {nm:42s} GPP15={g15:6.0f} SMINN 2015 step={step:+5.0f}%  {'OK' if abs(step)<60 else 'CHECK'}")
        ds.close()
    except Exception as e: print(f"  {d.split('/')[-2][:42]}: {str(e)[:40]}")
PY
echo "MONITOR_DONE $(date)" > /home/braghiere/monitor_finish.DONE
