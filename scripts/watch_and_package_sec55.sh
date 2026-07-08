#!/bin/bash
# watch_and_package_sec55.sh
# Polls SLURM until all 12 SSP585 jobs finish, then runs §5.5 packaging.
# Run as: nohup bash watch_and_package_sec55.sh &

LOGFILE="/home/braghiere/ELM-FUN-BNFMIP/scripts/sec55_watch.log"
SCRIPT="/home/braghiere/ELM-FUN-BNFMIP/scripts/package_bnfmip_outputs.py"

# The 12 correct SSP585 job IDs (from CaseStatus last success)
JOBS="5430435 5430436 5430437 5430438 5430439 5430440 5430441 5430442 5430443 5430444 5430445 5430446"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE"
}

log "=== §5.5 watcher started ==="
log "Monitoring jobs: $JOBS"

while true; do
    # Count how many of the 12 jobs are still in queue
    still_running=0
    completed=0
    failed_ids=()
    for jid in $JOBS; do
        state=$(squeue -j "$jid" -h -o "%T" 2>/dev/null)
        if [ -z "$state" ]; then
            # Job not in queue — check sacct for completion state
            final=$(sacct -j "$jid" -n -o State --parsable2 2>/dev/null | head -1)
            if [ "$final" = "COMPLETED" ]; then
                ((completed++))
            elif [ -n "$final" ] && [ "$final" != "COMPLETED" ]; then
                log "  WARNING: job $jid finished with state: $final"
                failed_ids+=("$jid")
                ((completed++))  # count as done even if failed
            else
                ((completed++))  # no sacct info, assume done
            fi
        else
            ((still_running++))
        fi
    done

    log "Status: $still_running running, $completed done out of 12"

    if [ "$still_running" -eq 0 ]; then
        log "All 12 SSP585 jobs finished!"
        if [ ${#failed_ids[@]} -gt 0 ]; then
            log "WARNING: These jobs did not complete successfully: ${failed_ids[*]}"
        fi
        break
    fi

    sleep 300  # poll every 5 minutes
done

log "Starting §5.5 packaging..."
python3 -u "$SCRIPT" --section 55 >> "$LOGFILE" 2>&1
rc=$?

if [ $rc -eq 0 ]; then
    log "§5.5 packaging complete!"
    log "Delivery directory: /home/braghiere/BNF_tom/delivery"
    log "Files:"
    find /home/braghiere/BNF_tom/delivery -name "*sec55*.nc" | sort >> "$LOGFILE"
else
    log "ERROR: §5.5 packaging failed (rc=$rc)"
fi
