#!/bin/sh
# One backup run of NetBird's data: its SQLite databases are copied consistently
# into /staging, then restic takes those copies plus any other files in the data
# folder: it encrypts them, uploads only what changed, applies the retention
# policy and checks the repository. The watchtower verifies the result every day.
set -eu

src=/src/netbird # the server's data volume

on_exit() {
  status=$?
  if [ "$status" -ne 0 ]; then echo "== backup FAILED (exit $status)"; fi
}
trap on_exit EXIT

echo "== backup started $(date -u +%FT%TZ)"
[ -f "$src/store.db" ] || { echo "no $src/store.db: is the server's data volume mounted?" >&2; exit 1; }

rm -rf /staging
mkdir -p /staging

echo "== SQLite databases"
# store.db: accounts, peers, policies. idp.db: the built-in sign-in's users and
# keys. events.db: the activity log. SQLite's online backup is consistent even
# while the server is writing. Everything here runs as root, like the server.
for db in "$src"/*.db; do
  name=${db##*/}
  case $name in
  geonames_*) continue ;; # location data, downloaded again when missing
  esac
  echo "$name"
  sqlite3 "$db" ".backup '/staging/$name'"
done

echo "== restic"
# The repository is created once, by hand (see services/README.md), never here: a
# failed read looks just like a missing repository, and initialising over an
# existing one would lock you out of every backup already in it.
restic backup --tag nightly \
  --exclude "$src/*.db" --exclude "$src/*.db-*" \
  --exclude "$src/*.mmdb" \
  /staging "$src"
restic forget --tag nightly --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune
restic check

echo "== backup finished $(date -u +%FT%TZ)"
