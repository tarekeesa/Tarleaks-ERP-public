#!/bin/sh
# =============================================================================
# The scheduled jobs of one app (its "<app>-jobs" container in
# docker-compose.yml). Production runs these as Kubernetes CronJobs; on a
# server they run here, with the app's own image and settings.
#
#   run-jobs.sh 5m:sla-tick 1h:billing-tick 1d:retention-sweep 30d:retention-sweep
#
# Each argument is <every>:<subcommand>, <every> a number of minutes (m), hours
# (h) or days (d). Every job runs once JOBS_START_DELAY seconds after the
# container starts (default 120: the app finishes starting first), then again
# each time its interval has passed. One job at a time, each at most
# JOBS_TIMEOUT seconds (default 3600).
#
# A failed run is logged and tried again at the next interval: the container
# keeps going. A subcommand this release does not have (the program exits 2,
# "unknown subcommand") is logged once and left out until the next start.
# =============================================================================
set -u
log() { printf '%s jobs: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
seconds() { # 5m | 2h | 1d -> seconds, empty when not understood
  n=${1%?}
  case "$n" in ''|*[!0-9]*) return 0 ;; esac
  case "$1" in
    *m) echo $((n * 60)) ;;
    *h) echo $((n * 3600)) ;;
    *d) echo $((n * 86400)) ;;
  esac
}

[ $# -gt 0 ] || { log "no jobs given (usage: run-jobs.sh 5m:<subcommand> ...)"; exit 2; }
for job in "$@"; do
  every=${job%%:*}; sub=${job#*:}
  if [ -z "$(seconds "$every")" ] || [ "$sub" = "$job" ] || ! printf '%s' "$sub" | grep -qE '^[a-z][a-z0-9-]*$'; then
    log "cannot read the job '$job' (expected <every>:<subcommand>, for example 5m:sla-tick)"
    exit 2
  fi
done

stopping=0
trap 'stopping=1' TERM INT
state=$(mktemp -d)
delay=${JOBS_START_DELAY:-120}
limit=${JOBS_TIMEOUT:-3600}
log "scheduled: $*. First run in ${delay}s."
sleep "$delay" & wait $!

while [ "$stopping" = 0 ]; do
  for job in "$@"; do
    [ "$stopping" = 0 ] || break
    every=${job%%:*}; sub=${job#*:}
    f="$state/$sub.$every"
    [ -e "$f.off" ] && continue
    now=$(date +%s)
    last=0; [ -f "$f" ] && last=$(cat "$f")
    [ $((now - last)) -ge "$(seconds "$every")" ] || continue
    echo "$now" > "$f"
    rc=0
    timeout "$limit" /app/service "$sub" || rc=$?
    took=$(( $(date +%s) - now ))
    case "$rc" in
      0) [ "$(seconds "$every")" -lt 3600 ] || log "$sub done (${took}s); next in $every" ;;
      2) log "$sub is not in this release of the program: left out until the next start"; : > "$f.off" ;;
      124|143) log "$sub FAILED: still running after ${limit}s, stopped; next try in $every" ;;
      *) log "$sub FAILED (exit code $rc, ${took}s; its messages are above); next try in $every" ;;
    esac
  done
  sleep 20 & wait $!
done
log "stopping"
