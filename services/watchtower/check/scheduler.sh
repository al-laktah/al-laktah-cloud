#!/bin/sh
# Runs the backup checks once a day at CHECK_TIME (HH:MM, UTC). This is a plain
# loop rather than cron, because cron jobs don't see the container's environment.
set -eu

ping() {
  # Optional dead man's switch for the watchtower itself (e.g. healthchecks.io):
  # if this VM dies, nothing on it can tell you, so something outside has to.
  if [ -n "${WATCHTOWER_PING_URL:-}" ]; then wget -q -T 10 -O /dev/null "$WATCHTOWER_PING_URL$1" || true; fi
}

time=${CHECK_TIME:-06:00}
hour=${time%%:*}
minute=${time#*:}
target=$((${hour#0} * 3600 + ${minute#0} * 60)) # strip a leading 0 so 08 isn't read as octal

echo "backup checks run daily at $time UTC"
while true; do
  now=$(($(date -u +%s) % 86400))
  wait=$(((target - now + 86400) % 86400))
  if [ "$wait" -eq 0 ]; then wait=86400; fi
  sleep "$wait"
  # /start lets healthchecks.io time the run and notice one that never finishes.
  ping /start
  # Each check reports to Gatus itself; try again tomorrow if one fails.
  ok=yes
  check.sh main || ok=no
  check.sh netbird || ok=no
  if [ "$ok" = yes ]; then ping ""; else ping /fail; fi
done
