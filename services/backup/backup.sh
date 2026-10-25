#!/bin/sh
# One backup run. Each service's databases are copied consistently into /staging,
# then restic takes those copies plus the services' files: it encrypts them,
# uploads only what changed, applies the retention policy and checks the repository.
set -eu

ping() {
  # Optional dead man's switch (e.g. healthchecks.io). It alerts you when the pings
  # stop, the failure you would otherwise never notice.
  if [ -n "${BACKUP_PING_URL:-}" ]; then wget -q -T 10 -O /dev/null "$BACKUP_PING_URL$1" || true; fi
}
trap 'status=$?; if [ "$status" -ne 0 ]; then echo "== backup FAILED (exit $status)"; ping /fail; fi' EXIT

sqlite_backup() {
  # SQLite's online backup is consistent even while the app is writing. It runs as
  # the file's owner, so any lock files it creates stay usable by the app.
  owner=$(stat -c %u:%g "$1")
  su-exec "$owner" sqlite3 "$1" ".backup '$2'"
}

echo "== backup started $(date -u +%FT%TZ)"
ping /start

rm -rf /staging
mkdir -p /staging
chmod 1777 /staging # writable for the SQLite file owners, like /tmp

echo "== Outline database"
pg_dump --clean --if-exists --no-owner --file /staging/outline.sql # PG* variables come from compose.yaml

echo "== SQLite databases"
sqlite_backup /src/pocket-id/pocket-id.db /staging/pocket-id.db
sqlite_backup /src/shorti/andy.db /staging/shorti.db

echo "== restic"
# The repository is created once, by hand (see services/README.md), never here: a
# failed read looks just like a missing repository, and initialising over an
# existing one would lock you out of every backup already in it.
restic backup --tag nightly \
  --exclude '/src/pocket-id/pocket-id.db*' \
  --exclude '/src/shorti/andy.db*' \
  /staging /src/outline-files /src/pocket-id /src/shorti
restic forget --tag nightly --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune
restic check

ping ""
echo "== backup finished $(date -u +%FT%TZ)"
