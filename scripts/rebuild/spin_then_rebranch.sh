#!/bin/bash
exec > /home/braghiere/spin_then_rebranch.out 2>&1
RR=/lustre/or-scratch24/scratch/braghiere
COMBOS="fun_bon noacc_bon acc_bon fun_man noacc_man acc_man fun_ha1 noacc_ha1 acc_ha1"
echo "monitor start $(date); waiting for all 9 spin-ups to reach r.0301"
for i in $(seq 1 120); do
  ready=0
  for c in $COMBOS; do
    ls $RR/spinCNP_${c}_*/run/*.clm2.r.0301-01-01-00000.nc >/dev/null 2>&1 && ready=$((ready+1))
  done
  echo "  [$i] $(date +%H:%M) spun-up ready: $ready/9"
  [ $ready -ge 9 ] && break
  sleep 300
done
echo "=== spin-ups ready ($ready/9). Launching re-branch ==="
bash /home/braghiere/rebranch.sh
echo "=== re-branch results ==="
grep -E "rebranch su_|BUILD FAIL|CREATE FAIL|MISSING|REBRANCH_DONE" /home/braghiere/rebranch.log 2>/dev/null
echo "SPIN_THEN_REBRANCH_DONE $(date)"
