#!/bin/sh
# Daily, independent check of the backups, run from the watchtower instead of the
# VMs that make them. It only reads: every restic command uses --no-lock, and the
# watchtower's OCI policy allows nothing but reading the buckets. The result goes
# to Gatus, which alerts on a failure, or when no result arrives at all.
#
#   check.sh main      the main VM's backups (services/backup)
#   check.sh netbird   the NetBird VM's backups (services/netbird)
set -eu

target=${1:-main}
case $target in
main) endpoint=backups_nightly-backup ;;
netbird)
  endpoint=backups_netbird-backup
  RESTIC_REPOSITORY=$NETBIRD_RESTIC_REPOSITORY
  export RESTIC_REPOSITORY
  ;;
*)
  echo "usage: check.sh [main|netbird]" >&2
  exit 2
  ;;
esac

started=$(date +%s)
step="starting"

report() { # report <true|false> <message>: push the result to Gatus
  # Gatus takes the message as a URL parameter; keep it to URL-safe characters.
  message=$(printf '%s' "$2" | tr -c 'A-Za-z0-9._:/-' '+')
  wget -q -T 10 -O /dev/null --post-data '' \
    --header "Authorization: Bearer $GATUS_PUSH_TOKEN" \
    "$GATUS_URL/api/v1/endpoints/$endpoint/external?success=$1&error=$message&duration=$(($(date +%s) - started))s" ||
    echo "could not reach Gatus"
}

pg() { psql --host=/tmp --username=postgres --no-psqlrc --quiet -v ON_ERROR_STOP=1 "$@"; }

on_exit() {
  status=$?
  # The restored copies are unencrypted, so they never outlive the check.
  if [ -f /tmp/pg/postmaster.pid ]; then su-exec postgres pg_ctl --pgdata=/tmp/pg --silent --mode=immediate stop || true; fi
  rm -rf /restore /tmp/pg
  if [ "$status" -ne 0 ]; then
    echo "== $target backup check FAILED: $step"
    report false "$step"
  fi
}
trap on_exit EXIT

echo "== $target backup check started $(date -u +%FT%TZ)"
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

sqlite_ok() { # sqlite_ok <file>: the file is a healthy SQLite database with tables
  step="${1##*/} is missing or failed its integrity check"
  [ -f "$1" ]
  [ "$(sqlite3 "$1" 'PRAGMA integrity_check')" = ok ]
  [ "$(sqlite3 "$1" "SELECT count(*) FROM sqlite_master WHERE type = 'table'")" -gt 0 ]
}

case $target in
main)
  sqlite_ok /restore/staging/pocket-id.db
  sqlite_ok /restore/staging/shorti.db

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
  ;;
netbird)
  # store.db must be there; every other database that was backed up must be healthy too.
  sqlite_ok /restore/staging/store.db
  for db in /restore/staging/*.db; do sqlite_ok "$db"; done

  step="the NetBird store has no account"
  [ "$(sqlite3 /restore/staging/store.db 'SELECT count(*) FROM accounts')" -gt 0 ]
  peers=$(sqlite3 /restore/staging/store.db 'SELECT count(*) FROM peers')

  summary="snapshot ${age_hours}h old, $peers NetBird peers, data part $part/4 verified"
  ;;
esac

echo "== $target backup check passed: $summary"
report true "$summary"
