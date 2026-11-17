# Backups

[← All services](../README.md)

Every night at 02:30 UTC, the `backup` stack:
1. Dumps the Postgres databases of Outline, NetBox and Umami.
2. Copies Pocket ID's and shorti's SQLite databases with SQLite's online backup, which stays consistent while the apps keep writing.
3. Sends those copies, plus the uploaded files of Outline, NetBox and Pocket ID (and NetBox's scripts), to restic.

restic encrypts everything on the VM, uploads only what changed, and keeps **7 daily, 4 weekly and 6 monthly** snapshots. It then checks the repository. Every morning, the [watchtower](../watchtower/README.md) checks the backups independently and test-restores the databases.

The backups go to the `backups` bucket that `bootstrap/` creates. Because that bucket isn't part of the main config, it survives even a full rebuild of the VM. The VM signs in to OCI as itself (an *instance principal*: see `backup.tf`), and a policy limits it to that one bucket. So the VM holds no cloud credentials. **The only secret is the restic password: without it, the backups can't be decrypted.**

The NetBird VM backs up its own data to a separate bucket: see [NetBird's backups](../netbird/README.md#netbirds-backups).

## One-time setup

1. **The bucket:** `cd bootstrap && terraform apply`. Expect 1 to add.
2. **The VM's permission:** `terraform apply` in the repo root. Expect 2 to add: the dynamic group and the policy. Policies can take a minute to take effect.
3. **The restic password, in 1Password:**
   ```sh
   op item create --vault=Homelab --category="Secure Note" --title="Backups" \
     "restic_password[password]=$(openssl rand -base64 32)"
   ```
4. **The settings:** copy the output of `terraform output -raw services_config` into `services/config.env`.
5. **Deploy, create the restic repository (once, ever), then run a first backup right away:**
   ```sh
   services/deploy.sh backup
   ssh <host> 'cd ~/services/backup && docker compose exec backup restic init'
   ssh <host> 'cd ~/services/backup && docker compose exec backup backup.sh'
   ```
   The backup should end with `no errors were found` and `== backup finished`. The nightly run never creates the repository itself. A failed read looks just like a missing repository, and initialising over an existing one would lock you out of every backup already in it.

   If restic says the repository doesn't exist right after `terraform apply`, a new policy can take a few minutes to apply everywhere. Wait, then try again.

The stack reaches into the other stacks' networks and volumes, so deploy those stacks first. `backup.sh` is built into the image: after changing it, deploy `backup` before running it by hand.

## Day to day

```sh
cd ~/services/backup                                    # on the VM
docker compose logs --tail 50 backup                    # last night's run
docker compose exec backup backup.sh                    # run a backup now
docker compose exec backup restic snapshots             # list snapshots
docker compose exec backup restic dump latest /staging/outline.sql | head   # peek into the latest one
```

Nobody reads those logs every day. To get an email when a night's backup fails or doesn't run, create a free check at [healthchecks.io](https://healthchecks.io) and put its ping URL in `BACKUP_PING_URL` in `services/config.env`. Then redeploy `backup`.

## Restoring

On the VM, first restore the latest snapshot into `~/restore` (use `restic snapshots` and a snapshot ID instead of `latest` for an older one):

```sh
cd ~/services/backup
docker compose run --rm -v ~/restore:/restore backup restic restore latest --target /restore
```

`~/restore/staging/` then holds the database copies and `~/restore/src/` the files. Restore only what you need, stopping each app first:

- **Outline database:**
  ```sh
  cd ~/services/outline && docker compose stop outline
  docker compose exec -T postgres psql -q -U outline -d outline < ~/restore/staging/outline.sql
  docker compose start outline
  ```
- **Outline files:**
  ```sh
  docker run --rm --entrypoint cp -v outline_files:/data -v ~/restore/src/outline-files:/from:ro services/backup:local -a /from/. /data/
  ```
- **NetBox database:**
  ```sh
  cd ~/services/netbox && docker compose stop netbox worker
  docker compose exec -T netbox-postgres psql -q -U netbox -d netbox < ~/restore/staging/netbox.sql
  docker compose start netbox worker
  ```
- **NetBox files** (uploads, reports and scripts):
  ```sh
  for v in media reports scripts; do
    docker run --rm --entrypoint cp -v netbox_$v:/data -v ~/restore/src/netbox-$v:/from:ro services/backup:local -a /from/. /data/
  done
  ```
- **Umami** (websites, accounts and every recorded visit):
  ```sh
  cd ~/services/umami && docker compose stop umami
  docker compose exec -T umami-postgres psql -q -U umami -d umami < ~/restore/staging/umami.sql
  docker compose start umami
  ```
- **Pocket ID** (users, passkeys, OIDC clients):
  ```sh
  cd ~/services/pocket-id && docker compose stop pocket-id
  docker run --rm --entrypoint sh -v pocket-id_data:/data -v ~/restore:/r:ro services/backup:local -c \
    'rm -f /data/pocket-id.db-wal /data/pocket-id.db-shm && cp /r/staging/pocket-id.db /data/pocket-id.db && cp -a /r/src/pocket-id/. /data/ && chown -R 1000:1000 /data'
  docker compose start pocket-id
  ```
- **shorti:**
  ```sh
  cd ~/services/shorti && docker compose stop api
  docker run --rm --entrypoint sh -v shorti_shorti-data:/data -v ~/restore:/r:ro services/backup:local -c \
    'rm -f /data/andy.db-wal /data/andy.db-shm && cat /r/staging/shorti.db > /data/andy.db'
  docker compose start api
  ```

**After a VM rebuild,** deploy the stacks first, so their volumes exist. Then restore as above. Rebuilding gives the VM a new OCID; `terraform apply` updates the dynamic group to match it.

Delete `~/restore` when you're done; it holds unencrypted copies of everything.
