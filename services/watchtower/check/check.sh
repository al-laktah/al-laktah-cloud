#!/bin/sh
# Daily, independent check of the backups, run from the watchtower instead of the
# VM that makes them. It only reads: every restic command uses --no-lock, and the
# watchtower's OCI policy allows nothing but reading the bucket. The result goes
# to Gatus, which alerts on a failure, or when no result arrives at all.
set -eu

started=$(date +%s)
step="starting"

report() { # report <true|false> <message>: push the result to Gatus
  # Gatus takes the message as a URL parameter; keep it to URL-safe characters.
  message=$(printf '%s' "$2" | tr -c 'A-Za-z0-9._:/-' '+')
  wget -q -T 10 -O /dev/null --post-data '' \
    --header "Authorization: Bearer $GATUS_PUSH_TOKEN" \
    "$GATUS_URL/api/v1/endpoints/backups_nightly-backup/external?success=$1&error=$message&duration=$(($(date +%s) - started))s" ||
    echo "could not reach Gatus"
}

ping() {
  # Optional dead man's switch for the watchtower itself (e.g. healthchecks.io):
  # if this VM dies, nothing on it can tell you, so something outside has to.
  if [ -n "${WATCHTOWER_PING_URL:-}" ]; then wget -q -T 10 -O /dev/null "$WATCHTOWER_PING_URL$1" || true; fi
}

pg() { psql --host=/tmp --username=postgres --no-psqlrc --quiet -v ON_ERROR_STOP=1 "$@"; }

on_exit() {
  status=$?
  # The restored copies are unencrypted, so they never outlive the check.
  if [ -f /tmp/pg/postmaster.pid ]; then su-exec postgres pg_ctl --pgdata=/tmp/pg --silent --mode=immediate stop || true; fi
  rm -rf /restore /tmp/pg
  if [ "$status" -ne 0 ]; then
    echo "== backup check FAILED: $step"
    report false "$step"
    ping /fail
  fi
}
trap on_exit EXIT

echo "== backup check started $(date -u +%FT%TZ)"
rm -rf /restore /tmp/pg

step="could not list the snapshots"
snapshots=$(restic --no-lock snapshots --tag nightly --json)
count=$(printf '%s' "$snapshots" | jq 'length')
echo "nightly snapshots in the repository: $count"
step="no nightly snapshots found"
[ "$count" -gt 0 ]
latest=$(printf '%s' "$snapshots" | jq -r 'max_by(.time) | .time')
step="could not read the snapshot time ($latest)"
latest_epoch=$(printf '%s' "$latest" | jq -R 'sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601')
age_hours=$((($(date +%s) - latest_epoch) / 3600))
echo "latest snapshot: $latest (${age_hours}h old)"
step="the latest backup is ${age_hours}h old"
[ "$age_hours" -lt "${MAX_BACKUP_AGE_HOURS:-26}" ]

# A different quarter of the data every day, so all of it is re-read every 4 days.
part=$(($(date +%s) / 86400 % 4 + 1))
step="restic check failed (data part $part/4)"
restic --no-lock check --read-data-subset="$part/4"

step="could not restore the databases"
restic --no-lock restore latest --tag nightly --target /restore --include /staging

for db in pocket-id shorti; do
  step="$db.db failed its integrity check"
  [ "$(sqlite3 "/restore/staging/$db.db" 'PRAGMA integrity_check')" = ok ]
  [ "$(sqlite3 "/restore/staging/$db.db" "SELECT count(*) FROM sqlite_master WHERE type = 'table'")" -gt 0 ]
done

step="the Outline database dump did not load into Postgres"
mkdir -p /tmp/pg
chown postgres:postgres /tmp/pg
su-exec postgres initdb --pgdata=/tmp/pg --username=postgres --auth=trust >/dev/null
su-exec postgres pg_ctl --pgdata=/tmp/pg --silent --wait --log=/tmp/pg.log \
  --options="-c listen_addresses='' -c unix_socket_directories=/tmp -c shared_buffers=32MB" start
pg -c 'CREATE ROLE outline' -c 'CREATE DATABASE outline OWNER outline'
pg --dbname=outline --file=/restore/staging/outline.sql >/dev/null
documents=$(pg --dbname=outline --tuples-only --no-align -c 'SELECT count(*) FROM documents')
su-exec postgres pg_ctl --pgdata=/tmp/pg --silent --wait stop

summary="snapshot ${age_hours}h old, $documents Outline documents, data part $part/4 verified"
echo "== backup check passed: $summary"
report true "$summary"
ping ""
