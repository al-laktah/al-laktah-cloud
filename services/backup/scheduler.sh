#!/bin/sh
# Runs backup.sh once a day at BACKUP_TIME (HH:MM, UTC). This is a plain loop
# rather than cron, because cron jobs don't see the container's environment.
set -eu

time=${BACKUP_TIME:-02:30}
hour=${time%%:*}
minute=${time#*:}
target=$((${hour#0} * 3600 + ${minute#0} * 60)) # strip a leading 0 so 08 isn't read as octal

echo "backups run daily at $time UTC"
while true; do
  now=$(($(date -u +%s) % 86400))
  wait=$(((target - now + 86400) % 86400))
  if [ "$wait" -eq 0 ]; then wait=86400; fi
  sleep "$wait"
  backup.sh || true # a failed run is logged (and pinged); try again tomorrow
done
